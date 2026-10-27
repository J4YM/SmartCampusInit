-- Assertions for add_endorsement_meetings.sql. Run in the Supabase SQL Editor
-- on a DEV project as an Admin session (Admin passes the DO / Guidance role
-- checks), AFTER add_endorsement_other_kind.sql, reword_meeting_invitations.sql
-- and add_endorsement_meetings.sql. It needs a student with a linked parent.
-- Rolled back at the end. Run once BEFORE the migration (fails) and once AFTER
-- (prints "ALL PASSED").

begin;

do $$
declare
  v_student uuid; v_parent uuid;
  v_rep uuid; v_rep_x uuid; v_pending uuid;
  v_m uuid; v_m2 uuid; v_m3 uuid; v_failed boolean;
  v_when timestamptz := now() + interval '3 days';
begin
  select l.student_id, l.parent_id into v_student, v_parent
    from public.parent_student_links l limit 1;
  assert v_student is not null, 'need a student with a linked parent';

  -- An approved counseling endorsement, and one that excludes the parent.
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

  -- A not-yet-approved endorsement cannot get a meeting.
  insert into public.escalation_reports
    (student_id, kind, title, summary, message, channels, created_by_name)
  values (v_student, 'counseling', 'Waiting', 'x', '', '{}', 'Test DO')
  returning id into v_pending;
  v_failed := false;
  begin
    perform public.propose_endorsement_meeting(v_pending, v_when, 'Office', 'student');
  exception when others then v_failed := sqlerrm like '%accepted%'; end;
  assert v_failed, 'only an accepted endorsement can get a meeting';

  -- Past times are refused.
  v_failed := false;
  begin
    perform public.propose_endorsement_meeting(v_rep, now() - interval '1 hour', 'Office', 'student');
  exception when others then v_failed := sqlerrm like '%in the future%'; end;
  assert v_failed, 'a past time is refused';

  -- Proposing: Guidance is told, nobody invited yet, no SMS.
  v_m := public.propose_endorsement_meeting(v_rep, v_when, 'Guidance Office', 'both');
  assert (select status from public.guidance_meetings where id = v_m) = 'Awaiting_Guidance';
  assert exists (select 1 from public.notifications
                  where target_role = 'Guidance_Counselor'::app_role
                    and title = 'Meeting awaiting your confirmation'
                    and created_at >= now() - interval '1 minute'),
    'Guidance is told a meeting awaits confirmation';
  assert not exists (select 1 from public.notifications
                      where user_id in (v_student, v_parent)
                        and title = 'Meeting invitation'
                        and created_at >= now() - interval '1 minute'),
    'nobody is invited before Guidance confirms';
  assert not exists (select 1 from public.sms_outbox where related_id = v_m),
    'no SMS before Guidance confirms';

  -- Confirming with a changed time invites both and queues one SMS.
  perform public.confirm_endorsement_meeting(v_m, v_when + interval '1 day', null);
  assert (select status from public.guidance_meetings where id = v_m) = 'Proposed';
  assert (select scheduled_at from public.guidance_meetings where id = v_m)
         = v_when + interval '1 day', 'the changed time is stored';
  assert exists (select 1 from public.notifications
                  where user_id = v_student and title = 'Meeting invitation'
                    and message like 'You are invited to a meeting on %'
                    and created_at >= now() - interval '1 minute'),
    'student invited after confirmation';
  assert exists (select 1 from public.notifications
                  where user_id = v_parent and title = 'Meeting invitation'
                    and created_at >= now() - interval '1 minute'),
    'parent invited after confirmation';
  assert (select count(*) from public.sms_outbox where related_id = v_m) = 1,
    'exactly one SMS for a both invitation';
  assert exists (select 1 from public.notifications
                  where target_role = 'Discipline_Officer'::app_role
                    and title = 'Meeting confirmed by Guidance'
                    and message like '%changed%'
                    and created_at >= now() - interval '1 minute'),
    'the DO is told the time changed';

  -- It cannot be confirmed twice.
  v_failed := false;
  begin
    perform public.confirm_endorsement_meeting(v_m, null, null);
  exception when others then v_failed := true; end;
  assert v_failed, 'a confirmed meeting cannot be confirmed again';

  -- Return: a note is required, the DO gets it, it cannot then be confirmed.
  v_m2 := public.propose_endorsement_meeting(v_rep, v_when, 'Office', 'student');
  assert (select status from public.guidance_meetings where id = v_m) = 'Proposed',
    'a live invitation stays until the new time is confirmed';
  v_failed := false;
  begin
    perform public.return_endorsement_meeting(v_m2, '   ');
  exception when others then v_failed := true; end;
  assert v_failed, 'returning needs a note';
  perform public.return_endorsement_meeting(v_m2, 'Please pick Friday.');
  assert (select status from public.guidance_meetings where id = v_m2) = 'Returned';
  assert (select guidance_note from public.guidance_meetings where id = v_m2)
         = 'Please pick Friday.';
  v_failed := false;
  begin
    perform public.confirm_endorsement_meeting(v_m2, null, null);
  exception when others then v_failed := true; end;
  assert v_failed, 'a returned meeting cannot be confirmed';

  -- Confirming a new time replaces the earlier live invitation.
  v_m3 := public.propose_endorsement_meeting(
    v_rep, v_when + interval '5 days', 'Office', 'student');
  perform public.confirm_endorsement_meeting(v_m3, null, null);
  assert (select status from public.guidance_meetings where id = v_m) = 'Cancelled',
    'the earlier live meeting is cancelled once the new one is confirmed';

  -- Exclude parent: only the student can be invited; the parent hears nothing.
  v_failed := false;
  begin
    perform public.propose_endorsement_meeting(v_rep_x, v_when, 'Office', 'parent');
  exception when others then v_failed := sqlerrm like '%parent%'; end;
  assert v_failed, 'an excluded parent cannot be invited';
  v_m := public.propose_endorsement_meeting(v_rep_x, v_when, 'Office', 'student');
  perform public.confirm_endorsement_meeting(v_m, null, null);
  assert not exists (select 1 from public.sms_outbox where related_id = v_m),
    'no SMS for a student-only meeting';

  -- Students and parents cannot read an unconfirmed meeting.
  assert exists (
    select 1 from pg_policies
     where tablename = 'guidance_meetings'
       and policyname = 'guidance_meetings_student_select'
       and qual ilike '%Awaiting_Guidance%'),
    'the student policy hides unconfirmed meetings';
  assert exists (
    select 1 from pg_policies
     where tablename = 'guidance_meetings'
       and policyname = 'guidance_meetings_parent_select'
       and qual ilike '%Awaiting_Guidance%'),
    'the parent policy hides unconfirmed meetings';

  raise notice 'ALL PASSED';
end $$;

rollback;
