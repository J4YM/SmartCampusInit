-- supabase/add_class_sections_insert_policy.sql
--
-- add_subjects_enrollments_schema.sql only anticipated reading class_sections
-- (it predates any UI that writes to it). The Registrar module's "Save
-- Changes" on the Class Schedule tab needs to INSERT new offerings — this
-- adds the missing write policy, restricted to Registrar/Admin, matching
-- this repo's established current_user_role() RLS convention.
--
-- Run in Supabase SQL Editor, after add_subjects_enrollments_schema.sql.

drop policy if exists "class_sections_registrar_insert" on public.class_sections;
create policy "class_sections_registrar_insert"
on public.class_sections for insert
to authenticated
with check (current_user_role() in ('Registrar'::app_role, 'Admin'::app_role));
