-- DEMO PREP, step 1b — follow-up to demo_1_cleanup.sql for databases where the
-- EARLIER version of that script was already run (it kept Carl Vinson Ventura
-- among the 50). Carl must not exist before the demo: he is re-created by the
-- live 10-student batch upload.
--
-- Removes ONLY Carl (student_number 338958) and, if he was their only child,
-- his linked guardian — the same delete order demo_1_cleanup.sql uses.
-- Everything else is left alone.
--
-- Run PREVIEW first. Change the final `commit` to `rollback` for a dry run.

-- PREVIEW (read-only)
select s.student_number, p.first_name, p.last_name, p.email, s.course, s.year_level
  from public.students s
  join public.profiles p on p.id = s.id
 where s.student_number = '338958';

select count(*) as students_now from public.students;

-- DELETE
begin;

create temporary table _carl on commit drop as
select id from public.students where student_number = '338958';

-- Guardians whose only linked child is Carl.
create temporary table _carl_guardians on commit drop as
select l.parent_id as id
  from public.parent_student_links l
 where l.student_id in (select id from _carl)
   and not exists (select 1 from public.parent_student_links o
                    where o.parent_id = l.parent_id
                      and o.student_id not in (select id from _carl));

delete from public.attendance_records where student_id in (select id from _carl);
delete from public.student_violations where student_id in (select id from _carl);
delete from public.student_gpa_records where student_id in (select id from _carl);
delete from public.grades where student_id in (select id from _carl);
delete from public.enrollments where student_id in (select id from _carl);
delete from public.parent_student_links where student_id in (select id from _carl);
delete from public.students where id in (select id from _carl);
delete from public.profiles where id in (select id from _carl_guardians);
delete from public.profiles where id in (select id from _carl);
delete from auth.users
 where id in (select id from _carl) or id in (select id from _carl_guardians);

-- Should read 49 if the earlier cleanup left 50 (Carl + 49).
select count(*) as students_left from public.students;

commit;  -- use `rollback;` instead for a dry run
