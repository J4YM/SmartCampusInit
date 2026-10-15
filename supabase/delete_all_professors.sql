-- Deletes EVERY professor account (role = 'Teacher'), real MS365 sign-ins
-- and import-created stubs alike. Unlike reset_schedule_import_test_data.sql,
-- which only removes anonymous stub professors, this one is not limited
-- to import output: real professors lose their accounts and will have to
-- sign in / be recreated again.
--
-- Subjects, sections, class_sections, enrollments and grades are NOT
-- deleted. class_sections.professor_id is set to null so those rows stay
-- but become unassigned (professor_id has no on delete clause, so the
-- profile delete would otherwise fail with a foreign-key violation).
-- Rows with "on delete cascade" / "set null" on profiles (professor
-- module tables, audit_logs.actor_id, attendance recorded_by, ...) are
-- handled by the database automatically.
--
-- Run the PREVIEW block first and check the names.

-- ---------------------------------------------------------------------------
-- PREVIEW
-- ---------------------------------------------------------------------------

select p.id,
       p.full_name,
       coalesce(u.is_anonymous, false) as is_stub,
       (select count(*) from public.class_sections cs
         where cs.professor_id = p.id) as assigned_class_sections
  from public.profiles p
  left join auth.users u on u.id = p.id
  where p.role = 'Teacher'::app_role
  order by is_stub desc, p.full_name;

-- ---------------------------------------------------------------------------
-- DELETE
-- ---------------------------------------------------------------------------

begin;

create temporary table _professor_ids as
select id from public.profiles where role = 'Teacher'::app_role;

-- Unassign the professors from their class sections.
update public.class_sections
   set professor_id = null
 where professor_id in (select id from _professor_ids);

delete from public.profiles where id in (select id from _professor_ids);
delete from auth.users where id in (select id from _professor_ids);

drop table _professor_ids;

commit;
