-- IT Technician role + technical-issue ticketing (offline device/reader,
-- offline kiosk, classroom PC problems). See
-- docs/superpowers/specs/2026-08-23-it-technician-dashboard-design.md.
--
-- Run in Supabase SQL Editor, after add_notifications_schema.sql and
-- add_notifications_user_targeting.sql (this reuses that table's dual
-- target_role/target_user_id routing) and add_rfid_reader_network_schema.sql
-- (referenced only in comments below).

-- ---------------------------------------------------------------------------
-- 1. New role value on the shared app_role enum.
-- ---------------------------------------------------------------------------

alter type public.app_role add value if not exists 'IT_Technician';

-- ---------------------------------------------------------------------------
-- 2. Ticket tables.
-- ---------------------------------------------------------------------------

do $$ begin
  create type public.technical_issue_category as enum (
    'offline_device', 'offline_kiosk', 'classroom_pc', 'other'
  );
exception
  when duplicate_object then null;
end $$;

do $$ begin
  create type public.technical_issue_status as enum (
    'open', 'in_progress', 'resolved'
  );
exception
  when duplicate_object then null;
end $$;

create table if not exists public.technical_issue_reports (
  id uuid primary key default gen_random_uuid(),
  category public.technical_issue_category not null,
  description text not null,
  location text,
  reported_by uuid not null references public.profiles(id),
  -- Denormalized so a resolved ticket still shows "reported by a Teacher"
  -- even if that profile is later deleted — matches the `app_role` db
  -- value convention (see lib/auth/app_role.dart's appRoleToDbValue).
  reported_by_role text not null,
  status public.technical_issue_status not null default 'open',
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by uuid references public.profiles(id)
);

create index if not exists technical_issue_reports_status_idx
  on public.technical_issue_reports (status, created_at desc);

alter table public.technical_issue_reports enable row level security;

drop policy if exists "technical_issue_reports_insert" on public.technical_issue_reports;
create policy "technical_issue_reports_insert"
  on public.technical_issue_reports
  for insert
  to authenticated
  with check (current_user_role() in ('Teacher'::app_role, 'Admin'::app_role));

-- IT Technician + Admin see every ticket; a reporter sees their own.
drop policy if exists "technical_issue_reports_select" on public.technical_issue_reports;
create policy "technical_issue_reports_select"
  on public.technical_issue_reports
  for select
  to authenticated
  using (
    current_user_role() in ('IT_Technician'::app_role, 'Admin'::app_role)
    or auth.uid() = reported_by
  );

drop policy if exists "technical_issue_reports_update" on public.technical_issue_reports;
create policy "technical_issue_reports_update"
  on public.technical_issue_reports
  for update
  to authenticated
  using (current_user_role() in ('IT_Technician'::app_role, 'Admin'::app_role))
  with check (current_user_role() in ('IT_Technician'::app_role, 'Admin'::app_role));

-- Demo-mode anon access — same tradeoff as every other table's anon policy
-- in this project (static demo accounts have no JWT). Tighten before
-- production.
drop policy if exists "technical_issue_reports_anon_all" on public.technical_issue_reports;
create policy "technical_issue_reports_anon_all"
  on public.technical_issue_reports
  for all
  to anon
  using (true)
  with check (true);

create table if not exists public.technical_issue_comments (
  id uuid primary key default gen_random_uuid(),
  report_id uuid not null references public.technical_issue_reports(id) on delete cascade,
  author_id uuid not null references public.profiles(id),
  author_role text not null,
  message text not null,
  created_at timestamptz not null default now()
);

create index if not exists technical_issue_comments_report_idx
  on public.technical_issue_comments (report_id, created_at);

alter table public.technical_issue_comments enable row level security;

drop policy if exists "technical_issue_comments_insert" on public.technical_issue_comments;
create policy "technical_issue_comments_insert"
  on public.technical_issue_comments
  for insert
  to authenticated
  with check (
    current_user_role() in ('IT_Technician'::app_role, 'Admin'::app_role)
    or auth.uid() = (
      select reported_by from public.technical_issue_reports where id = report_id
    )
  );

drop policy if exists "technical_issue_comments_select" on public.technical_issue_comments;
create policy "technical_issue_comments_select"
  on public.technical_issue_comments
  for select
  to authenticated
  using (
    current_user_role() in ('IT_Technician'::app_role, 'Admin'::app_role)
    or auth.uid() = (
      select reported_by from public.technical_issue_reports where id = report_id
    )
  );

drop policy if exists "technical_issue_comments_anon_all" on public.technical_issue_comments;
create policy "technical_issue_comments_anon_all"
  on public.technical_issue_comments
  for all
  to anon
  using (true)
  with check (true);

-- ---------------------------------------------------------------------------
-- 3. RPCs. Both take the actor's id/role as explicit parameters rather than
--    relying on auth.uid()/current_user_role() — the static demo accounts
--    (lib/auth/static_demo_accounts.dart) never hold a real Supabase Auth
--    session, the same reason record_rfid_tap and every *_id column in this
--    project's demo-friendly RPCs work this way.
-- ---------------------------------------------------------------------------

create or replace function public.report_technical_issue(
  p_category public.technical_issue_category,
  p_description text,
  p_reporter_id uuid,
  p_reporter_role text,
  p_location text default null
)
returns public.technical_issue_reports
language plpgsql
security definer
set search_path = public
as $$
declare
  v_report public.technical_issue_reports;
begin
  insert into public.technical_issue_reports (
    category, description, location, reported_by, reported_by_role
  )
  values (
    p_category, p_description, p_location, p_reporter_id, p_reporter_role
  )
  returning * into v_report;

  insert into public.notifications (target_role, title, message)
  values (
    'IT_Technician'::app_role,
    'New technical issue reported',
    p_description
  );

  return v_report;
end;
$$;

revoke all on function public.report_technical_issue(
  public.technical_issue_category, text, uuid, text, text
) from public;
grant execute on function public.report_technical_issue(
  public.technical_issue_category, text, uuid, text, text
) to anon, authenticated;

create or replace function public.add_technical_issue_comment(
  p_report_id uuid,
  p_message text,
  p_author_id uuid,
  p_author_role text
)
returns public.technical_issue_comments
language plpgsql
security definer
set search_path = public
as $$
declare
  v_comment public.technical_issue_comments;
  v_reporter_id uuid;
begin
  insert into public.technical_issue_comments (
    report_id, author_id, author_role, message
  )
  values (
    p_report_id, p_author_id, p_author_role, p_message
  )
  returning * into v_comment;

  select reported_by into v_reporter_id
    from public.technical_issue_reports
    where id = p_report_id;

  -- IT Technician/Admin replying routes straight back to the original
  -- reporter; the reporter replying broadcasts to IT Technician again.
  if p_author_role in ('IT_Technician', 'Admin') then
    insert into public.notifications (target_role, title, message, user_id)
    values (
      'Teacher'::app_role,
      'Update on your technical issue report',
      p_message,
      v_reporter_id
    );
  else
    insert into public.notifications (target_role, title, message)
    values (
      'IT_Technician'::app_role,
      'New reply on a technical issue report',
      p_message
    );
  end if;

  return v_comment;
end;
$$;

revoke all on function public.add_technical_issue_comment(
  uuid, text, uuid, text
) from public;
grant execute on function public.add_technical_issue_comment(
  uuid, text, uuid, text
) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 4. Realtime — matches add_notifications_schema.sql's pattern so a future
--    ticket-list live-refresh can subscribe the same way the bell already
--    does. Idempotent.
-- ---------------------------------------------------------------------------
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'technical_issue_reports'
  ) then
    alter publication supabase_realtime add table public.technical_issue_reports;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'technical_issue_comments'
  ) then
    alter publication supabase_realtime add table public.technical_issue_comments;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 5. Demo IT Technician system profile — same reasoning and pattern as the
