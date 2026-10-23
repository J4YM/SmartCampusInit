-- Assertions for add_do_investigations.sql. Run in the Supabase SQL Editor on a
-- DEV project as an Admin session (Admin passes the DO role checks); like the
-- other test_*.sql files it needs a session whose current_user_role()
-- resolves. Rolled back at the end. Run it once BEFORE the migration (it fails
-- at the first assertion) and once AFTER (it prints "ALL PASSED").

begin;

do $$
declare
  v_student uuid; v_reporter uuid; v_offense uuid;
  v_vio uuid; v_inv uuid; v_meeting uuid; v_failed boolean;
  v_before int; v_after int; v_def text;
begin
  -- Guidance cannot read investigations; it keeps only endorsement meetings.
  assert not exists (
    select 1 from pg_policies
     where tablename = 'guidance_investigations'
       and qual ilike '%Guidance_Counselor%'),
    'Guidance must not read investigations';
  assert exists (
    select 1 from pg_policies
     where tablename = 'guidance_meetings'
       and qual ilike '%escalation_report_id is not null%'),
    'Guidance keeps endorsement meetings only';

  -- The workflow functions no longer admit Guidance.
  foreach v_def in array array[
    'public.schedule_guidance_meeting(uuid, timestamptz, text, text)',
    'public.set_meeting_outcome(uuid, text)',
    'public.complete_investigation(uuid, text, text)'
  ] loop
    assert pg_get_functiondef(v_def::regprocedure) not ilike '%''Guidance_Counselor''::app_role%',
      v_def || ' must not admit Guidance';
  end loop;

  -- record_sanction no longer tells Guidance about an early sanction.
  assert pg_get_functiondef(
    'public.record_sanction(uuid, text, uuid, text, text, date, date, boolean, text)'::regprocedure)
    not ilike '%''Guidance_Counselor''::app_role%',
    'record_sanction must not notify Guidance';

  -- The whole flow works for the DO / Admin and tells Guidance nothing.
  select id into v_student from public.students limit 1;
  select id into v_reporter from public.profiles limit 1;
  select id into v_offense from public.handbook_offenses limit 1;
  select count(*) into v_before from public.notifications
   where target_role = 'Guidance_Counselor'::app_role;

  v_vio := public.submit_incident_report(v_student, now() - interval '1 hour', 'fight', '{}', v_reporter);
  perform public.classify_violation(v_vio, array[v_offense]);
  v_inv := public.escalate_to_guidance(v_vio);

  v_failed := false;
  begin
    perform public.schedule_guidance_meeting(v_inv, now() - interval '1 day', 'Room 1', 'both');
    v_failed := true;
  exception when others then null; end;
  assert not v_failed, 'past meeting must raise';

  v_meeting := public.schedule_guidance_meeting(v_inv, now() + interval '2 days', 'Discipline Office', 'both');
  perform public.set_meeting_outcome(v_meeting, 'Completed');
  perform public.complete_investigation(v_inv, 'Mutual altercation.', 'Warning');
  assert (select status::text from public.student_violations where id = v_vio) = 'Investigation_Complete';

  v_failed := false;
  begin
    perform public.schedule_guidance_meeting(v_inv, now() + interval '3 days', 'Room 1', 'both');
    v_failed := true;
  exception when others then null; end;
  assert not v_failed, 'a completed investigation cannot be scheduled';

  select count(*) into v_after from public.notifications
   where target_role = 'Guidance_Counselor'::app_role;
  assert v_after = v_before, 'investigations must not notify Guidance';

  raise notice 'ALL PASSED';
end $$;

rollback;
