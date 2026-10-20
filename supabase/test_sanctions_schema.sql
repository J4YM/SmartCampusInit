-- Assertions for add_sanctions_schema.sql. Run in the Supabase SQL Editor on a
-- DEV project as an Admin/Discipline_Officer session. Rolled back at the end.
-- Needs: one student, one Minor and one non-Minor handbook offense, and the
-- guidance script (add_guidance_investigations.sql) already applied.
-- Expected: final NOTICE "ALL PASSED".

begin;

do $$
declare
  v_student uuid;
  v_reporter uuid;
  v_minor uuid;
  v_major uuid;
  v_a uuid; v_b uuid; v_c uuid;
  v_failed boolean;
begin
  select id into v_student from public.students limit 1;
  select id into v_reporter from public.profiles limit 1;
  select id into v_minor from public.handbook_offenses where category = 'Minor' limit 1;
  select id into v_major from public.handbook_offenses where category <> 'Minor' limit 1;

  -- A: auto_record_minor on an unclassified case raises.
  v_a := public.submit_incident_report(v_student, now() - interval '1 hour', 'a', '{}', v_reporter);
  v_failed := false;
  begin perform public.auto_record_minor(v_a); v_failed := true;
  exception when others then null; end;
  assert not v_failed, 'unclassified auto-record must raise';

  -- B: classified Minor auto-records: sanction row + Resolved.
  perform public.classify_violation(v_a, array[v_minor]);
  perform public.auto_record_minor(v_a);
  assert (select status::text from public.student_violations where id = v_a) = 'Resolved';
  assert (select count(*) from public.sanctions where violation_id = v_a) = 1;

  -- C: second sanction on the same case raises (unique / already resolved).
  v_failed := false;
  begin
    perform public.record_sanction(v_a, 'custom', null, 'other', 'again', null, null, false, null);
    v_failed := true;
  exception when others then null; end;
  assert not v_failed, 'double sanction must raise';

  -- D: auto-record on a non-Minor raises.
  v_b := public.submit_incident_report(v_student, now() - interval '1 hour', 'b', '{}', v_reporter);
  perform public.classify_violation(v_b, array[v_major]);
  v_failed := false;
  begin perform public.auto_record_minor(v_b); v_failed := true;
  exception when others then null; end;
  assert not v_failed, 'non-minor auto-record must raise';

  -- E: non_readmission sets enrollment standing.
  perform public.record_sanction(
    v_b, 'custom', null, 'non_readmission', 'Not to be readmitted', null, null, true, null);
  assert (select enrollment_standing from public.students where id = v_student) = 'Non_Readmission';

  -- F: affects_enrollment must match type.
  v_c := public.submit_incident_report(v_student, now() - interval '1 hour', 'c', '{}', v_reporter);
  perform public.classify_violation(v_c, array[v_major]);
  v_failed := false;
  begin
    perform public.record_sanction(v_c, 'custom', null, 'warning', 'w', null, null, true, null);
    v_failed := true;
  exception when others then null; end;
  assert not v_failed, 'warning with affects_enrollment must raise';

  -- G: with-guidance case needs an override reason.
  update public.student_violations set status = 'Under_Investigation' where id = v_c;
  v_failed := false;
  begin
    perform public.record_sanction(v_c, 'custom', null, 'warning', 'w', null, null, false, '  ');
    v_failed := true;
  exception when others then null; end;
  assert not v_failed, 'with-guidance sanction without reason must raise';
  perform public.record_sanction(v_c, 'custom', null, 'warning', 'w', null, null, false, 'Student graduating');
  assert (select override_reason from public.sanctions where violation_id = v_c) = 'Student graduating';

  raise notice 'ALL PASSED';
end $$;

rollback;
