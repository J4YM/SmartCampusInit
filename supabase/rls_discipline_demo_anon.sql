-- Demo-mode read/write access for the Discipline Officer dashboard and
-- Admin Overview, matching the existing pattern in rls_students_list_anon.sql.
--
-- Why this is needed: the static demo accounts (lib/auth/static_demo_accounts.dart
-- — admin / Capstone2026!, do.demo / DO2026!, etc.) never call Supabase Auth
-- at all (`SessionController.signIn` only sets local app state), so every
-- Supabase request they make goes out under the plain `anon` API key with no
-- JWT. Any RLS policy keyed on `auth.uid()` / `current_user_role()` — e.g.
-- `good_moral_requests_discipline_guidance_full`, or an admin-only policy on
-- `student_violations` — therefore evaluates to false for them, and the
-- query silently returns zero rows (no error) even though the data exists.
-- This is why violations/Good Moral requests didn't show up in the DO
-- Dashboard or the Admin Overview's Discipline Alerts card when signed in
-- with a demo account, right after populating sample data.
--
-- Same tradeoff as rls_students_list_anon.sql: this makes the affected
-- tables readable (and `student_violations` writable) by anyone holding the
-- public anon key, no login required. Fine for local development/demo;
-- tighten before production (e.g. require a real authenticated staff JWT).
--
-- Run in Supabase SQL Editor, after add_discipline_officer_schema.sql and
-- add_good_moral_requests_schema.sql.

-- ---------------------------------------------------------------------------
-- student_violations — read for the DO Dashboard queue / Overview stats;
-- write for Validate/Modify/Deny (`DisciplineRepository.resolveViolation` /
-- `updateViolation` in lib/data/discipline_repository.dart).
-- ---------------------------------------------------------------------------
alter table public.student_violations enable row level security;

drop policy if exists "student_violations_anon_select_all" on public.student_violations;
create policy "student_violations_anon_select_all"
  on public.student_violations
  for select
  to anon, authenticated
  using (true);

drop policy if exists "student_violations_anon_update_all" on public.student_violations;
create policy "student_violations_anon_update_all"
  on public.student_violations
  for update
  to anon, authenticated
  using (true)
  with check (true);

-- ---------------------------------------------------------------------------
-- good_moral_requests — read for the DO Dashboard's Good Moral Management
-- queue. (Only viewed from that page today, no write, so no update policy
-- needed here — add_good_moral_requests_schema.sql's existing
-- staff/self/parent policies are untouched.)
-- ---------------------------------------------------------------------------
drop policy if exists "good_moral_requests_anon_select_all" on public.good_moral_requests;
create policy "good_moral_requests_anon_select_all"
  on public.good_moral_requests
  for select
  to anon, authenticated
  using (true);

-- ---------------------------------------------------------------------------
-- handbook_offenses — read for the violation-type label shown per case and
-- the Modify dialog's offense dropdown.
-- ---------------------------------------------------------------------------
alter table public.handbook_offenses enable row level security;

drop policy if exists "handbook_offenses_anon_select_all" on public.handbook_offenses;
create policy "handbook_offenses_anon_select_all"
  on public.handbook_offenses
  for select
  to anon, authenticated
  using (true);

-- ---------------------------------------------------------------------------
-- profiles — broad read, needed for: the `reported_by` staff name shown per
-- violation, and the Staff Accounts / RFID Mapping pages (which list
-- arbitrary staff profiles, not just ones linked to a student/parent like
-- the existing rls_students_list_anon.sql policies cover).
-- ---------------------------------------------------------------------------
drop policy if exists "profiles_anon_select_all" on public.profiles;
create policy "profiles_anon_select_all"
  on public.profiles
  for select
  to anon, authenticated
  using (true);
