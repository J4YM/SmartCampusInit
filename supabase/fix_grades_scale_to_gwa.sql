-- `grades.grade` was defined on a 0-100 percentage scale
-- (add_grades_schema.sql), but this is a Philippine college — grades are
-- 1.00-5.00, 1.00 = best, lower is better (the same scale
-- student_gpa_records/gwaToPercentage already use elsewhere in this
-- schema; see lib/data/guidance_counselor_repository.dart's own doc
-- comment on gwaToPercentage for how that one maps 1.00-5.00 onto a
-- 0-100 percentage for the ML service specifically — that function is
-- unrelated to this table and is not being changed here).
--
-- Any existing row under the old 0-100 constraint is not a valid 1.00-5.00
-- grade and can't be reliably auto-converted (no fixed formula maps a raw
-- percentage back onto a specific GWA without knowing this school's own
-- grading policy) — PREVIEW below first; if it shows real graded rows,
-- stop and ask before running the rest, since this project's own
-- Registrar demo account couldn't even read this table before today (see
-- part 2 below), so any row that got in was written some other way.
--
-- Run in Supabase SQL Editor, after add_grades_schema.sql.

-- ---------------------------------------------------------------------------
-- PREVIEW — run this first.
-- ---------------------------------------------------------------------------

select count(*) as existing_grade_rows from public.grades;
select * from public.grades limit 20;

-- ---------------------------------------------------------------------------
-- 1. Clear existing 0-100-scale data, then rescale the column itself.
-- ---------------------------------------------------------------------------

delete from public.grades;

alter table public.grades
  alter column grade type numeric(3,2),
  drop constraint if exists grades_grade_check;

alter table public.grades
  add constraint grades_grade_check check (grade >= 1.00 and grade <= 5.00);

-- ---------------------------------------------------------------------------
-- 2. grades_registrar_all (add_grades_schema.sql) only ever covered
-- `authenticated` — every demo account (lib/auth/static_demo_accounts.dart,
-- including registrar.demo) has no real Supabase Auth session and
-- authenticates as `anon` instead, so the Registrar's own Grades tab
-- couldn't read or write this table at all under the original policy.
-- Matches this repo's now-familiar anon-demo-account pattern (see
-- add_enrollments_write_policy.sql).
-- ---------------------------------------------------------------------------

drop policy if exists "grades_anon_all" on public.grades;
create policy "grades_anon_all"
on public.grades for all
to anon
using (true)
with check (true);
