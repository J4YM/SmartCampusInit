-- Schema additions for the Admin Dashboard UI (packages/admin_dashboard),
-- integrated from CipherPunk-7800/Capstone-Project ("Admin Dashboard/").
--
-- Most dashboard pages (Overview, Student Directory, RFID Mapping, ML &
-- Thresholds, Notifications, Reports & Exports, Settings) are still UI-only
-- placeholders (`.empty()` factories, no Supabase calls yet) and need no
-- schema changes until they're wired up. Two things ARE concrete gaps
-- against dbschema.md today:
--
--   1. Staff Accounts page needs profile fields (department, phone,
--      active/inactive) that `profiles` doesn't have, plus an Admin-wide
--      RLS policy — today only self-select/self-update + linked-student/
--      parent reads exist, so an Admin can't list or manage other staff.
--   2. Audit & Privacy Logs page needs an `audit_logs` table — flagged as
--      a planned capability in lib/admin/admin_module_scope.dart
--      ("Audit trails for every login and sensitive data access (RA
--      10173)") but never modeled in the database.
--
-- Run in Supabase SQL Editor.

-- ---------------------------------------------------------------------------
-- 1. Staff account fields on `profiles`
-- ---------------------------------------------------------------------------

alter table public.profiles
  add column if not exists department text,
  add column if not exists phone_number text,
  add column if not exists is_active boolean not null default true,
  add column if not exists last_login_at timestamptz;

-- Admin needs to list/edit every staff profile (Staff Accounts page), not
-- just their own row or students/parents linked to them.
drop policy if exists "profiles_admin_manage_staff" on public.profiles;
create policy "profiles_admin_manage_staff"
  on public.profiles
  for all
  to authenticated
  using (current_user_role() = 'Admin'::app_role)
  with check (current_user_role() = 'Admin'::app_role);

-- ---------------------------------------------------------------------------
-- 2. Audit & Privacy Logs
-- ---------------------------------------------------------------------------

do $$ begin
  create type public.audit_severity as enum ('INFO', 'WARN', 'CRITICAL');
exception
  when duplicate_object then null;
end $$;

-- Append-only: no `updated_at` — audit entries are never edited in place.
create table if not exists public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  occurred_at timestamptz not null default now(),
  actor_id uuid references public.profiles(id) on delete set null,
  actor_email text not null,
  actor_role app_role not null,
  action text not null,
  ip_address text,
  record_id text,
  severity audit_severity not null default 'INFO',
  created_at timestamptz not null default now()
);

create index if not exists audit_logs_occurred_at_idx
  on public.audit_logs (occurred_at desc);

alter table public.audit_logs enable row level security;

-- Only Admins review the audit trail; every other role is excluded by
-- omission (no policy = no access once RLS is enabled).
drop policy if exists "audit_logs_admin_select" on public.audit_logs;
create policy "audit_logs_admin_select"
  on public.audit_logs
  for select
  to authenticated
  using (current_user_role() = 'Admin'::app_role);

-- Any authenticated backend action can append an entry; entries can never
-- be updated or deleted (no update/delete policy is defined on purpose).
drop policy if exists "audit_logs_authenticated_insert" on public.audit_logs;
create policy "audit_logs_authenticated_insert"
  on public.audit_logs
  for insert
  to authenticated
  with check (true);
