-- One-time reset of everything the schedule-import feature (Registrar's
-- Classes+Professor list, Scheduling Officer's CFL/Room Schedule uploads)
-- has created so far, so re-uploading with the duplicate-professor
-- (coreProfessorName) and duplicate-meeting (offering dedup) fixes in
-- place starts from a clean slate instead of layering on top of the
-- duplicates those bugs already created.
--
-- SAFE ONLY as test/demo data cleanup: this assumes no real student has
-- been enrolled into any of these class_sections yet (enrollments
-- references class_sections and would cascade away with it) and no
-- section/subject here is also relied on by something unrelated to this
-- feature. Run the PREVIEW block first and eyeball the counts/names
-- before running the DELETE block.
--
-- Does NOT touch: room_aliases / program_aliases (curated lookup tables,
-- not import output — keep these), or any real MS365-signed-in
-- professor (identified below by NOT being is_anonymous).

-- ---------------------------------------------------------------------------
-- PREVIEW — run this first. Confirm these are all test data before
-- proceeding to the DELETE block below.
-- ---------------------------------------------------------------------------

select 'class_sections' as table_name, count(*) from public.class_sections
union all
select 'class_section_meetings', count(*) from public.class_section_meetings
union all
select 'enrollments', count(*) from public.enrollments
union all
select 'grades', count(*) from public.grades
union all
select 'subjects', count(*) from public.subjects
union all
select 'sections', count(*) from public.sections
union all
select 'stub professor profiles', count(*)
  from public.profiles p
  join auth.users u on u.id = p.id
  where u.is_anonymous = true and p.role = 'Teacher'::app_role;

-- ---------------------------------------------------------------------------
-- DELETE — only run this after checking the preview above looks right.
-- Order matters (child rows before the parents they reference).
-- ---------------------------------------------------------------------------

-- 1. enrollments/grades reference class_sections WITHOUT on delete
--    cascade (add_subjects_enrollments_schema.sql / add_grades_schema.sql)
--    — deleting class_sections first would fail with a foreign-key
--    violation if either has any row for it, so these go first. If you
--    used "Enroll this section's students" while testing, this is where
--    that gets cleared too.
delete from public.enrollments;
delete from public.grades;

-- 2. class_section_meetings cascades automatically when its parent
--    class_sections row is deleted (on delete cascade), so deleting
--    class_sections alone is enough for both.
delete from public.class_sections;

-- 3. Every subject the Classes+Professor list / CFL / Room Schedule
--    imports created (including the AUTO-xxxxxxxx placeholder codes from
--    the resolveSectionId/resolveSubjectId fallback fixes).
delete from public.subjects;

-- 4. Every section those same imports auto-created — scoped to sections
--    with zero students in them. `students.section_id` references
--    sections but that table predates this repo's tracked migrations
--    (created before version control), so its delete behavior can't be
--    verified from the codebase — this WHERE clause is a safety net so a
--    real, already-populated section can never be caught by this reset
--    even if every other assumption above is wrong.
delete from public.sections
where id not in (
  select section_id from public.students where section_id is not null
);

-- 5. Every stub/placeholder professor profile the import auto-created —
--    is_anonymous uniquely identifies these (create_auto_professor_
--    profile in add_scheduling_officer_role.sql always sets it; a real
--    MS365 sign-in never does), so this can't accidentally catch a real
--    professor's account.
create temporary table _stub_professor_ids as
select p.id
  from public.profiles p
  join auth.users u on u.id = p.id
  where u.is_anonymous = true and p.role = 'Teacher'::app_role;

delete from public.profiles where id in (select id from _stub_professor_ids);
delete from auth.users where id in (select id from _stub_professor_ids);

drop table _stub_professor_ids;
