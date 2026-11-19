-- Assertions for add_concern_investigations.sql. Run in the Supabase SQL Editor
-- on a DEV project as an Admin session, AFTER add_concern_reports.sql,
-- add_endorsement_meetings.sql, add_do_investigations.sql,
-- add_manual_incident_reports.sql and add_concern_investigations.sql. Needs two
-- students and a handbook offense. Rolled back at the end. Run once BEFORE the
-- migration (fails) and once AFTER (prints "ALL PASSED").

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
  v_s1 uuid; v_s2 uuid; v_offense uuid;
  v_c1 uuid; v_c2 uuid; v_c3 uuid;
  v_inv uuid; v_viol uuid; v_rep uuid; v_failed boolean;
  v_file jsonb;
begin
  select id into v_s1 from public.students order by id limit 1;
  select id into v_s2 from public.students where id <> v_s1 order by id limit 1;
  assert v_s1 is not null and v_s2 is not null, 'need two students';
  select id into v_offense from public.handbook_offenses limit 1;
  assert v_offense is not null, 'need a handbook offense';

  insert into public.concern_reports (student_id, concern, details)
  values (v_s1, 'bullying', 'He keeps taking my lunch money') returning id into v_c1;

  -- (a) Send to investigation about the OTHER student.
  v_inv := public.send_concern_to_investigation(
    v_c1, v_s2, v_offense, 'Took lunch money', now() - interval '1 day');
  assert v_inv is not null, 'returns the investigation id';
  select id into v_viol from public.student_violations where concern_id = v_c1;
  assert v_viol is not null, 'one violation is linked to the concern';
  assert (select student_id from public.student_violations where id = v_viol) = v_s2,
    'the incident is about the named student, not the reporter';
  assert (select source from public.student_violations where id = v_viol) = 'student_affairs';
  assert (select violation_id from public.guidance_investigations where id = v_inv) = v_viol
     and (select student_id from public.guidance_investigations where id = v_inv) = v_s2,
    'an investigation starts about the named student';
  assert (select status from public.concern_reports where id = v_c1) = 'In_Progress',
    'the concern moves to In_Progress';
  assert (select violation_id from public.concern_reports where id = v_c1) = v_viol,
    'the concern remembers its incident';

  -- (b) Sending twice is refused.
  v_failed := false;
  begin
    perform public.send_concern_to_investigation(v_c1, v_s2, v_offense, 'again', now());
  exception when others then v_failed := true; end;
  assert v_failed, 'a concern already under investigation cannot be sent again';

  -- (c) A closed concern cannot be sent.
  insert into public.concern_reports (student_id, concern, details, status)
  values (v_s1, 'safety', 'x', 'Closed') returning id into v_c2;
  v_failed := false;
  begin
    perform public.send_concern_to_investigation(v_c2, v_s2, v_offense, 'x', now());
  exception when others then v_failed := true; end;
  assert v_failed, 'a closed concern cannot be sent to investigation';

  -- (d) The status picker still works while the investigation is open.
  update public.concern_reports set status = 'Closed' where id = v_c1;
  assert (select status from public.concern_reports where id = v_c1) = 'Closed',
    'the concern can be closed with the investigation still open';
  assert (select status from public.guidance_investigations where id = v_inv) = 'Open',
    'closing the concern leaves the investigation open';

  -- (e) A closed concern still cannot be endorsed.
  v_failed := false;
  begin
    insert into public.escalation_reports
      (student_id, kind, title, summary, message, channels, created_by_name, concern_id)
    values (v_s1, 'counseling', 'Check-in', 'x', '', '{}', 'Test DO', v_c1);
  exception when others then v_failed := sqlerrm like '%closed%'; end;
  assert v_failed, 'endorsing a closed concern is still rejected';

  -- (f) The case file shows the endorsement, its meeting and the findings.
  insert into public.concern_reports (student_id, concern, details)
  values (v_s1, 'other', 'y') returning id into v_c3;
  insert into public.escalation_reports
    (student_id, kind, title, summary, message, channels, created_by_name, concern_id)
  values (v_s1, 'counseling', 'Check-in', 'Seems withdrawn', '', '{}', 'Test DO', v_c3)
  returning id into v_rep;
  perform public.decide_escalation_report(v_rep, true, 'Please attend', null, 'Test GC');
  insert into public.guidance_meetings
    (escalation_report_id, student_id, scheduled_at, location, invitee, status, response_note)
  values (v_rep, v_s1, now() + interval '2 days', 'Guidance Office', 'both',
          'Completed', 'We will attend');

  v_file := public.concern_case_file(v_c3);
  assert jsonb_array_length(v_file->'endorsements') = 1, 'one endorsement in the case file';
  assert v_file->'endorsements'->0->'meetings'->0->>'response_note' = 'We will attend',
    'the meeting response note is in the case file';
  assert v_file->'endorsements'->0->>'decision_note' = 'Please attend',
    'the decision note is in the case file';
  assert v_file->'investigation' = 'null'::jsonb, 'no investigation yet';

  v_file := public.concern_case_file(v_c1);
  assert v_file->'investigation'->>'status' = 'Open', 'the open investigation is in the case file';

  -- (g) Only the DO or Admin.
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  v_failed := false;
  begin perform public.concern_case_file(v_c1);
  exception when others then v_failed := sqlstate = '42501'; end;
  assert v_failed, 'an anonymous caller cannot read the case file';

  raise notice 'ALL PASSED';
end $$;

rollback;
