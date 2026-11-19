-- Assertions for add_investigation_scheduling.sql. Run in the Supabase SQL
-- Editor on a DEV project as an Admin session, AFTER
-- add_parent_availability_scheduling.sql, add_parent_credential_access.sql,
-- add_do_investigations.sql and add_investigation_scheduling.sql. Needs a
-- student with a linked parent and a handbook offense; a Guidance_Counselor
-- profile is used when one exists. Rolled back at the end. Run once BEFORE the
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
  v_student uuid; v_parent uuid; v_offense uuid; v_gc uuid;
  v_viol uuid; v_inv uuid;
  v_round uuid; v_round2 uuid; v_round3 uuid; v_slot uuid; v_meeting uuid;
  v_t1 timestamptz := date_trunc('minute', now() + interval '3 days');
  v_t2 timestamptz := date_trunc('minute', now() + interval '4 days');
  v_gc_before int; v_failed boolean;
  v_claims text := current_setting('request.jwt.claims', true);
  v_sub text := current_setting('request.jwt.claim.sub', true);
begin
  select l.student_id, l.parent_id into v_student, v_parent
    from public.parent_student_links l limit 1;
  assert v_student is not null, 'need a student with a linked parent';
  select id into v_offense from public.handbook_offenses limit 1;
  assert v_offense is not null, 'need a handbook offense';
  select id into v_gc from public.profiles where role::text = 'Guidance_Counselor' limit 1;

  insert into public.student_violations (student_id, offense_id, status, incident_at)
  values (v_student, v_offense, 'Pending', now()) returning id into v_viol;
  v_inv := public.escalate_to_guidance(v_viol);

  select count(*) into v_gc_before from public.notifications
   where target_role::text = 'Guidance_Counselor';

  -- (a) The DO asks the parent.
  v_round := public.request_investigation_availability(v_inv);
  assert (select status from public.meeting_availability_rounds where id = v_round) = 'Open';
  assert (select investigation_id from public.meeting_availability_rounds where id = v_round) = v_inv
     and (select escalation_report_id from public.meeting_availability_rounds where id = v_round) is null,
    'an investigation round has an investigation and no endorsement';
  assert (select count(*) from public.notifications
           where target_role::text = 'Parent' and user_id = v_parent
             and title = 'Meeting availability requested') >= 1,
    'the parent is notified';

  -- (b) One round at a time; a round must belong to exactly one subject.
  v_failed := false;
  begin perform public.request_investigation_availability(v_inv);
  exception when others then v_failed := sqlerrm like '%in progress%'; end;
  assert v_failed, 'a second request while one is open is refused';

  v_failed := false;
  begin
    insert into public.meeting_availability_rounds (student_id, round_no, status)
    values (v_student, 99, 'Open');
  exception when check_violation then v_failed := true; end;
  assert v_failed, 'a round with neither subject is rejected';

  -- (c) Guidance cannot request, decide or cancel an investigation round.
  if v_gc is not null then
    perform set_config('request.jwt.claims',
      json_build_object('sub', v_gc, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_gc::text, true);
    v_failed := false;
    begin perform public.request_investigation_availability(v_inv);
    exception when others then v_failed := sqlstate = '42501'; end;
    assert v_failed, 'Guidance cannot request';
    v_failed := false;
    begin perform public.cancel_parent_availability(v_round);
    exception when others then v_failed := sqlstate = '42501'; end;
    assert v_failed, 'Guidance cannot cancel an investigation round';
    perform set_config('request.jwt.claims', v_claims, true);
    perform set_config('request.jwt.claim.sub', v_sub, true);
  end if;

  -- (d) The parent (anon, credential path) offers two times.
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  perform public.submit_parent_availability(v_round, array[v_t1, v_t2], v_parent);
  perform set_config('request.jwt.claims', v_claims, true);
  perform set_config('request.jwt.claim.sub', v_sub, true);
  assert (select status from public.meeting_availability_rounds where id = v_round) = 'Offered';
  assert (select count(*) from public.meeting_availability_slots where round_id = v_round) = 2;

  -- Guidance's endorsement function refuses an investigation round.
  if v_gc is not null then
    perform set_config('request.jwt.claims',
      json_build_object('sub', v_gc, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_gc::text, true);
    select id into v_slot from public.meeting_availability_slots
     where round_id = v_round order by slot_at limit 1;
    v_failed := false;
    begin perform public.decide_parent_availability(v_round, v_slot);
    exception when others then v_failed := true; end;
    assert v_failed, 'Guidance cannot approve an investigation round';
    perform set_config('request.jwt.claims', v_claims, true);
    perform set_config('request.jwt.claim.sub', v_sub, true);
  end if;

  -- (e) The DO approves one time: a Proposed investigation meeting.
  select id into v_slot from public.meeting_availability_slots
   where round_id = v_round order by slot_at limit 1;
  perform public.decide_investigation_availability(v_round, v_slot, 'Guidance Office');
  select meeting_id into v_meeting from public.meeting_availability_rounds where id = v_round;
  assert v_meeting is not null, 'the round records its meeting';
  assert (select status from public.guidance_meetings where id = v_meeting) = 'Proposed';
  assert (select investigation_id from public.guidance_meetings where id = v_meeting) = v_inv
     and (select invitee from public.guidance_meetings where id = v_meeting) = 'parent',
    'a Proposed meeting for the parent, on the investigation';
  assert (select status from public.meeting_availability_rounds where id = v_round) = 'Approved';

  -- (f) Decline path: a new round, and a declined time cannot be re-offered.
  v_round2 := public.request_investigation_availability(v_inv);
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  perform public.submit_parent_availability(v_round2, array[v_t1 + interval '2 days'], v_parent);
  perform set_config('request.jwt.claims', v_claims, true);
  perform set_config('request.jwt.claim.sub', v_sub, true);
  perform public.decide_investigation_availability(v_round2, null, null, 'Please offer other times');
  assert (select status from public.meeting_availability_rounds where id = v_round2) = 'Declined';
  select id into v_round3 from public.meeting_availability_rounds
   where investigation_id = v_inv and status = 'Open';
  assert v_round3 is not null, 'declining opens a fresh round';
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  v_failed := false;
  begin perform public.submit_parent_availability(v_round3, array[v_t1 + interval '2 days'], v_parent);
  exception when others then v_failed := sqlerrm like '%declined%'; end;
  assert v_failed, 'a declined time cannot be offered again';
  perform set_config('request.jwt.claims', v_claims, true);
  perform set_config('request.jwt.claim.sub', v_sub, true);

  -- (g) The DO cancels the open round.
  perform public.cancel_parent_availability(v_round3);
  assert (select status from public.meeting_availability_rounds where id = v_round3) = 'Cancelled';

  -- (h) The 48-hour reminder covers an investigation round (no endorsement).
  v_round3 := public.request_investigation_availability(v_inv);
  update public.meeting_availability_rounds
     set requested_at = now() - interval '3 days' where id = v_round3;
  assert public.remind_stale_availability_rounds() >= 1, 'the stale round is reminded';
  assert (select reminded_at from public.meeting_availability_rounds where id = v_round3) is not null;

  -- (i) Nobody on the Guidance side heard about any of it.
  assert (select count(*) from public.notifications
           where target_role::text = 'Guidance_Counselor') = v_gc_before,
    'no Guidance Counselor notification for investigation scheduling';

  raise notice 'ALL PASSED';
end $$;

rollback;
