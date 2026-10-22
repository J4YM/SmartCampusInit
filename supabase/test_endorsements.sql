-- Assertions for add_endorsements.sql. Run in the Supabase SQL Editor on a DEV
-- project as an Admin session (Admin passes the DO / Guidance role checks).
-- Rolled back at the end. Run it once BEFORE the migration (it fails at the
-- first assertion) and once AFTER (it prints "ALL PASSED").

begin;

do $$
declare
  v_student uuid; v_other uuid; v_reporter uuid; v_offense uuid;
  v_vio uuid; v_rep uuid; v_ref uuid; v_failed boolean;
begin
  select id into v_student from public.students limit 1;
  select id into v_other from public.students where id <> v_student limit 1;
  select id into v_reporter from public.profiles limit 1;
  select id into v_offense from public.handbook_offenses limit 1;

  -- A counseling-only endorsement needs no message and no channels, and has
  -- no violation behind it.
  insert into public.escalation_reports
    (student_id, kind, summary, message, channels, created_by_name)
  values (v_student, 'counseling', 'Seems withdrawn lately.', '', '{}', 'Test DO')
  returning id into v_rep;

  -- Approving it must not notify the parent.
  perform public.decide_escalation_report(v_rep, true, null, null, 'Test GC');
  assert (select status from public.escalation_reports where id = v_rep) = 'Approved';
  assert (select intervention_id from public.escalation_reports where id = v_rep) is null,
    'counseling approval must not create a parent intervention';
  assert not exists (
    select 1 from public.parent_interventions
     where student_id = v_student and sent_by = 'Guidance Office'
       and created_at >= now() - interval '1 minute'),
    'counseling approval must not message the parent';

  -- History: nothing for a student who was never endorsed...
  assert (select count(*) from public.endorsement_violation_history(v_other)) = 0
    or exists (select 1 from public.escalation_reports where student_id = v_other),
    'un-endorsed student must return no history';

  -- ...and the offense, date and status for an endorsed one, with no
  -- sanction column anywhere in the result.
  v_vio := public.submit_incident_report(v_student, now() - interval '1 hour', 'fight', '{}', v_reporter);
  perform public.classify_violation(v_vio, array[v_offense]);
  assert exists (
    select 1 from public.endorsement_violation_history(v_student) h
     where h.violation_id = v_vio),
    'endorsed student history must include the violation';
  assert not exists (
    select 1 from unnest(
      (select proargnames from pg_proc where proname = 'endorsement_violation_history')
    ) as n where n ilike '%sanction%' or n ilike '%override%' or n ilike '%finding%'),
    'history must not expose sanction, override or findings columns';

  -- A referral can be endorsed once, and not after it is closed.
  insert into public.student_referrals (student_id, referred_by, is_self, concern, details)
  values (v_student, v_student, true, 'emotional', 'I feel overwhelmed.')
  returning id into v_ref;
  insert into public.escalation_reports
    (student_id, kind, summary, message, channels, referral_id)
  values (v_student, 'counseling', 'From referral.', '', '{}', v_ref);
  assert (select status from public.student_referrals where id = v_ref) = 'In_Progress',
    'endorsing a referral marks it in progress';

  v_failed := false;
  begin
    insert into public.escalation_reports
      (student_id, kind, summary, message, channels, referral_id)
    values (v_student, 'counseling', 'Again.', '', '{}', v_ref);
    v_failed := true;
  exception when others then null; end;
  assert not v_failed, 'a referral cannot be endorsed twice';

  update public.student_referrals set status = 'Closed' where id = v_ref;
  insert into public.student_referrals (student_id, referred_by, is_self, concern, details, status)
  values (v_student, v_student, true, 'other', 'Old one.', 'Closed')
  returning id into v_ref;
  v_failed := false;
  begin
    insert into public.escalation_reports
      (student_id, kind, summary, message, channels, referral_id)
    values (v_student, 'counseling', 'Closed.', '', '{}', v_ref);
    v_failed := true;
  exception when others then null; end;
  assert not v_failed, 'a closed referral cannot be endorsed';

  -- Referrals belong to the DO: Guidance has no policy on them.
  assert not exists (
    select 1 from pg_policies
     where tablename = 'student_referrals'
       and (qual ilike '%Guidance_Counselor%' or with_check ilike '%Guidance_Counselor%')),
    'Guidance must not read or update referrals';

  -- Guidance cannot read sanctions.
  assert not exists (
    select 1 from pg_policies
     where tablename = 'sanctions'
       and qual ilike '%Guidance_Counselor%'),
    'Guidance must not read sanctions';

  -- No sanction rows or trigger left in the counselor logs.
  assert not exists (select 1 from public.counseling_archive_logs where log_type = 'sanction'),
    'sanction log rows must be gone';
  assert not exists (
    select 1 from pg_trigger where tgname = 'log_sanction_to_archive'),
    'sanction log trigger must be gone';

  raise notice 'ALL PASSED';
end $$;

rollback;
