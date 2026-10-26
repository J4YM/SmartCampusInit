-- Assertions for add_referral_meetings.sql. Run in the Supabase SQL Editor on a
-- DEV project as an Admin session, AFTER add_guidance_referrals.sql. It needs
-- a student with a linked parent in parent_student_links.
-- Rolled back at the end. Run once BEFORE the migration (fails) and once AFTER
-- (prints "ALL PASSED").

begin;

do $$
declare
  v_student uuid; v_parent uuid; v_ref uuid; v_m uuid; v_m2 uuid; v_failed boolean;
  v_when timestamptz := now() + interval '2 days';
begin
  select l.student_id, l.parent_id into v_student, v_parent
    from public.parent_student_links l limit 1;
  assert v_student is not null, 'need a student with a linked parent';

  insert into public.student_referrals (student_id, referred_by, is_self, concern, details)
  values (v_student, v_student, true, 'emotional', 'Test referral.')
  returning id into v_ref;

  -- student only: the parent gets nothing, and no SMS is queued.
  v_m := public.schedule_referral_meeting(v_ref, v_when, 'Guidance Office', 'student');
  assert exists (select 1 from public.notifications
                  where user_id = v_student and title = 'Guidance meeting scheduled'
                    and created_at >= now() - interval '1 minute'),
    'student invited -> student notified';
  assert not exists (select 1 from public.notifications
                      where user_id = v_parent and title = 'Guidance meeting scheduled'
                        and created_at >= now() - interval '1 minute'),
    'student only -> parent NOT notified';
  assert not exists (select 1 from public.sms_outbox where related_id = v_m),
    'student only -> no SMS queued';

  -- parent: notification + one SMS, the student is not notified again.
  v_m2 := public.schedule_referral_meeting(v_ref, v_when + interval '1 day', null, 'parent');
  assert (select status from public.guidance_meetings where id = v_m) = 'Cancelled',
    'a new invitation cancels the earlier open one';
  assert exists (select 1 from public.notifications
                  where user_id = v_parent and title = 'Guidance meeting scheduled'
                    and created_at >= now() - interval '1 minute'),
    'parent invited -> parent notified';
  assert (select count(*) from public.sms_outbox where related_id = v_m2) = 1,
    'parent invited -> exactly one SMS queued';

  -- both: SMS once.
  v_m := public.schedule_referral_meeting(v_ref, v_when + interval '2 days', null, 'both');
  assert (select count(*) from public.sms_outbox where related_id = v_m) = 1,
    'both -> one SMS';
  assert (select status from public.student_referrals where id = v_ref) = 'In_Progress',
    'scheduling moves the referral to In_Progress';

  -- Past times are refused.
  v_failed := false;
  begin
    perform public.schedule_referral_meeting(v_ref, now() - interval '1 hour', null, 'student');
  exception when others then
    v_failed := sqlerrm like '%must be scheduled in the future%';
  end;
  assert v_failed, 'a past time is refused';

  -- Guidance reads referral meetings.
  assert exists (
    select 1 from pg_policies
     where tablename = 'guidance_meetings' and policyname = 'guidance_meetings_staff_select'
       and qual ilike '%referral_id is not null%'),
    'Guidance reads meetings that belong to a referral';

  raise notice 'ALL PASSED';
end $$;

rollback;
