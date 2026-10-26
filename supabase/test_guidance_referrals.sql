-- Assertions for add_guidance_referrals.sql. Run in the Supabase SQL Editor on
-- a DEV project as an Admin session, AFTER add_concern_reports.sql.
-- Rolled back at the end. Run once BEFORE the migration (fails at the first
-- assertion) and once AFTER (prints "ALL PASSED").

begin;

do $$
declare
  v_student uuid; v_rep uuid; v_ref uuid; v_self uuid; v_failed boolean;
begin
  select id into v_student from public.students limit 1;

  -- No classmate referral is left in Guidance's table.
  assert not exists (select 1 from public.student_referrals where is_self = false),
    'no is_self = false rows remain in student_referrals';

  -- Self-only submit: the old five-argument overload is gone.
  assert not exists (
    select 1 from pg_proc
     where proname = 'submit_student_referral' and pronargs = 5),
    'the classmate overload of submit_student_referral is dropped';

  v_self := public.submit_student_referral(v_student, 'emotional', 'I feel overwhelmed.', false);
  assert (select source from public.student_referrals where id = v_self) = 'self';
  assert exists (select 1 from public.my_student_referrals(v_student) m where m.id = v_self),
    'the student sees their own self referral';

  -- Guidance is told, not the DO.
  assert exists (
    select 1 from public.notifications
     where target_role = 'Guidance_Counselor'::app_role
       and title in ('New student referral', 'Urgent student referral')
       and created_at >= now() - interval '1 minute'),
    'Guidance notified of a self referral';

  -- Approving an endorsement creates exactly one referral.
  insert into public.escalation_reports
    (student_id, kind, title, summary, message, channels, created_by_name)
  values (v_student, 'counseling', 'Check-in', 'Seems withdrawn lately.', '', '{}', 'Test DO')
  returning id into v_rep;
  perform public.decide_escalation_report(v_rep, true, null, null, 'Test GC');
  assert (select count(*) from public.student_referrals
           where endorsement_id = v_rep and source = 'endorsement') = 1,
    'approving an endorsement creates one referral';
  update public.escalation_reports set decision_note = 'again' where id = v_rep;
  assert (select count(*) from public.student_referrals where endorsement_id = v_rep) = 1,
    'updating an approved endorsement again creates no second referral';

  -- The student's own list never shows the endorsement referral.
  assert not exists (
    select 1 from public.my_student_referrals(v_student) m
      join public.student_referrals r on r.id = m.id
     where r.source = 'endorsement'),
    'my_student_referrals omits endorsement referrals';

  -- Privacy: no policy lets the Discipline Officer read referrals.
  assert not exists (
    select 1 from pg_policies
     where tablename = 'student_referrals' and roles::text like '%authenticated%'
       and (qual ilike '%Discipline_Officer%' or with_check ilike '%Discipline_Officer%')),
    'the DO must not read or update referrals';
  assert exists (
    select 1 from pg_policies
     where tablename = 'student_referrals'
       and qual ilike '%Guidance_Counselor%'),
    'Guidance reads referrals';

  raise notice 'ALL PASSED';
end $$;

rollback;
