-- `enrollments` (added by add_subjects_enrollments_schema.sql) only ever
-- got a SELECT policy, and only for `authenticated` — no INSERT/UPDATE
-- policy exists at all, and `anon` has no access whatsoever. The new
-- "Enroll in Subject" / "Drop" actions on the Registrar's Student Records
-- profile panel (irregular-student enrollment — see
-- docs/superpowers/specs/2026-09-04-irregular-students-schema-design.md)
-- write to this table directly.
--
-- Every demo account (lib/auth/static_demo_accounts.dart, including
-- registrar.demo) has no real Supabase Auth session, so it authenticates
-- as `anon` — matching this repo's now-familiar pattern (see
-- add_students_update_policy.sql, add_schedule_import_commit_support.sql),
-- without an anon policy these actions would silently write nothing under
-- a demo account.
--
-- Run in Supabase SQL Editor. Idempotent: safe to re-run.

drop policy if exists "enrollments_anon_select" on public.enrollments;
create policy "enrollments_anon_select"
on public.enrollments for select
to anon
using (true);

drop policy if exists "enrollments_anon_write" on public.enrollments;
create policy "enrollments_anon_write"
on public.enrollments for all
to anon
using (true)
with check (true);

-- Real Microsoft-OAuth accounts: Registrar/Admin only, matching
-- class_section_meetings' own write policy shape.
drop policy if exists "enrollments_authenticated_write" on public.enrollments;
create policy "enrollments_authenticated_write"
on public.enrollments for all
to authenticated
using (current_user_role() in ('Registrar'::app_role, 'Admin'::app_role))
with check (current_user_role() in ('Registrar'::app_role, 'Admin'::app_role));
