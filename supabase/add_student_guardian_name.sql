-- supabase/add_student_guardian_name.sql
--
-- Two fixes behind "I can't edit a student's Parent/Guardian name or contact":
--
-- 1. `students.guardian_name` — the IT Technician and Registrar edit forms
--    collect a Parent/Guardian Name, but it had nowhere to be saved. The read
--    path derived the name only from a linked parent-portal account
--    (parent_student_links), so a name typed into a form was dropped on save
--    and never came back. This is a plain column, like the existing
--    `guardian_contact_no` (add_id_card_student_columns.sql); a linked parent
--    account's name is still shown when this is empty.
--
-- 2. Staff may update a *student's* `profiles` row. Registrar edits a
--    student's name/email/phone, which live on `profiles`, but profiles only
--    had "update your own row" (rls_student_self_insert.sql) plus a demo-only
--    anon policy. Without this, a real signed-in Registrar's save matches
--    zero rows — PostgREST reports success and nothing changes. Scoped to
--    rows whose role is Student, so staff still can't touch other staff
--    accounts' roles or details through this policy.
--
-- Run in Supabase SQL Editor, after add_id_card_student_columns.sql and
-- add_students_update_policy.sql. Idempotent: safe to re-run.

alter table public.students
  add column if not exists guardian_name text;

drop policy if exists "profiles_staff_update_students" on public.profiles;
create policy "profiles_staff_update_students"
  on public.profiles
  for update
  to authenticated
  using (
    role = 'Student'::app_role
    and current_user_role() in (
      'Registrar'::app_role, 'Admin'::app_role, 'IT_Technician'::app_role
    )
  )
  with check (
    role = 'Student'::app_role
    and current_user_role() in (
      'Registrar'::app_role, 'Admin'::app_role, 'IT_Technician'::app_role
    )
  );
