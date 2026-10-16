-- DEMO PREP, step 1 of 3 — clean the database down to the demo baseline.
--
-- Keeps:
--   * EXACTLY 50 students (real accounts first; the 250 mock students
--     900001-900250 only fill in if there are fewer than 50 real ones).
--     Carl Vinson Ventura (student_number 338958) is deliberately NOT kept: he
--     is deleted here and comes back with the 10-student batch uploaded live
--     during the demo.
--   * The demo professor Ramon Villanueva (fixed profile id ...0002) and the
--     real professor Jovie Mart Salas (her real Microsoft login; matched by
--     name, real sign-ins preferred over import stubs). She has no classes
--     after this cleanup unless a later upload assigns her some.
--   * All non-student / non-teacher staff accounts, sections, subjects,
--     curriculum, handbook_offenses, program/room aliases, RFID/kiosk setup.
--
-- Deletes:
--   * Every other student (+ guardians who only had those children) and
--     every other Teacher profile.
--   * ALL class_sections, class_section_meetings, enrollments, grades,
--     attendance_records, student_violations and student_gpa_records —
--     step 3 re-seeds them for the kept students after the uploads.
--
-- Order of the demo prep:
--   1. this file (cleanup)
--   2. BEFORE the demo, Registrar uploads, in this order:
--        Course_and_Professor_Assignment_Demo.xlsx   (creates the 9 other professors + subjects)
--        CFL_Demo_Professors_1st_Sem_2026-2027.xlsx  (schedules / sections / rooms)
--   3. demo_3_seed_activity.sql (enrollments, attendance, grades, violations for the 50)
--   4. DURING the demo:
--        Student_Information_Demo_Batch30.xlsx       (10 students incl. Carl)
--        Academic_Honors_Demo_Batch30.xlsx           (GPA for those 30)
--
-- Run in the Supabase SQL Editor. Run PREVIEW first and read it. The DELETE
-- block is one transaction; change the final `commit` to `rollback` for a
-- dry run.

-- ---------------------------------------------------------------------------
-- PREVIEW (read-only)
-- ---------------------------------------------------------------------------

-- Who is kept (50) — Carl is excluded on purpose.
with ranked as (
  select s.id, s.student_number, p.first_name, p.last_name, s.course, s.year_level,
         row_number() over (
           order by (s.student_number between '900001' and '900250'), s.created_at, s.student_number
         ) as rn
    from public.students s
    join public.profiles p on p.id = s.id
   where s.student_number <> '338958'
)
select 'KEEP' as action, student_number, first_name, last_name, course, year_level
  from ranked where rn <= 50
order by 2;

-- Teachers: who is kept (demo professor + Jovie Mart Salas) and who goes.
select case when p.id = '00000000-0000-4000-8000-000000000002'
             or (lower(p.first_name || ' ' || p.last_name) like '%jovie%'
                 and lower(p.first_name || ' ' || p.last_name) like '%salas%')
            then 'KEEP' else 'DELETE' end as action,
       p.id, p.first_name, p.last_name, p.email,
       coalesce(u.is_anonymous, false) as is_stub
  from public.profiles p
  left join auth.users u on u.id = p.id
 where p.role = 'Teacher'::app_role
 order by 1, p.last_name;

-- What is about to go.
select 'students total' as what, count(*) from public.students
union all select 'teachers total', count(*) from public.profiles where role = 'Teacher'::app_role
union all select 'class_sections', count(*) from public.class_sections
union all select 'enrollments', count(*) from public.enrollments
union all select 'grades', count(*) from public.grades
union all select 'attendance_records', count(*) from public.attendance_records
union all select 'student_violations', count(*) from public.student_violations
union all select 'student_gpa_records', count(*) from public.student_gpa_records;

-- ---------------------------------------------------------------------------
-- DELETE
-- ---------------------------------------------------------------------------
begin;

create temporary table _keep_students on commit drop as
with ranked as (
  select s.id,
         row_number() over (
           order by (s.student_number between '900001' and '900250'), s.created_at, s.student_number
         ) as rn
    from public.students s
   where s.student_number <> '338958'
)
select id from ranked where rn <= 50;

create temporary table _drop_students on commit drop as
select id from public.students where id not in (select id from _keep_students);

-- Guardians whose only linked children are being deleted.
create temporary table _drop_guardians on commit drop as
select p.id
  from public.profiles p
 where p.role = 'Parent'::app_role
   and exists (select 1 from public.parent_student_links l
                where l.parent_id = p.id and l.student_id in (select id from _drop_students))
   and not exists (select 1 from public.parent_student_links l
                    where l.parent_id = p.id and l.student_id not in (select id from _drop_students));

-- Jovie Mart Salas: keep her real (non-stub) Microsoft login; if only a stub
-- matches, keep that instead.
create temporary table _keep_teachers on commit drop as
with m as (
  select p.id, coalesce(u.is_anonymous, false) as is_stub
    from public.profiles p
    left join auth.users u on u.id = p.id
   where p.role = 'Teacher'::app_role
     and lower(p.first_name || ' ' || p.last_name) like '%jovie%'
     and lower(p.first_name || ' ' || p.last_name) like '%salas%'
)
select id from m where not is_stub
union all
select id from m where not exists (select 1 from m where not is_stub)
union all
select '00000000-0000-4000-8000-000000000002'::uuid;

-- Teachers other than the kept ones.
create temporary table _drop_teachers on commit drop as
select id from public.profiles
 where role = 'Teacher'::app_role
   and id not in (select id from _keep_teachers);

-- Per-term data: wiped for everyone, re-seeded by demo_3_seed_activity.sql.
delete from public.attendance_records;
delete from public.student_violations;
delete from public.student_gpa_records;
delete from public.grades;
delete from public.enrollments;
delete from public.class_section_meetings;
delete from public.class_sections;
-- Professor section assignments of the teachers going away cascade with the
-- profile; the demo professor's own class_assignments are left alone.

-- Departing students (enrollments/grades already gone; the rest cascades).
delete from public.parent_student_links where student_id in (select id from _drop_students);
delete from public.students where id in (select id from _drop_students);
delete from public.profiles where id in (select id from _drop_guardians);
delete from public.profiles where id in (select id from _drop_students);

-- Departing teachers.
delete from public.profiles where id in (select id from _drop_teachers);

delete from auth.users
 where id in (select id from _drop_guardians)
    or id in (select id from _drop_students)
    or id in (select id from _drop_teachers);

-- Post-condition check: should read students = 50, teachers = 2
-- (Ramon + Jovie; 1 if no Jovie profile was found — check the preview).
select (select count(*) from public.students) as students_left,
       (select count(*) from public.profiles where role = 'Teacher'::app_role) as teachers_left;

commit;  -- use `rollback;` instead for a dry run
