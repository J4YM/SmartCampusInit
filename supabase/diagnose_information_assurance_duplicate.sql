-- Gets the exact, untruncated professor name and room text behind the
-- "Information Assurance..." Friday 08:30-11:30 Laboratory duplicate —
-- the dashboard's table truncates long text with "...", so it's
-- impossible to tell from a screenshot whether "New IT Faculty" (no
-- trailing number) is genuinely different text from "New IT Faculty 1",
-- or whether the room alias for "ComLab 1" is actually being applied.
-- This shows the real, full values stored for each duplicate row.

select
  cs.id as class_section_id,
  s.title as subject,
  sec.name as section,
  p.id as professor_id,
  p.first_name as professor_first_name,
  p.last_name as professor_last_name,
  csm.id as meeting_id,
  csm.component,
  csm.day,
  csm.start_time,
  csm.end_time,
  csm.room
from public.class_section_meetings csm
join public.class_sections cs on cs.id = csm.class_section_id
join public.subjects s on s.id = cs.subject_id
join public.sections sec on sec.id = cs.section_id
join public.profiles p on p.id = cs.professor_id
where s.title ilike '%Information Assurance%'
  and csm.day = 'F'
  and csm.component = 'Laboratory'
order by cs.id, csm.id;
