-- Demo data for the discipline workflow re-defense. DEV / DEMO PROJECT ONLY.
--
-- Creates a handful of UNCLASSIFIED incident reports against real students so
-- the Discipline Officer has something to classify, escalate, auto-record and
-- sanction live. Every row is tagged "[DEMO]" in incident_notes so the cleanup
-- block at the bottom removes exactly these rows and nothing else.
--
-- Run AFTER all the workflow scripts (see docs/superpowers/demo-checklist.md).
-- Re-running adds more demo rows; run the cleanup first if you want a fresh set.
--
-- Needs: at least three students and one Teacher profile.

do $$
declare
  v_students uuid[];
  v_prof uuid;
begin
  select array_agg(id) into v_students
    from (select id from public.students order by created_at limit 3) s;
  select id into v_prof from public.profiles where role = 'Teacher' limit 1;

  if coalesce(array_length(v_students, 1), 0) < 3 then
    raise exception 'Need at least 3 students to seed the demo.';
  end if;

  -- 1. A routine report: classify as Minor and auto-record (the bypass).
  insert into public.student_violations
    (student_id, offense_id, reported_by, professor_id, status, incident_at, incident_notes)
  values
    (v_students[1], null, v_prof, v_prof, 'Pending', now() - interval '3 hours',
     '[DEMO] Student was not wearing the prescribed uniform during class.');

  -- 2. A serious report: classify as Major, escalate to Guidance, schedule a
  --    meeting, then record a non-readmission sanction.
  insert into public.student_violations
    (student_id, offense_id, reported_by, professor_id, status, incident_at, incident_notes)
  values
    (v_students[2], null, v_prof, v_prof, 'Pending', now() - interval '1 day',
     '[DEMO] Student was seen in a physical altercation behind the gym with another student.');

  -- 3. A report that has waited too long: shows the red Expired marker and the
  --    urgent alert. Dated 10 days back so it is past 72 weekday hours.
  insert into public.student_violations
    (student_id, offense_id, reported_by, professor_id, status, created_at, incident_at, incident_notes)
  values
    (v_students[3], null, v_prof, v_prof, 'Pending',
     now() - interval '10 days', now() - interval '10 days',
     '[DEMO] Student used a mobile phone during an examination.');

  perform public.expire_stale_violations();
end $$;

-- ---------------------------------------------------------------------------
-- CLEANUP (run after the demo). Removes the demo reports and everything that
-- hangs off them (evidence, investigations, meetings, sanctions). Does NOT undo
-- an enrollment restriction a demo sanction set: lift it with
--   select public.lift_enrollment_standing('<student uuid>', 'demo cleanup');
-- ---------------------------------------------------------------------------
--
-- delete from public.student_violations where incident_notes like '[DEMO]%';