--    demo Professor system profile in add_professor_module_schema.sql: the
--    static `ittech.demo` account (lib/auth/static_demo_accounts.dart) never
--    calls Supabase Auth, so it has no real `profiles.id` to satisfy
--    `technical_issue_comments.author_id` / `technical_issue_reports.resolved_by`
--    (both `references public.profiles(id)`). This fixed id is referenced
--    directly by lib/ui/it_technician_connected_page.dart — keep the two in
--    sync if it ever changes. Real Microsoft-authenticated IT Technician
--    accounts use their own actual profile id instead and never touch this
--    row.
-- ---------------------------------------------------------------------------
do $$
declare
  v_it_technician_id uuid := '00000000-0000-4000-8000-000000000099';
begin
  insert into auth.users (
    id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, is_anonymous, created_at, updated_at
  )
  values (
    v_it_technician_id, '00000000-0000-0000-0000-000000000000'::uuid, 'authenticated', 'authenticated',
    'ittech.demo@baliuag.sti.edu.ph', crypt('demo-system-not-a-real-login', gen_salt('bf')), now(),
    '{"provider":"system","providers":["system"]}'::jsonb, '{}'::jsonb, false, now(), now()
  )
  on conflict (id) do nothing;

  insert into public.profiles (
    id, email, first_name, last_name, role, status, department, is_active, created_at
  )
  values (
    v_it_technician_id, 'ittech.demo@baliuag.sti.edu.ph',
    'IT', 'Technician', 'IT_Technician'::app_role, 'approved'::approval_status,
    'Information Technology', true, now()
  )
  on conflict (id) do update set
    role = excluded.role,
    status = excluded.status,
    department = excluded.department,
    is_active = excluded.is_active;
end $$;
