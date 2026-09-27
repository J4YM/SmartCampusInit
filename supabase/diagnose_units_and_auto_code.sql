-- Investigates two reported bugs in the generated Class Schedule:
-- (1) units always show blank/0, (2) subjects always get an "AUTO-..."
-- code even when the Registrar's Classes+Professor list roster upload
-- already gave that subject a real course code.
--
-- Two very different root causes are possible for each, needing very
-- different fixes:
--   Units: either (a) class_section_meetings.units is genuinely null in
--     the DB — meaning either the units migration was never run, or the
--     CFL file's actual "Units" column header doesn't exactly match what
--     parseFacultyLoading looks for — or (b) the data predates the units
--     column ever being populated (imported before that feature existed).
--   AUTO code: either (a) the Classes+Professor list's own subjects were
--     never given a real code in the first place (a header-matching
--     issue in parseClassesAndProfessorList, e.g. "Course Code" not
--     matching the real column header exactly), or (b) the roster's
--     subject WAS given a real code, but CFL/Room Schedule's title-only
--     match against it is failing (a wording/whitespace difference
--     between how the same subject's title appears in each file).

-- 1. How many subjects have a real code vs an auto-generated one, and a
--    sample of each — tells us immediately whether the roster upload
--    itself ever produced real codes at all.
select
  (code ilike 'AUTO-%') as is_auto_generated,
  count(*) as subject_count
from public.subjects
group by is_auto_generated;

select id, code, title, created_at
from public.subjects
order by created_at desc
limit 30;

-- 2. For any subject that exists BOTH with a real code AND an AUTO code
--    under the same (or near-identical) title — the smoking gun for "CFL
--    title-match against an already-coded subject is failing". A blank
--    result here means that specific failure mode isn't happening; if
--    every subject only has ONE row (auto or real, never both), the roster
--    upload itself never produced a real code for that subject at all.
select a.id as auto_subject_id, a.code as auto_code, a.title as auto_title,
       r.id as real_subject_id, r.code as real_code, r.title as real_title
from public.subjects a
join public.subjects r
  on r.code not ilike 'AUTO-%'
  and a.code ilike 'AUTO-%'
  and lower(trim(a.title)) = lower(trim(r.title))
where a.id <> r.id;

-- 3. class_section_meetings.units — null vs populated counts, and a
--    sample of any populated rows (to confirm the column itself works at
--    all once real data has it).
select
  (units is null) as units_is_null,
  count(*) as meeting_count
from public.class_section_meetings
group by units_is_null;

select id, class_section_id, component, day, units, created_at
from public.class_section_meetings
order by created_at desc
limit 20;
