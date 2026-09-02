-- Adds `enrollment_year` to `students` — backs the Good Moral Certificate's
-- "from {enrollment_year}-{current_year}" line, which previously had no
-- backing data at all. Nullable: a student with no enrollment_year set just
-- omits that clause from the certificate rather than showing a wrong year.
--
-- Existing rows are backfilled with a placeholder derived from year_level
-- (assuming a standard 4-year progression from the current year) purely so
-- current demo/test data looks plausible — per the app owner, this dataset
-- will be truncated and replaced with real student records from the school
-- before go-live, so exactness here doesn't matter.
--
-- Run in Supabase SQL Editor. Idempotent: safe to re-run.

alter table public.students
  add column if not exists enrollment_year int;

update public.students s
set enrollment_year = extract(year from now())::int - (sec.year_level - 1)
from public.sections sec
where s.section_id = sec.id
  and s.enrollment_year is null;
