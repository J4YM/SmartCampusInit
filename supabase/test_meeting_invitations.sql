-- Assertions for reword_meeting_invitations.sql. Run in the Supabase SQL Editor
-- on a DEV project as an Admin session, AFTER add_referral_meetings.sql and
-- add_do_investigations.sql. It needs a student with a linked parent.
-- Rolled back at the end. Run once BEFORE the migration (fails) and once AFTER
-- (prints "ALL PASSED").

begin;

do $$
declare
  v_student uuid; v_parent uuid; v_ref uuid; v_m uuid; v_msg text;
begin
  -- Exact wording, student and parent.
  assert public.meeting_invitation_text('Oct 30, 2026 09:00 AM', 'Guidance Office')
    = 'You are invited to a meeting on Oct 30, 2026 09:00 AM at Guidance Office. '
      || 'Please confirm in your dashboard.',
    'student wording';
  assert public.meeting_invitation_text('Oct 30, 2026 09:00 AM', 'Guidance Office', 'Ana Cruz')
    = 'You are invited to a meeting on Oct 30, 2026 09:00 AM at Guidance Office '
      || 'regarding Ana Cruz. Please confirm in the Parent Portal.',
    'parent wording';
  assert public.meeting_invitation_text('Oct 30, 2026 09:00 AM', null)
    = 'You are invited to a meeting on Oct 30, 2026 09:00 AM. '
      || 'Please confirm in your dashboard.',
    'no location, no " at "';

  -- The SMS opens with the invitation and stays within 300 characters.
  v_msg := public.meeting_invitation_sms(
    'Oct 30, 2026 09:00 AM', repeat('Long room name ', 30), 'Ana Cruz', 'STI Baliuag');
  assert v_msg like 'You are invited to a meeting on %', 'sms opens with the invitation';
  assert length(v_msg) <= 300, 'sms is at most 300 characters';

  -- The schedulers use it.
  select l.student_id, l.parent_id into v_student, v_parent
    from public.parent_student_links l limit 1;
  assert v_student is not null, 'need a student with a linked parent';
  insert into public.student_referrals (student_id, referred_by, is_self, concern, details)
  values (v_student, v_student, true, 'emotional', 'Test referral.')
  returning id into v_ref;
  v_m := public.schedule_referral_meeting(
    v_ref, now() + interval '2 days', 'Guidance Office', 'parent');
  assert exists (
    select 1 from public.sms_outbox
     where related_id = v_m and message like 'You are invited to a meeting on %'),
    'the referral SMS opens with the invitation';
  assert exists (
    select 1 from public.notifications
     where user_id = v_parent and message like 'You are invited to a meeting on %'
       and created_at >= now() - interval '1 minute'),
    'the parent notification opens with the invitation';

  raise notice 'ALL PASSED';
end $$;

rollback;
