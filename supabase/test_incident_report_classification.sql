-- Assertions for add_incident_report_classification.sql (+ the suggestion
-- trigger changes from change_auto_escalation_to_suggestion.sql).
-- Run in the Supabase SQL Editor on a DEV project. Everything is rolled back.
-- Needs at least one student and one Minor + one non-Minor handbook offense.
-- Expected: no exception; final NOTICE says "ALL PASSED".

begin;

do $$
declare
  v_student uuid;
  v_reporter uuid;
  v_id uuid;
  v_minor uuid;
  v_major uuid;
  r public.student_violations;
  v_failed boolean := false;
begin
  select id into v_student from public.students limit 1;
  select id into v_reporter from public.profiles limit 1;
  select id into v_minor from public.handbook_offenses where category = 'Minor' limit 1;
  select id into v_major from public.handbook_offenses where category <> 'Minor' limit 1;

  -- 1. Future incident time is rejected.
  begin
    perform public.submit_incident_report(
      v_student, now() + interval '2 days', 'x', '{}', v_reporter, null);
    v_failed := true;
  exception when others then null;
  end;
  assert not v_failed, 'future incident_at must raise';

  -- 2. Empty description is rejected.
  begin
    perform public.submit_incident_report(
      v_student, now() - interval '1 hour', '   ', '{}', v_reporter, null);
    v_failed := true;
  exception when others then null;
  end;
  assert not v_failed, 'blank description must raise';

  -- 3. Valid report: unclassified, Pending, incident_at kept, evidence stored.
  v_id := public.submit_incident_report(
    v_student, now() - interval '3 hours', 'Seen vaping behind the gym',
    array['a/b.jpg'], v_reporter, null);
  select * into r from public.student_violations where id = v_id;
  assert r.offense_id is null, 'new report must be unclassified';
  assert r.status = 'Pending', 'new report must be Pending';
  assert r.incident_at < r.created_at, 'incident_at must be earlier than created_at';
  assert (select count(*) from public.violation_evidence where violation_id = v_id) = 1,
    'evidence row expected';

  -- 4. Classify (as postgres/service the role check is bypassed only if
  --    current_user_role() allows; this test assumes the dev session is Admin).
  perform public.classify_violation(v_id, array[v_minor, v_major]);
  select * into r from public.student_violations where id = v_id;
  assert r.offense_id = v_minor, 'first offense set on original row';
  assert r.classified_at is not null, 'classified_at set';
  assert (select count(*) from public.student_violations
           where student_id = v_student and incident_notes = 'Seen vaping behind the gym') = 2,
    'second offense becomes a sibling row';

  -- 5. Classifying twice is rejected.
  v_failed := false;
  begin
    perform public.classify_violation(v_id, array[v_minor]);
    v_failed := true;
  exception when others then null;
  end;
  assert not v_failed, 'double classify must raise';

  -- 6. Legacy backfill: no row left without incident_at.
  assert not exists (select 1 from public.student_violations where incident_at is null),
    'every row has incident_at';

  -- 7. An unclassified insert must not trip the old triggers.
  insert into public.student_violations (student_id, offense_id, status, incident_at)
  values (v_student, null, 'Pending', now());

  -- 8. Suggestion triggers flag; they never file parent interventions.
  declare
    v_before int := (select count(*) from public.parent_interventions);
    v_flag uuid;
  begin
    v_flag := public.submit_incident_report(
      v_student, now() - interval '1 hour', 'racist remarks in class', '{}', v_reporter);
    perform public.classify_violation(v_flag, array[v_major]);
    assert (select suggested_escalation from public.student_violations where id = v_flag),
      'major offense must set suggested_escalation';
    assert (select count(*) from public.parent_interventions) = v_before,
      'no parent intervention may be filed automatically';
  end;

  raise notice 'ALL PASSED';
end $$;

rollback;
