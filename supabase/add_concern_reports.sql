-- Concern Reports: a student reports a concern to Student Affairs (the
-- Discipline Officer role). This is the old "referral" route that ended at the
-- DO, under its new name. Self referrals for counseling now go to Guidance
-- only (add_guidance_referrals.sql).
--
--   * concern_reports: one row per report. student_id is the reporter;
--     about_student_id is only set on rows migrated from an old classmate
--     referral (the form no longer asks for another student).
--   * submit_concern_report / my_concern_reports: the only way a student
--     creates / lists their own.
--   * Old DO-bound referrals are copied here with the SAME id: every one of
--     them was DO-bound, so every one becomes a Concern (self referrals
--     included) and the endorsement links survive. add_guidance_referrals.sql
--     then clears them out of the Guidance table, which starts fresh.
--   * escalation_reports.referral_id becomes concern_id and points here.
--
-- Run in Supabase SQL Editor after add_endorsements.sql. Idempotent.
-- Run add_guidance_referrals.sql afterwards.

-- ---------------------------------------------------------------------------
-- 1. Table
-- ---------------------------------------------------------------------------

create table if not exists public.concern_reports (
  id uuid primary key default gen_random_uuid(),
  -- The student who filed it.
  student_id uuid not null references public.students(id) on delete cascade,
  -- Only on rows migrated from an old classmate referral.
  about_student_id uuid references public.students(id) on delete set null,
  -- 'academic' | 'attendance' | 'behavior' | 'bullying' | 'safety' | 'other'
  -- (the older emotional / family values are kept for migrated rows)
  concern text not null default 'other',
  details text not null default '',
  urgency text not null default 'Normal',
  status text not null default 'Pending',
  -- Visible to the reporter on their dashboard.
  handler_note text,
  handled_by uuid references public.profiles(id) on delete set null,
  handled_at timestamptz,
  created_at timestamptz not null default now(),
  constraint concern_reports_status_check
    check (status in ('Pending', 'In_Progress', 'Closed')),
  constraint concern_reports_urgency_check
    check (urgency in ('Normal', 'Urgent')),
  constraint concern_reports_concern_check
    check (concern in ('academic', 'attendance', 'behavior', 'emotional',
                       'family', 'bullying', 'safety', 'other'))
);

create index if not exists concern_reports_status_idx
  on public.concern_reports (status, created_at desc);
create index if not exists concern_reports_student_idx
  on public.concern_reports (student_id, created_at desc);

alter table public.concern_reports enable row level security;

-- Student Affairs works them; Guidance never reads them.
drop policy if exists "concern_reports_staff_select" on public.concern_reports;
create policy "concern_reports_staff_select" on public.concern_reports
  for select to authenticated
  using (current_user_role() in ('Admin'::app_role, 'Discipline_Officer'::app_role));

drop policy if exists "concern_reports_staff_update" on public.concern_reports;
create policy "concern_reports_staff_update" on public.concern_reports
  for update to authenticated
  using (current_user_role() in ('Admin'::app_role, 'Discipline_Officer'::app_role))
  with check (current_user_role() in ('Admin'::app_role, 'Discipline_Officer'::app_role));

-- Demo mode: static demo accounts run under the anon key (same tradeoff as
-- add_student_referrals.sql). Tighten before production.
drop policy if exists "concern_reports_anon_select" on public.concern_reports;
create policy "concern_reports_anon_select" on public.concern_reports
  for select to anon using (true);
drop policy if exists "concern_reports_anon_update" on public.concern_reports;
create policy "concern_reports_anon_update" on public.concern_reports
  for update to anon using (true) with check (true);

-- ---------------------------------------------------------------------------
-- 2. submit_concern_report / my_concern_reports
-- ---------------------------------------------------------------------------

