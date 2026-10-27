-- Assertions for add_endorsement_other_kind.sql. Run in the Supabase SQL Editor
-- on a DEV project as an Admin session, AFTER add_guidance_referrals.sql.
-- Rolled back at the end. Run once BEFORE the migration (fails) and once AFTER
-- (prints "ALL PASSED").

begin;

do $$
declare
  v_student uuid; v_rep uuid; v_failed boolean;
begin
  select id into v_student from public.students limit 1;

  -- An Other endorsement needs no channels and carries its description.
  insert into public.escalation_reports
    (student_id, kind, title, summary, message, channels, other_description,
     exclude_parent, created_by_name)
  values (v_student, 'other', 'Mediation', 'Needs a mediator.', '', '{}',
          'Peer mediation', true, 'Test DO')
  returning id into v_rep;

  -- Approving it messages nobody.
  perform public.decide_escalation_report(v_rep, true, null, null, 'Test GC');
  assert (select status from public.escalation_reports where id = v_rep) = 'Approved';
  assert not exists (
    select 1 from public.parent_interventions
     where student_id = v_student and sent_by = 'Guidance Office'
       and created_at >= now() - interval '1 minute'),
    'an Other approval must not message the parent';

  -- The referral Guidance gets carries the description.
  assert exists (
    select 1 from public.student_referrals
     where endorsement_id = v_rep and details like '%Peer mediation%'),
    'the referral mentions the description';

  -- An unknown kind is refused.
  v_failed := false;
  begin
    insert into public.escalation_reports
      (student_id, kind, summary, message, channels)
    values (v_student, 'bogus', 'x', '', '{}');
    v_failed := true;
  exception when others then null; end;
  assert not v_failed, 'kind must be one of the known values';

  raise notice 'ALL PASSED';
end $$;

rollback;
