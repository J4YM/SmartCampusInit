-- Assertions for add_meeting_completion_log.sql. Run in the Supabase SQL Editor
-- on a DEV project as an Admin session, AFTER add_endorsement_meetings.sql,
-- add_counseling_archive_logs.sql, add_do_investigations.sql and
-- add_meeting_completion_log.sql. Needs a student and a handbook offense; a
-- Discipline_Officer profile is used when one exists. Rolled back at the end.
-- Run once BEFORE the migration (fails) and once AFTER (prints "ALL PASSED").

begin;

do $$
declare v_admin uuid;
begin
  select id into v_admin from public.profiles where role::text = 'Admin' limit 1;
  assert v_admin is not null, 'need an Admin profile to run this test';
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', v_admin::text, true);
end $$;

do $$
declare
  v_student uuid; v_offense uuid; v_do uuid; v_viol uuid; v_inv uuid;
  v_rep uuid; v_m_both uuid; v_m_student uuid; v_m_missed uuid; v_m_inv uuid;
  v_failed boolean;
  v_claims text := current_setting('request.jwt.claims', true);
  v_sub text := current_setting('request.jwt.claim.sub', true);
  v_notes text;
begin
  select id into v_student from public.students order by id limit 1;
  assert v_student is not null, 'need a student';
  select id into v_offense from public.handbook_offenses limit 1;
  assert v_offense is not null, 'need a handbook offense';
  select id into v_do from public.profiles where role::text = 'Discipline_Officer' limit 1;

  -- An accepted endorsement with three meetings.
  insert into public.escalation_reports
    (student_id, kind, title, summary, message, channels, created_by_name)
  values (v_student, 'counseling', 'Check-in', 'Seems withdrawn', '', '{}', 'Test DO')
  returning id into v_rep;
  perform public.decide_escalation_report(v_rep, true, 'Please attend', null, 'Test GC');

  insert into public.guidance_meetings
    (escalation_report_id, student_id, scheduled_at, location, invitee, status, response_note)
  values (v_rep, v_student, now() + interval '1 day', 'Guidance Office', 'both',
          'Confirmed', 'We will attend') returning id into v_m_both;
  insert into public.guidance_meetings
    (escalation_report_id, student_id, scheduled_at, location, invitee, status)
  values (v_rep, v_student, now() + interval '2 days', 'Guidance Office', 'student',
          'Confirmed') returning id into v_m_student;
  insert into public.guidance_meetings
    (escalation_report_id, student_id, scheduled_at, location, invitee, status)
  values (v_rep, v_student, now() + interval '3 days', 'Guidance Office', 'parent',
          'Confirmed') returning id into v_m_missed;

  -- (a) Completing a parent meeting logs one parent_conference entry.
  perform public.set_meeting_outcome(v_m_both, 'Completed');
  assert (select count(*) from public.counseling_archive_logs where meeting_id = v_m_both) = 1,
    'one log entry for the completed meeting';
  assert (select log_type from public.counseling_archive_logs where meeting_id = v_m_both)
           = 'parent_conference', 'a parent meeting is a parent conference';
  assert (select student_id from public.counseling_archive_logs where meeting_id = v_m_both)
           = v_student, 'the entry is on the student';
  select notes into v_notes from public.counseling_archive_logs where meeting_id = v_m_both;
  assert v_notes like '%We will attend%', 'the invitee''s reply is in the notes';
  assert v_notes like '%Guidance Office%', 'the location is in the notes';
  assert v_notes like '%Please attend%', 'the endorsement decision note is in the notes';

  -- (b) Completing again changes nothing: still one entry.
  v_failed := false;
  begin perform public.set_meeting_outcome(v_m_both, 'Completed');
  exception when others then v_failed := true; end;
  assert (select count(*) from public.counseling_archive_logs where meeting_id = v_m_both) = 1,
    'never a duplicate entry';

  -- (c) A student-only meeting is a counseling entry.
  perform public.set_meeting_outcome(v_m_student, 'Completed');
  assert (select log_type from public.counseling_archive_logs where meeting_id = v_m_student)
           = 'counseling', 'a student-only meeting is counseling';

  -- (d) Missed is not logged.
  perform public.set_meeting_outcome(v_m_missed, 'Missed');
  assert (select count(*) from public.counseling_archive_logs where meeting_id = v_m_missed) = 0,
    'a missed meeting is not logged';

  -- (e) A Discipline Officer completing the meeting still logs it, although
  -- the DO cannot write the archive directly.
  if v_do is not null then
    insert into public.guidance_meetings
      (escalation_report_id, student_id, scheduled_at, location, invitee, status)
    values (v_rep, v_student, now() + interval '4 days', 'Guidance Office', 'both',
            'Confirmed') returning id into v_m_both;
    perform set_config('request.jwt.claims',
      json_build_object('sub', v_do, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_do::text, true);
    perform public.set_meeting_outcome(v_m_both, 'Completed');
    perform set_config('request.jwt.claims', v_claims, true);
    perform set_config('request.jwt.claim.sub', v_sub, true);
    assert (select count(*) from public.counseling_archive_logs where meeting_id = v_m_both) = 1,
      'a DO completing a guidance meeting still logs it';
  end if;

  -- (f) An investigation meeting (DO only, no counselor) is not logged.
  insert into public.student_violations (student_id, offense_id, status, incident_at)
  values (v_student, v_offense, 'Pending', now()) returning id into v_viol;
  v_inv := public.escalate_to_guidance(v_viol);
  insert into public.guidance_meetings
    (investigation_id, student_id, scheduled_at, location, invitee, status)
  values (v_inv, v_student, now() + interval '5 days', 'Guidance Office', 'parent',
          'Confirmed') returning id into v_m_inv;
  perform public.set_meeting_outcome(v_m_inv, 'Completed');
  assert (select count(*) from public.counseling_archive_logs where meeting_id = v_m_inv) = 0,
    'an investigation meeting is not written to the counselor archive';

  raise notice 'ALL PASSED';
end $$;

rollback;
