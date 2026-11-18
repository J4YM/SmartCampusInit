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

  raise notice 'ALL PASSED';
end $$;

rollback;
