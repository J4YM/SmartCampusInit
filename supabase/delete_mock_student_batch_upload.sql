-- Removes the 50-student mock batch enrollment upload
-- (Downloads\Student_Information_Mock_Data.xlsx) — every row in that file
-- used the fake email domain "@student.school.edu.ph" (the school's real
-- domain is different), which makes it a precise, safe identifier: no
-- real student would ever have that domain. Several rows also used
-- programs the school doesn't actually offer (BSA, BSPsych, BSCS, BSEd)
-- and Senior High strands (ABM, HUMSS, TVL-ICT, STEM, GAS) — confirming
-- this is entirely mock/test data, not something to preserve.
--
-- Scoped by email rather than by upload timestamp or `is_anonymous` (the
-- broader heuristics reset_schedule_import_test_data.sql uses for
-- schedule-import test data): those would risk also catching a real
-- student who happens to self-register (also anonymous auth) around the
-- same time. The email domain can't collide with anything real.
--
-- Run the PREVIEW block first and confirm every row shown is one you
-- recognize from that mock file before running the DELETE block.

-- ---------------------------------------------------------------------------
-- PREVIEW — run this first.
-- ---------------------------------------------------------------------------

select
  s.student_number,
  p.first_name,
  p.last_name,
  s.course,
  s.year_level,
  p.email,
  s.created_at
from public.students s
join public.profiles p on p.id = s.id
where p.email ilike '%@student.school.edu.ph'
order by s.created_at desc;

select count(*) as mock_student_count
from public.profiles
where email ilike '%@student.school.edu.ph';

-- ---------------------------------------------------------------------------
-- DELETE — only run this after the preview above looks right. Order
-- matters (child rows before the parents they reference).
-- ---------------------------------------------------------------------------

create temporary table _mock_student_ids as
select p.id
from public.profiles p
where p.email ilike '%@student.school.edu.ph';

-- enrollments/grades reference students WITHOUT on delete cascade
-- (add_subjects_enrollments_schema.sql / add_grades_schema.sql) — deleting
-- students first would fail with a foreign-key violation if either has a
-- row for one of them.
delete from public.enrollments where student_id in (select id from _mock_student_ids);
delete from public.grades where student_id in (select id from _mock_student_ids);

-- parent_student_links predates version control (created before this
-- repo tracked migrations), so its delete behavior can't be verified from
-- the codebase — deleting explicitly here is a safety net in case it
-- lacks cascade, same reasoning reset_schedule_import_test_data.sql uses
-- for the untracked `sections` table.
delete from public.parent_student_links where student_id in (select id from _mock_student_ids);

-- Every other table referencing students (good_moral_requests,
-- admission_slips, rfid_assignment_requests, attendance/professor-module
-- records, risk_assessments) already has `on delete cascade`, so deleting
-- `students` here is enough for all of them.
delete from public.students where id in (select id from _mock_student_ids);

delete from public.profiles where id in (select id from _mock_student_ids);
delete from auth.users where id in (select id from _mock_student_ids);

drop table _mock_student_ids;
