-- Assertions for add_do_investigations.sql. Run in the Supabase SQL Editor on a
-- DEV project as an Admin session (Admin passes the DO role checks); like the
-- other test_*.sql files it needs a session whose current_user_role()
-- resolves. Rolled back at the end. Run it once BEFORE the migration (it fails
-- at the first assertion) and once AFTER (it prints "ALL PASSED").

begin;

-- Act as an Admin for the whole script. The SQL Editor has no logged-in user
-- (auth.uid() is null, so current_user_role() is null and every role check
-- fails); this impersonates an existing Admin profile for this transaction.
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
    'public.complete_investigation(uuid, text, text, text)'
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
  v_reporter := auth.uid();  -- must be the caller: the session is "authenticated"
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
  perform public.complete_investigation(v_inv, 'Mutual altercation.', 'Proven', 'Warning');
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