create or replace function public.submit_concern_report(
  p_reporter_id uuid,
  p_concern text,
  p_details text,
  p_urgent boolean default false
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_urgency text := case when p_urgent then 'Urgent' else 'Normal' end;
  v_concern text := coalesce(nullif(btrim(p_concern), ''), 'other');
  v_id uuid;
begin
  if auth.role() = 'authenticated' and p_reporter_id is distinct from auth.uid() then
    raise exception 'You can only file a concern report as yourself.' using errcode = '42501';
  end if;

  if not exists (select 1 from public.students where id = p_reporter_id) then
    raise exception 'Only a student can file a concern report.';
  end if;

  if coalesce(btrim(p_details), '') = '' then
    raise exception 'Please describe your concern.';
  end if;

  -- A sensitive topic is never left as a routine report.
  if to_regproc('public.find_sensitive_terms(text)') is not null then
    if coalesce(array_length(public.find_sensitive_terms(p_details), 1), 0) > 0 then
      v_urgency := 'Urgent';
    end if;
  end if;
  if v_concern in ('safety', 'bullying') then
    v_urgency := 'Urgent';
  end if;

  insert into public.concern_reports (student_id, concern, details, urgency)
  values (p_reporter_id, v_concern, btrim(p_details), v_urgency)
  returning id into v_id;

  return v_id;
end;
$$;

revoke all on function public.submit_concern_report(uuid, text, text, boolean) from public;
grant execute on function public.submit_concern_report(uuid, text, text, boolean)
  to anon, authenticated;

create or replace function public.my_concern_reports(p_reporter_id uuid)
returns table (
  id uuid,
  concern text,
  urgency text,
  status text,
  handler_note text,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select c.id, c.concern, c.urgency, c.status, c.handler_note, c.created_at
    from public.concern_reports c
   where c.student_id = p_reporter_id
     and (auth.role() <> 'authenticated' or p_reporter_id = auth.uid())
   order by c.created_at desc;
$$;

revoke all on function public.my_concern_reports(uuid) from public;
grant execute on function public.my_concern_reports(uuid) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. Tell Student Affairs
-- ---------------------------------------------------------------------------

create or replace function public.trg_notify_concern_report()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.notifications (target_role, title, message)
  values (
    'Discipline_Officer'::app_role,
    case when new.urgency = 'Urgent'
      then 'Urgent concern report'
      else 'New concern report' end,
    public.sms_student_name(new.student_id)
      || ' filed a concern report. Review it under Concerns.'
  );
  return new;
exception when others then
  raise warning 'trg_notify_concern_report failed: %', sqlerrm;
  return new;
end;
$$;

drop trigger if exists concern_reports_notify on public.concern_reports;
create trigger concern_reports_notify
  after insert on public.concern_reports
  for each row execute function public.trg_notify_concern_report();

-- ---------------------------------------------------------------------------
-- 4. Copy the old DO-bound referrals (same ids). Safe to re-run. The notify
--    trigger is paused so Student Affairs is not told about old reports.
-- ---------------------------------------------------------------------------

do $$
begin
  -- Every old referral was DO-bound, so every one becomes a Concern. Only
  -- before add_guidance_referrals.sql has reshaped the table (it adds
  -- `source`): afterwards its rows are Guidance's own.
  if to_regclass('public.student_referrals') is not null
     and not exists (
       select 1 from information_schema.columns
        where table_schema = 'public' and table_name = 'student_referrals'
          and column_name = 'source') then
    alter table public.concern_reports disable trigger concern_reports_notify;
    insert into public.concern_reports
      (id, student_id, about_student_id, concern, details, urgency, status,
       handler_note, handled_by, handled_at, created_at)
    select r.id,
           r.referred_by,
           case when r.is_self then null else r.student_id end,
           r.concern, r.details, r.urgency, r.status,
           r.counselor_note, r.handled_by, r.handled_at, r.created_at
      from public.student_referrals r
     where exists (select 1 from public.students s where s.id = r.referred_by)
    on conflict (id) do nothing;
    alter table public.concern_reports enable trigger concern_reports_notify;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 5. Endorsements link to a concern report (referral_id -> concern_id)
-- ---------------------------------------------------------------------------

do $$
begin
  if exists (select 1 from information_schema.columns
              where table_schema = 'public' and table_name = 'escalation_reports'
                and column_name = 'referral_id') then
    alter table public.escalation_reports
      drop constraint if exists escalation_reports_referral_id_fkey;
    -- A link to a self referral nobody copied above would dangle: clear it.
    update public.escalation_reports e
       set referral_id = null
     where referral_id is not null
       and not exists (select 1 from public.concern_reports c where c.id = e.referral_id);
    alter table public.escalation_reports rename column referral_id to concern_id;
  end if;
end $$;

alter table public.escalation_reports
  drop constraint if exists escalation_reports_concern_id_fkey;
alter table public.escalation_reports
  add constraint escalation_reports_concern_id_fkey
  foreign key (concern_id) references public.concern_reports(id) on delete set null;

drop index if exists public.escalation_reports_referral_uidx;
drop index if exists public.escalation_reports_concern_uidx;
create unique index escalation_reports_concern_uidx
  on public.escalation_reports (concern_id)
  where concern_id is not null and status <> 'Rejected';

-- A concern is endorsed once, never after it is closed.
create or replace function public.trg_endorsement_referral_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status text;
  v_student uuid;
begin
  if new.concern_id is null then
    return new;
  end if;
  -- A migrated classmate report is about the classmate, not the reporter.
  select status, coalesce(about_student_id, student_id) into v_status, v_student
    from public.concern_reports where id = new.concern_id;
  if v_status is null then
    raise exception 'Concern report not found.';
  end if;
  if v_student is distinct from new.student_id then
    raise exception 'This concern report is about a different student.';
  end if;
  if v_status = 'Closed' then
    raise exception 'This concern report is already closed.';
  end if;
  return new;
end;
$$;

create or replace function public.trg_endorsement_referral_progress()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.concern_id is not null then
    update public.concern_reports
       set status = 'In_Progress',
           handled_by = coalesce(handled_by, auth.uid()),
           handled_at = coalesce(handled_at, now())
     where id = new.concern_id and status <> 'Closed';
  end if;
  return new;
end;
$$;
