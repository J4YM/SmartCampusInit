-- supabase/add_students_update_policy.sql
--
-- public.students has SELECT policies (anon + authenticated,
-- rls_students_list_anon.sql) and an INSERT-own policy (authenticated
-- self-registration, rls_student_self_insert.sql), but NO UPDATE policy
-- at all. With RLS enabled, that means every UPDATE statement against
-- this table — including the Admin Student Directory's and IT
-- Technician's own "assign RFID card to student" saves
-- (lib/data/students_repository.dart's update(), called from
-- lib/ui/admin/student_directory_connected_page.dart and
-- lib/ui/it_technician_connected_page.dart) — silently matches zero
-- rows. PostgREST returns 200 with no error for this, so the app has no
-- way to detect the write never happened: the UI reports success, but
-- `students.rfid_uid` (and every other field the edit form touches)
-- never actually changes. This is the root cause of RFID card
-- assignment appearing to work but never taking effect.
--
-- Two policies, matching this project's established per-table pattern
-- (see e.g. add_it_technician_schema.sql's technical_issue_reports
-- policies):
--   - anon: every demo account (lib/auth/static_demo_accounts.dart,
--     including admin/ittech.demo) is a purely client-side check with
--     no real Supabase Auth session — StaticDemoAccounts.trySignIn never
--     calls Supabase — so those sessions call Supabase under the anon
--     key. Tighten before production.
--   - authenticated, staff-role-scoped: real Microsoft-OAuth-signed-in
--     Registrar/Admin/IT_Technician accounts.
--
-- Run in Supabase SQL Editor. Idempotent: safe to re-run.

drop policy if exists "students_anon_update" on public.students;
create policy "students_anon_update"
  on public.students
  for update
  to anon
  using (true)
  with check (true);

drop policy if exists "students_staff_update" on public.students;
create policy "students_staff_update"
  on public.students
  for update
  to authenticated
  using (current_user_role() in (
    'Registrar'::app_role, 'Admin'::app_role, 'IT_Technician'::app_role
  ))
  with check (current_user_role() in (
    'Registrar'::app_role, 'Admin'::app_role, 'IT_Technician'::app_role
  ));
