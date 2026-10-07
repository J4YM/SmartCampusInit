-- Guidance Counselor archival logs: a confidential, per-student record of
-- past interventions, counseling sessions, parent conferences, referrals
-- and similar. Shown in the Guidance Counselor dashboard's "Student Archive"
-- tab (expand a student to view, add or delete their logs).
--
-- Confidentiality
--   * Only the Guidance Counselor can add or delete logs; Admin can read
--     (audit) but not write. Student Affairs, professors, students and
--     parents have no policy at all, so they cannot read these rows.
--   * There is no update: a wrong entry is deleted and re-added, so every
--     change leaves an audit_logs trail (the app writes view/add/delete
--     entries via AuditLogger).
--   * DEMO TRADEOFF (chosen explicitly): the static demo accounts run under
--     the plain anon key, so the anon policies below let ANYONE holding that
--     key read and write these rows. Use fake data only while they exist,
--     and DROP the two "_anon_" policies before real student data is stored.
--
-- Run in Supabase SQL Editor. Idempotent.

create table if not exists public.counseling_archive_logs (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students(id) on delete cascade,
  -- 'counseling' | 'parent_conference' | 'intervention' | 'referral' | 'other'
  log_type text not null default 'other',
  occurred_on date not null default current_date,
  title text not null,
  notes text not null default '',
  created_by uuid references public.profiles(id) on delete set null,
  created_by_name text,
  created_at timestamptz not null default now(),
  constraint counseling_archive_logs_type_check
    check (log_type in ('counseling', 'parent_conference', 'intervention', 'referral', 'other'))
);

create index if not exists counseling_archive_logs_student_idx
  on public.counseling_archive_logs (student_id, occurred_on desc, created_at desc);

alter table public.counseling_archive_logs enable row level security;

drop policy if exists "counseling_logs_staff_select" on public.counseling_archive_logs;
create policy "counseling_logs_staff_select" on public.counseling_archive_logs
  for select to authenticated
  using (current_user_role() in ('Guidance_Counselor'::app_role, 'Admin'::app_role));

drop policy if exists "counseling_logs_gc_insert" on public.counseling_archive_logs;
create policy "counseling_logs_gc_insert" on public.counseling_archive_logs
  for insert to authenticated
  with check (current_user_role() = 'Guidance_Counselor'::app_role);

drop policy if exists "counseling_logs_gc_delete" on public.counseling_archive_logs;
create policy "counseling_logs_gc_delete" on public.counseling_archive_logs
  for delete to authenticated
  using (current_user_role() = 'Guidance_Counselor'::app_role);

-- DEMO ONLY — drop these before storing real data (see header).
drop policy if exists "counseling_logs_anon_select" on public.counseling_archive_logs;
create policy "counseling_logs_anon_select" on public.counseling_archive_logs
  for select to anon using (true);
drop policy if exists "counseling_logs_anon_insert" on public.counseling_archive_logs;
create policy "counseling_logs_anon_insert" on public.counseling_archive_logs
  for insert to anon with check (true);
drop policy if exists "counseling_logs_anon_delete" on public.counseling_archive_logs;
create policy "counseling_logs_anon_delete" on public.counseling_archive_logs
  for delete to anon using (true);
