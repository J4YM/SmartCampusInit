-- Assertions for add_investigation_outcome.sql. Run in the Supabase SQL Editor
-- on a DEV project as an Admin session (Admin passes the DO role checks); like
-- the other test_*.sql files it needs a session whose current_user_role()
-- resolves. Rolled back at the end. Run it once BEFORE the migration (it fails
-- at the first assertion) and once AFTER (it prints "ALL PASSED").

begin;

do $$
declare
  v_student uuid; v_reporter uuid; v_offense uuid;
  v_vio uuid; v_inv uuid; v_vio2 uuid; v_inv2 uuid; v_vio3 uuid; v_inv3 uuid;
  v_failed boolean;
begin
  assert exists (
    select 1 from information_schema.columns
     where table_name = 'guidance_investigations' and column_name = 'outcome'),
    'outcome column must exist';
  assert to_regprocedure('public.complete_investigation(uuid, text, text)') is null,
    'old 3-argument complete_investigation must be dropped';

  select id into v_student from public.students limit 1;
  select id into v_reporter from public.profiles limit 1;
  select id into v_offense from public.handbook_offenses limit 1;

  -- Case 1: Not Proven.
  v_vio := public.submit_incident_report(v_student, now() - interval '1 hour', 'fight', '{}', v_reporter);
  perform public.classify_violation(v_vio, array[v_offense]);
  v_inv := public.escalate_to_guidance(v_vio);

  -- Missing / invalid outcome raises.
  v_failed := false;
  begin perform public.complete_investigation(v_inv, 'Findings.', null); v_failed := true;
  exception when others then null; end;
  assert not v_failed, 'null outcome must raise';
  v_failed := false;
  begin perform public.complete_investigation(v_inv, 'Findings.', 'Maybe'); v_failed := true;
  exception when others then null; end;
  assert not v_failed, 'invalid outcome must raise';
  assert (select status from public.guidance_investigations where id = v_inv) = 'Open',
    'failed completion leaves the investigation Open';

  -- While Open the outcome cannot be set.
  v_failed := false;
  begin perform public.set_investigation_outcome(v_inv, 'Proven'); v_failed := true;
  exception when others then null; end;
  assert not v_failed, 'cannot set outcome on an Open investigation';

  perform public.complete_investigation(v_inv, 'No evidence.', 'Not_Proven', 'None');
  assert (select outcome from public.guidance_investigations where id = v_inv) = 'Not_Proven',
    'outcome stored';
  assert (select status::text from public.student_violations where id = v_vio) = 'Investigation_Complete';
  assert (select archived_at from public.student_violations where id = v_vio) is not null,
    'Not_Proven completion archives the violation';
  assert (select expired_at from public.student_violations where id = v_vio) is null,
    'Not_Proven archive is not an expiry';

  -- Not Proven blocks a sanction.
  v_failed := false;
  begin
    perform public.record_sanction(v_vio, 'custom', null, 'warning', 'Warn', null, null, false, null);
    v_failed := true;
  exception when others then null; end;
  assert not v_failed, 'Not_Proven must block record_sanction';
  assert not exists (select 1 from public.sanctions where violation_id = v_vio);

  -- Flipping to Proven (no sanction yet) lets the sanction through.
  perform public.set_investigation_outcome(v_inv, 'Proven');
  assert (select outcome from public.guidance_investigations where id = v_inv) = 'Proven';
  assert (select archived_at from public.student_violations where id = v_vio) is null,
    'Not_Proven -> Proven restores the violation';
  assert (select restored_at from public.student_violations where id = v_vio) is not null,
    'restore stamps restored_at';
  perform public.set_investigation_outcome(v_inv, 'Not_Proven');
  assert (select archived_at from public.student_violations where id = v_vio) is not null,
    'Proven -> Not_Proven archives again';
  perform public.set_investigation_outcome(v_inv, 'Proven');
  assert (select archived_at from public.student_violations where id = v_vio) is null;
  perform public.record_sanction(v_vio, 'custom', null, 'warning', 'Warn', null, null, false, null);
  assert exists (select 1 from public.sanctions where violation_id = v_vio);

  -- Once a sanction exists the verdict is frozen.
  v_failed := false;
  begin perform public.set_investigation_outcome(v_inv, 'Not_Proven'); v_failed := true;
  exception when others then null; end;
  assert not v_failed, 'outcome cannot change after a sanction';
  assert (select outcome from public.guidance_investigations where id = v_inv) = 'Proven';

  -- Case 2: Proven can be sanctioned straight away.
  v_vio2 := public.submit_incident_report(v_student, now() - interval '1 hour', 'fight 2', '{}', v_reporter);
  perform public.classify_violation(v_vio2, array[v_offense]);
  v_inv2 := public.escalate_to_guidance(v_vio2);
  perform public.complete_investigation(v_inv2, 'Confirmed.', 'Proven');
  perform public.record_sanction(v_vio2, 'custom', null, 'warning', 'Warn', null, null, false, null);
  assert exists (select 1 from public.sanctions where violation_id = v_vio2),
    'Proven can be sanctioned';
  assert (select archived_at from public.student_violations where id = v_vio2) is null,
    'Proven completion does not archive';

  -- Case 3: an Open investigation can still be sanctioned early (override).
  v_vio3 := public.submit_incident_report(v_student, now() - interval '1 hour', 'fight 3', '{}', v_reporter);
  perform public.classify_violation(v_vio3, array[v_offense]);
  v_inv3 := public.escalate_to_guidance(v_vio3);
  perform public.record_sanction(v_vio3, 'custom', null, 'warning', 'Warn', null, null, false, 'Urgent');
  assert exists (select 1 from public.sanctions where violation_id = v_vio3),
    'early sanction on Open still works';
  assert (select status from public.guidance_investigations where id = v_inv3) = 'Complete';

  raise notice 'ALL PASSED';
end $$;

rollback;
