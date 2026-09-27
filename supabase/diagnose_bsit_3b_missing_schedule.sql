-- Investigates why "BSIT 3B" shows no meetings in the generated Class
-- Schedule. Note the Classes+Professor list (roster only) NEVER creates a
-- `sections`/`class_sections` row at all — only the CFL and Room Schedule
-- uploads do (see ScheduleImportRunner.run, the `sectionName == null`
-- early-continue). So "no schedule" for a real section usually means one
-- of: (1) the section was never created because no CFL/Room Schedule tab
-- ever mentioned it, (2) it exists twice under two different spellings and
-- the real meetings landed on the "wrong" one, or (3) class_sections rows
-- exist (subject+professor assigned) but the meetings never committed.
-- Run each block and check which one explains it before assuming a bug.

-- 1. Every section whose name could plausibly be "BSIT 3B" — catches
--    spelling/spacing variants (e.g. "BSIT-3B", "BSIT_3B", "BSIT 3-B").
--    If this returns MORE THAN ONE row, that's the bug: a duplicate
--    section was created and the real schedule is probably attached to
--    the other spelling.
select id, name, program, year_level
from public.sections
where upper(replace(replace(name, ' ', ''), '-', '')) like '%BSIT%3%B%'
order by name;

-- 2. For every section found above, how many class_sections (subject +
--    professor offerings) exist, and how many meetings each one actually
--    has. A row with meeting_count = 0 means the offering was created
--    (usually via the roster/Classes+Professor list matching an existing
--    section name) but no CFL/Room Schedule file ever supplied a day/time/
--    room for it.
select
  sec.name as section_name,
  cs.id as class_section_id,
  s.title as subject,
  p.first_name,
  p.last_name,
  cs.school_year,
  cs.term,
  count(csm.id) as meeting_count
from public.sections sec
left join public.class_sections cs on cs.section_id = sec.id
left join public.subjects s on s.id = cs.subject_id
left join public.profiles p on p.id = cs.professor_id
left join public.class_section_meetings csm on csm.class_section_id = cs.id
where upper(replace(replace(sec.name, ' ', ''), '-', '')) like '%BSIT%3%B%'
group by sec.name, cs.id, s.title, p.first_name, p.last_name, cs.school_year, cs.term
order by sec.name, subject;

-- 3. If block 1 returns exactly one row and block 2 returns zero rows
--    entirely (not even a subject/professor pairing), the section itself
--    was never referenced by anything you uploaded yet — it needs a CFL
--    or Room Schedule file that actually lists BSIT 3B's classes.
