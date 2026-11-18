-- Assertions for add_parent_availability_scheduling.sql. Run in the Supabase
-- SQL Editor on a DEV project as an Admin session (Admin passes the DO role
-- check), AFTER add_endorsement_meetings.sql, reword_meeting_invitations.sql
-- and add_parent_availability_scheduling.sql. It needs a student with a linked
-- parent. The submit step impersonates that parent by setting the JWT claims
-- for the transaction. Rolled back at the end. Run once BEFORE the migration
-- (fails) and once AFTER (prints "ALL PASSED").

begin;

do $$
declare
  v_student uuid; v_parent uuid;
  v_rep uuid; v_rep_x uuid; v_pending uuid; v_rep2 uuid; v_rep_nolink uuid;
  v_nolink_student uuid;
  v_round uuid; v_round2 uuid; v_old_round uuid;
  v_failed boolean;
  v_claims text := current_setting('request.jwt.claims', true);
  v_sub text := current_setting('request.jwt.claim.sub', true);
  v_t1 timestamptz := now() + interval '3 days';
  v_t2 timestamptz := now() + interval '4 days';
begin
  select l.student_id, l.parent_id into v_student, v_parent
    from public.parent_student_links l limit 1;
  assert v_student is not null, 'need a student with a linked parent';

  -- Approved endorsement, one excluding the parent, one still pending.
  insert into public.escalation_reports
    (student_id, kind, title, summary, message, channels, created_by_name)
  values (v_student, 'counseling', 'Check-in', 'Seems withdrawn.', '', '{}', 'Test DO')
  returning id into v_rep;
  perform public.decide_escalation_report(v_rep, true, null, null, 'Test GC');

  insert into public.escalation_reports
    (student_id, kind, title, summary, message, channels, exclude_parent,
     other_description, created_by_name)
  values (v_student, 'other', 'Private', 'Private matter.', '', '{}', true,
          'Peer mediation', 'Test DO')
  returning id into v_rep_x;
  perform public.decide_escalation_report(v_rep_x, true, null, null, 'Test GC');

  insert into public.escalation_reports
    (student_id, kind, title, summary, message, channels, created_by_name)
  values (v_student, 'counseling', 'Waiting', 'x', '', '{}', 'Test DO')
  returning id into v_pending;

  -- (b) refusals before a round exists.
  v_failed := false;
  begin
    perform public.request_parent_availability(v_rep_x);
  exception when others then v_failed := sqlerrm like '%excluded%'; end;
  assert v_failed, 'an excluded-parent endorsement cannot ask the parent';

  v_failed := false;
  begin
    perform public.request_parent_availability(v_pending);
  exception when others then v_failed := sqlerrm like '%not accepted%'
                                       or sqlerrm like '%accepted%'; end;
  assert v_failed, 'a pending endorsement cannot ask the parent';

  -- A student with no linked parent.
  select s.id into v_nolink_student
    from public.students s
   where not exists (select 1 from public.parent_student_links l
                      where l.student_id = s.id)
   limit 1;
  if v_nolink_student is not null then
    insert into public.escalation_reports
      (student_id, kind, title, summary, message, channels, created_by_name)
    values (v_nolink_student, 'counseling', 'No parent', 'x', '', '{}', 'Test DO')
    returning id into v_rep_nolink;
    perform public.decide_escalation_report(v_rep_nolink, true, null, null, 'Test GC');
    v_failed := false;
    begin
      perform public.request_parent_availability(v_rep_nolink);
    exception when others then v_failed := sqlerrm like '%no linked parent%'; end;
    assert v_failed, 'a student without a linked parent is refused';
  else
    raise notice 'skipped: every student has a linked parent';
  end if;

  -- (a) request on an approved endorsement.
  v_round := public.request_parent_availability(v_rep);
  assert (select status from public.meeting_availability_rounds where id = v_round) = 'Open';
  assert (select round_no from public.meeting_availability_rounds where id = v_round) = 1,
    'first round is number 1';
  assert exists (select 1 from public.notifications
                  where user_id = v_parent
                    and title = 'Meeting availability requested'
                    and created_at >= now() - interval '1 minute'),
    'the parent is notified';
  assert (select count(*) from public.sms_outbox
           where related_id = v_round and kind = 'availability_request') = 1,
    'one SMS row is queued';
  assert (select length(message) from public.sms_outbox where related_id = v_round) <= 300,
    'SMS is at most 300 characters';

  -- (b) a second request while one is Open.
  v_failed := false;
  begin
    perform public.request_parent_availability(v_rep);
  exception when others then v_failed := sqlerrm like '%already in progress%'; end;
  assert v_failed, 'only one live round per endorsement';

  -- Act as the linked parent from here on.
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_parent, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', v_parent::text, true);

  -- (d) invalid submissions.
  v_failed := false;
  begin
    perform public.submit_parent_availability(v_round, '{}'::timestamptz[]);
  exception when others then v_failed := sqlerrm like '%between 1 and 10%'; end;
  assert v_failed, '0 slots refused';

  v_failed := false;
  begin
    perform public.submit_parent_availability(v_round, array(
      select now() + (g || ' days')::interval from generate_series(1, 11) g));
  exception when others then v_failed := sqlerrm like '%between 1 and 10%'; end;
  assert v_failed, '11 slots refused';

  v_failed := false;
  begin
    perform public.submit_parent_availability(v_round,
      array[v_t1, now() - interval '1 hour']);
  exception when others then v_failed := sqlerrm like '%future%'; end;
  assert v_failed, 'a past slot is refused';

  v_failed := false;
  begin
    perform public.submit_parent_availability(v_round, array[v_t1, v_t1]);
  exception when others then v_failed := sqlerrm like '%twice%'; end;
  assert v_failed, 'duplicate slots are refused';
  assert not exists (select 1 from public.meeting_availability_slots
                      where round_id = v_round),
    'refused submissions leave no slots behind';

  -- (c) a valid submission.
  perform public.submit_parent_availability(v_round, array[v_t1, v_t2]);
  assert (select status from public.meeting_availability_rounds where id = v_round) = 'Offered';
  assert (select offered_at from public.meeting_availability_rounds where id = v_round) is not null;
  assert (select count(*) from public.meeting_availability_slots
           where round_id = v_round and status = 'Offered') = 2,
    'two Offered slots';
  assert exists (select 1 from public.notifications
                  where target_role = 'Discipline_Officer'::app_role
                    and title = 'Parent offered meeting times'
                    and created_at >= now() - interval '1 minute'),
    'the DO is told';
  assert exists (select 1 from public.notifications
                  where target_role = 'Guidance_Counselor'::app_role
                    and title = 'Parent offered meeting times'
                    and created_at >= now() - interval '1 minute'),
    'Guidance is told';

  -- (d) a round that is no longer Open.
  v_failed := false;
  begin
    perform public.submit_parent_availability(v_round, array[v_t1]);
  exception when others then v_failed := sqlerrm like '%no longer open%'; end;
  assert v_failed, 'an Offered round cannot be submitted again';

  -- An Offered round also blocks a new request (Admin session).
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  perform set_config('request.jwt.claim.sub', coalesce(v_sub, ''), true);
  v_failed := false;
  begin
    perform public.request_parent_availability(v_rep);
  exception when others then v_failed := sqlerrm like '%already in progress%'; end;
  assert v_failed, 'an Offered round blocks a new request';

  -- Back to the Admin session.
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  perform set_config('request.jwt.claim.sub', coalesce(v_sub, ''), true);

  -- (e) a Declined slot from an earlier round cannot be offered again.
  insert into public.escalation_reports
    (student_id, kind, title, summary, message, channels, created_by_name)
  values (v_student, 'counseling', 'Second', 'x', '', '{}', 'Test DO')
  returning id into v_rep2;
  perform public.decide_escalation_report(v_rep2, true, null, null, 'Test GC');

  insert into public.meeting_availability_rounds
    (escalation_report_id, student_id, round_no, status)
  values (v_rep2, v_student, 1, 'Declined')
  returning id into v_old_round;
  insert into public.meeting_availability_slots (round_id, slot_at, status)
  values (v_old_round, v_t1, 'Declined');

  v_round2 := public.request_parent_availability(v_rep2);
  assert (select round_no from public.meeting_availability_rounds where id = v_round2) = 2,
    'the next round is number 2';

  perform set_config('request.jwt.claims',
    json_build_object('sub', v_parent, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', v_parent::text, true);

  v_failed := false;
  begin
    perform public.submit_parent_availability(v_round2, array[v_t1, v_t2]);
  exception when others then v_failed := sqlerrm like '%declined%'; end;
  assert v_failed, 'a declined time cannot be re-offered';

  -- 30 seconds after the declined time is still the same minute.
  v_failed := false;
  begin
    perform public.submit_parent_availability(
      v_round2, array[date_trunc('minute', v_t1) + interval '30 seconds']);
  exception when others then v_failed := sqlerrm like '%declined%'; end;
  assert v_failed, 'a time 30 seconds after a declined one is refused';

  -- Seconds-apart duplicates collapse to one minute and are refused.
  v_failed := false;
  begin
    perform public.submit_parent_availability(v_round2, array[
      date_trunc('minute', v_t2), date_trunc('minute', v_t2) + interval '20 seconds']);
  exception when others then v_failed := sqlerrm like '%twice%'; end;
  assert v_failed, 'same-minute duplicates are refused';

  -- Unknown round ids look the same as unlinked ones.
  v_failed := false;
  begin
    perform public.submit_parent_availability(gen_random_uuid(), array[v_t2]);
  exception when others then v_failed := sqlerrm like '%not found%'; end;
  assert v_failed, 'unknown round gives the generic error';

  -- submit re-checks the endorsement (Admin session flips exclude_parent).
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  perform set_config('request.jwt.claim.sub', coalesce(v_sub, ''), true);
  update public.escalation_reports set exclude_parent = true where id = v_rep2;
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_parent, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', v_parent::text, true);
  v_failed := false;
  begin
    perform public.submit_parent_availability(v_round2, array[v_t2]);
  exception when others then v_failed := sqlerrm like '%no longer needs%'; end;
  assert v_failed, 'submit re-checks the endorsement';

  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  perform set_config('request.jwt.claim.sub', coalesce(v_sub, ''), true);

end $$;

-- Decide / cancel / remind / old-flow guard.
do $$
declare
  v_student uuid; v_parent uuid;
  v_reps uuid[] := '{}';
  v_rep uuid;
  v_rA uuid; v_rB uuid; v_rC uuid; v_rD uuid; v_rE uuid; v_rF uuid; v_rB2 uuid;
  v_sA1 uuid; v_sA2 uuid; v_sB1 uuid; v_sC uuid;
  v_m uuid; v_m2 uuid; v_n int;
  v_failed boolean;
  v_claims text := current_setting('request.jwt.claims', true);
  v_sub text := current_setting('request.jwt.claim.sub', true);
  v_t1 timestamptz := now() + interval '3 days';
  v_t2 timestamptz := now() + interval '4 days';
  v_t3 timestamptz := now() + interval '5 days';
  v_t4 timestamptz := now() + interval '6 days';
begin
  select l.student_id, l.parent_id into v_student, v_parent
    from public.parent_student_links l limit 1;
  assert v_student is not null, 'need a student with a linked parent';

  -- Six approved endorsements: A approve, B decline, C past slot, D cancel,
  -- E stale reminder, F fresh (no reminder).
  for i in 1..7 loop
    insert into public.escalation_reports
      (student_id, kind, title, summary, message, channels, created_by_name)
    values (v_student, 'counseling', 'Decide ' || i, 'x', '', '{}', 'Test DO')
    returning id into v_rep;
    perform public.decide_escalation_report(v_rep, true, null, null, 'Test GC');
    v_reps := v_reps || v_rep;
  end loop;

  -- An old-flow meeting awaiting Guidance (or returned) blocks a request.
  insert into public.guidance_meetings
    (escalation_report_id, student_id, scheduled_at, location, invitee, status)
  values (v_reps[7], v_student, now() + interval '2 days', 'Office', 'student',
          'Awaiting_Guidance') returning id into v_m;
  v_failed := false;
  begin
    perform public.request_parent_availability(v_reps[7]);
  exception when others then v_failed := sqlerrm like '%awaiting Guidance%'; end;
  assert v_failed, 'an Awaiting_Guidance meeting blocks a request';
  update public.guidance_meetings set status = 'Returned' where id = v_m;
  v_failed := false;
  begin
    perform public.request_parent_availability(v_reps[7]);
  exception when others then v_failed := sqlerrm like '%awaiting Guidance%'; end;
  assert v_failed, 'a Returned meeting blocks a request';

  v_rA := public.request_parent_availability(v_reps[1]);
  v_rB := public.request_parent_availability(v_reps[2]);
  v_rD := public.request_parent_availability(v_reps[4]);

  -- Round C: Offered with a slot already in the past (inserted directly).
  insert into public.meeting_availability_rounds
    (escalation_report_id, student_id, round_no, status)
  values (v_reps[3], v_student, 1, 'Offered') returning id into v_rC;
  insert into public.meeting_availability_slots (round_id, slot_at, status)
  values (v_rC, now() - interval '1 hour', 'Offered') returning id into v_sC;

  -- Rounds E (49 hours old) and F (1 hour old), both Open.
  insert into public.meeting_availability_rounds
    (escalation_report_id, student_id, round_no, status, requested_at)
  values (v_reps[5], v_student, 1, 'Open', now() - interval '49 hours')
  returning id into v_rE;
  insert into public.meeting_availability_rounds
    (escalation_report_id, student_id, round_no, status, requested_at)
  values (v_reps[6], v_student, 1, 'Open', now() - interval '1 hour')
  returning id into v_rF;

  -- The parent offers times for A and B.
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_parent, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', v_parent::text, true);
  perform public.submit_parent_availability(v_rA, array[v_t1, v_t2]);
  perform public.submit_parent_availability(v_rB, array[v_t3, v_t4]);
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  perform set_config('request.jwt.claim.sub', coalesce(v_sub, ''), true);

  select id into v_sA1 from public.meeting_availability_slots
   where round_id = v_rA and slot_at = date_trunc('minute', v_t1);
  select id into v_sA2 from public.meeting_availability_slots
   where round_id = v_rA and slot_at = date_trunc('minute', v_t2);
  select id into v_sB1 from public.meeting_availability_slots
   where round_id = v_rB and slot_at = date_trunc('minute', v_t3);

  -- (d) refusals.
  v_failed := false;
  begin
    perform public.decide_parent_availability(v_rA, v_sB1);
  exception when others then v_failed := sqlerrm like '%does not belong%'; end;
  assert v_failed, 'a slot from another round is refused';

  v_failed := false;
  begin
    perform public.decide_parent_availability(v_rD, null);
  exception when others then v_failed := sqlerrm like '%not waiting%'; end;
  assert v_failed, 'a round that is not Offered cannot be decided';

  v_failed := false;
  begin
    perform public.decide_parent_availability(v_rC, v_sC);
  exception when others then v_failed := sqlerrm like '%already passed%'; end;
  assert v_failed, 'a past slot cannot be approved';
  assert (select status from public.meeting_availability_rounds where id = v_rC) = 'Offered',
    'a refused decision changes nothing';

  -- Length caps.
  v_failed := false;
  begin
    perform public.decide_parent_availability(v_rA, v_sA1, repeat('x', 121));
  exception when others then v_failed := sqlerrm like '%120 characters%'; end;
  assert v_failed, 'a location over 120 characters is refused';
  v_failed := false;
  begin
    perform public.decide_parent_availability(v_rA, v_sA1, null, repeat('x', 501));
  exception when others then v_failed := sqlerrm like '%500 characters%'; end;
  assert v_failed, 'a note over 500 characters is refused';

  -- An unrelated Awaiting_Guidance meeting on the same endorsement (inserted
  -- now that the round is Offered) must survive the approval.
  insert into public.guidance_meetings
    (escalation_report_id, student_id, scheduled_at, location, invitee, status)
  values (v_reps[1], v_student, now() + interval '2 days', 'Office', 'student',
          'Awaiting_Guidance') returning id into v_m;

  -- (a) approve one slot (default location).
  perform public.decide_parent_availability(v_rA, v_sA1);
  select id into v_m2 from public.guidance_meetings
   where escalation_report_id = v_reps[1] and status = 'Awaiting_Guidance';
  assert v_m2 = v_m, 'the Awaiting_Guidance meeting is left alone';
  assert (select status from public.meeting_availability_rounds where id = v_rA) = 'Approved';
  assert (select status from public.meeting_availability_slots where id = v_sA1) = 'Approved';
  assert (select status from public.meeting_availability_slots where id = v_sA2) = 'Not_Chosen';
  select id into v_m from public.guidance_meetings
   where escalation_report_id = v_reps[1] and status = 'Proposed';
  assert v_m is not null, 'one Proposed meeting exists';
  assert (select count(*) from public.guidance_meetings
           where escalation_report_id = v_reps[1] and status = 'Proposed') = 1;
  assert (select meeting_id from public.meeting_availability_rounds where id = v_rA) = v_m,
    'the round links to the meeting';
  assert (select invitee from public.guidance_meetings where id = v_m) = 'parent';
  assert (select scheduled_at from public.guidance_meetings where id = v_m)
         = date_trunc('minute', v_t1), 'meeting is at the approved slot';
  assert (select location from public.guidance_meetings where id = v_m) = 'Guidance Office',
    'default location';
  assert exists (select 1 from public.notifications
                  where user_id = v_parent and title = 'Meeting scheduled'
                    and created_at >= now() - interval '1 minute'),
    'the parent is notified';
  assert exists (select 1 from public.notifications
                  where target_role = 'Discipline_Officer'::app_role
                    and title = 'Meeting scheduled by Guidance'
                    and created_at >= now() - interval '1 minute'),
    'the DO is notified';
  assert (select count(*) from public.sms_outbox
           where kind = 'guidance_meeting' and related_id = v_m) = 1,
    'the schedule SMS is queued';
  assert (select length(message) from public.sms_outbox
           where kind = 'guidance_meeting' and related_id = v_m) <= 300;

  -- An approved round is final.
  v_failed := false;
  begin
    perform public.decide_parent_availability(v_rA, v_sA2);
  exception when others then v_failed := sqlerrm like '%not waiting%'; end;
  assert v_failed, 'an Approved round cannot be decided again';

  -- (b) decline all.
  perform public.decide_parent_availability(v_rB, null, null, 'Not suitable');
  assert (select status from public.meeting_availability_rounds where id = v_rB) = 'Declined';
  assert (select decision_note from public.meeting_availability_rounds where id = v_rB)
         = 'Not suitable';
  assert not exists (select 1 from public.meeting_availability_slots
                      where round_id = v_rB and status <> 'Declined'),
    'every slot is Declined';
  select id into v_rB2 from public.meeting_availability_rounds
   where escalation_report_id = v_reps[2] and round_no = 2 and status = 'Open';
  assert v_rB2 is not null, 'a new Open round with round_no + 1';
  assert (select requested_by from public.meeting_availability_rounds where id = v_rB2)
         is not distinct from
         (select requested_by from public.meeting_availability_rounds where id = v_rB),
    'the new round keeps requested_by';
  assert (select count(*) from public.sms_outbox
           where kind = 'availability_retry' and related_id = v_rB2) = 1,
    'the retry SMS is queued';
  assert exists (select 1 from public.notifications
                  where target_role = 'Discipline_Officer'::app_role
                    and title = 'Parent times declined by Guidance'
                    and created_at >= now() - interval '1 minute'),
    'the DO is told of the decline';

  -- (c) a declined time cannot be offered again.
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_parent, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', v_parent::text, true);
  v_failed := false;
  begin
    perform public.submit_parent_availability(v_rB2, array[v_t3]);
  exception when others then v_failed := sqlerrm like '%declined%'; end;
  assert v_failed, 'a declined time is refused in the next round';
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  perform set_config('request.jwt.claim.sub', coalesce(v_sub, ''), true);

  -- (e) cancel, and the old flow guard.
  v_failed := false;
  begin
    perform public.propose_endorsement_meeting(v_reps[4], now() + interval '2 days',
                                               'Office', 'student');
  exception when others then v_failed := sqlerrm like '%cancel the availability request first%'; end;
  assert v_failed, 'an Open round blocks the old flow';

  v_failed := false;
  begin
    perform public.propose_endorsement_meeting(v_reps[3], now() + interval '2 days',
                                               'Office', 'student');
  exception when others then v_failed := sqlerrm like '%cancel the availability request first%'; end;
  assert v_failed, 'an Offered round blocks the old flow';

  perform public.cancel_parent_availability(v_rD);
  assert (select status from public.meeting_availability_rounds where id = v_rD) = 'Cancelled';
  perform public.cancel_parent_availability(v_rC);
  assert (select status from public.meeting_availability_rounds where id = v_rC) = 'Cancelled',
    'an Offered round can be cancelled';
  v_m := public.propose_endorsement_meeting(v_reps[4], now() + interval '2 days',
                                            'Office', 'student');
  assert v_m is not null, 'the old flow works once the round is cancelled';

  v_failed := false;
  begin
    perform public.cancel_parent_availability(v_rD);
  exception when others then v_failed := sqlerrm like '%open availability request%'; end;
  assert v_failed, 'a Cancelled round cannot be cancelled again';

  -- (f) reminders: once, only for rounds older than 48 hours.
  v_n := public.remind_stale_availability_rounds();
  assert v_n >= 1, 'the 49-hour-old round is reminded';
  assert (select reminded_at from public.meeting_availability_rounds where id = v_rE)
         is not null, 'reminded_at is set';
  assert (select reminded_at from public.meeting_availability_rounds where id = v_rF)
         is null, 'the 1-hour-old round is left alone';
  assert (select count(*) from public.sms_outbox
           where kind = 'availability_reminder' and related_id = v_rE) = 1,
    'one reminder SMS';
  assert (select count(*) from public.sms_outbox
           where kind = 'availability_reminder' and related_id = v_rF) = 0;
  assert public.remind_stale_availability_rounds() = 0,
    'a second call reminds nobody';
  assert (select count(*) from public.sms_outbox
           where kind = 'availability_reminder' and related_id = v_rE) = 1,
    'still one reminder SMS';

  raise notice 'ALL PASSED';
end $$;

rollback;
