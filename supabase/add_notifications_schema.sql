-- Centralized notification system backing the Admin Dashboard's
-- Notifications page (packages/admin_dashboard/lib/pages/notifications) and
-- the notification bell already scaffolded (but always empty/mock) on the
-- Discipline Officer, Guidance Counselor, and Professor dashboards.
--
-- Each "Automated Trigger Rule" on the Notifications page is a button, not a
-- toggle: pressing it (after a confirm prompt) inserts one row here targeted
-- at the role that owns that event. Every dashboard whose role matches
-- `target_role` reads its own rows for its bell — this table IS the
-- centralized system, not per-module local state.
--
-- Run in Supabase SQL Editor.

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  target_role app_role not null,
  title text not null,
  message text not null,
  created_at timestamptz not null default now(),
  read_at timestamptz
);

create index if not exists notifications_target_role_idx
  on public.notifications (target_role, created_at desc);

alter table public.notifications enable row level security;

-- A role reads only its own targeted notifications; Admin can also read
-- everything (it's the module that sends them, and is itself a target for
-- some events like "RFID Gateway Offline").
drop policy if exists "notifications_role_select" on public.notifications;
create policy "notifications_role_select"
  on public.notifications
  for select
  to authenticated
  using (
    current_user_role() = target_role
    or current_user_role() = 'Admin'::app_role
  );

-- Only Admin's Notifications page sends (inserts) notifications.
drop policy if exists "notifications_admin_insert" on public.notifications;
create policy "notifications_admin_insert"
  on public.notifications
  for insert
  to authenticated
  with check (current_user_role() = 'Admin'::app_role);

-- A role marks only its own notifications read (bell "view all"/dismiss).
drop policy if exists "notifications_role_update_own" on public.notifications;
create policy "notifications_role_update_own"
  on public.notifications
  for update
  to authenticated
  using (current_user_role() = target_role)
  with check (current_user_role() = target_role);

-- ---------------------------------------------------------------------------
-- Demo-mode anon access — the static demo accounts (lib/auth/
-- static_demo_accounts.dart) never authenticate via Supabase Auth, so every
-- request goes out under the plain anon key with no JWT and no
-- current_user_role(). Same tradeoff as rls_discipline_demo_anon.sql: this
-- makes the table fully readable/writable by anyone holding the public anon
-- key. Fine for local development/demo; tighten before production.
-- ---------------------------------------------------------------------------
drop policy if exists "notifications_anon_select_all" on public.notifications;
create policy "notifications_anon_select_all"
  on public.notifications
  for select
  to anon
  using (true);

drop policy if exists "notifications_anon_insert_all" on public.notifications;
create policy "notifications_anon_insert_all"
  on public.notifications
  for insert
  to anon
  with check (true);

drop policy if exists "notifications_anon_update_all" on public.notifications;
create policy "notifications_anon_update_all"
  on public.notifications
  for update
  to anon
  using (true)
  with check (true);

-- ---------------------------------------------------------------------------
-- Realtime — lets every dashboard's bell live-update when a notification
-- targeted at it is inserted, matching add_realtime_publication.sql's
-- pattern for student_violations. Idempotent (errors if already a member).
-- ---------------------------------------------------------------------------
do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'notifications'
  ) then
    alter publication supabase_realtime add table public.notifications;
  end if;
end $$;
