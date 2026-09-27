-- Investigates the BSTM duplicate-subject bug — every visible column
-- (day, time, room, instructor) is IDENTICAL between the two rows shown
-- on screen, unlike earlier duplicates this session (which always
-- differed in spelling/formatting). That rules out a naming-variant bug
-- and leaves two very different possible causes needing different fixes:
--
--   (1) Two SEPARATE class_sections rows for the same subject+section+
--       professor (a resolution bug creating two offerings that should
--       have merged into one) — each with its own identical meeting.
--   (2) ONE class_sections row with duplicate class_section_meetings rows
--       under it (a commitMeetings/sequence bug that let two upserts
--       collide-free instead of overwriting each other).
--
-- Broadened to not guess the exact section name/subject spelling (the
-- first attempt at this query, filtered to "BSTM%3%C%", returned 0 rows —
-- wrong guess) — this instead lists every section whose meetings include
-- any of the subjects shown duplicated on screen, so the real section
-- name shows up directly in the results.

select
  cs.id as class_section_id,
  cs.school_year,
  cs.term,
  cs.created_at as class_section_created_at,
  s.id as subject_id,
  s.title as subject,
  sec.id as section_id,
  sec.name as section,
  p.id as professor_id,
  p.first_name as professor_first_name,
  p.last_name as professor_last_name,
  csm.id as meeting_id,
  csm.component,
  csm.day,
  csm.sequence,
  csm.start_time,
  csm.end_time,
  csm.room,
  csm.created_at as meeting_created_at
from public.class_section_meetings csm
join public.class_sections cs on cs.id = csm.class_section_id
join public.subjects s on s.id = cs.subject_id
join public.sections sec on sec.id = cs.section_id
left join public.profiles p on p.id = cs.professor_id
where sec.program ilike '%BSTM%'
  and (
    s.title ilike '%Understanding the Self%'
    or s.title ilike '%Euthenics%'
    or s.title ilike '%National Service Train%'
    or s.title ilike '%Readings in Philippine%'
    or s.title ilike '%PATHFIT%'
    or s.title ilike '%Mathematics in the M%'
    or s.title ilike '%Risk Management%'
  )
order by sec.name, s.title, cs.id, csm.day, csm.start_time, csm.id;
