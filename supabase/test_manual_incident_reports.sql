-- Assertions for add_manual_incident_reports.sql. Run in the Supabase SQL
-- Editor on a DEV project as an Admin session, AFTER add_do_investigations.sql
-- and add_manual_incident_reports.sql. Needs a student with a linked parent, a
-- handbook offense and a concern report. Rolled back at the end. Run once
-- BEFORE the migration (fails) and once AFTER (prints "ALL PASSED").

begin;

do $$
declare v_admin uuid;
begin
  select id into v_admin from public.profiles where role::text = 'Admin' limit 1;
  assert v_admin is not null, 'need an Admin profile to run this test';
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', v_admin::text, true);
end $$;

do $$
declare
  v_student uuid; v_parent uuid; v_offense uuid; v_viol uuid; v_viol2 uuid;
  v_before_int int; v_before_notif int; v_failed boolean;
  v_claims text := current_setting('request.jwt.claims', true);
  v_sub text := current_setting('request.jwt.claim.sub', true);
begin
  select l.student_id, l.parent_id into v_student, v_parent
    from public.parent_student_links l limit 1;
  assert v_student is not null, 'need a student with a linked parent';
  select id into v_offense from public.handbook_offenses limit 1;
  assert v_offense is not null, 'need a handbook offense';

  select count(*) into v_before_int from public.parent_interventions
   where student_id = v_student;
  select count(*) into v_before_notif from public.notifications
   where target_role::text = 'Parent' and user_id = v_parent;

  -- (a) Quiet by default: one violation, nothing sent to the parent.
  v_viol := public.report_incident(v_student, v_offense, 'Found vaping in the restroom',
                                   now() - interval '1 hour', 'Restroom 2');
  assert v_viol is not null, 'report_incident returns the violation id';
  assert (select source from public.student_violations where id = v_viol) = 'student_affairs',
    'marked as reported by Student Affairs';
  assert (select status::text from public.student_violations where id = v_viol) = 'Pending',
    'starts Pending';
  assert (select incident_notes from public.student_violations where id = v_viol)
           = 'Found vaping in the restroom', 'the description is the incident notes';
  assert (select count(*) from public.parent_interventions where student_id = v_student)
           = v_before_int, 'no parent message when notify is off';
  assert (select count(*) from public.notifications
           where target_role::text = 'Parent' and user_id = v_parent) = v_before_notif,
    'no parent notification when notify is off';

  -- (b) Notify on request, once.
  perform public.notify_parent_of_incident(v_viol);
  assert (select count(*) from public.parent_interventions where student_id = v_student)
           = v_before_int + 1, 'the DO can notify the parent afterwards';

  -- (c) Notify at save time.
  v_viol2 := public.report_incident(v_student, v_offense, 'Second incident', now(),
                                    null, true);
  assert (select count(*) from public.parent_interventions where student_id = v_student)
           = v_before_int + 2, 'p_notify_parent = true sends one message';

  -- (d) Validation.
  v_failed := false;
  begin perform public.report_incident(v_student, v_offense, '   ', now());
  exception when others then v_failed := true; end;
  assert v_failed, 'a blank description is refused';

  v_failed := false;
  begin perform public.report_incident(v_student, gen_random_uuid(), 'x', now());
  exception when others then v_failed := true; end;
  assert v_failed, 'an unknown offense is refused';

  -- (e) Only the DO or Admin.
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  v_failed := false;
  begin perform public.report_incident(v_student, v_offense, 'nope', now());
  exception when others then v_failed := sqlstate = '42501'; end;
  assert v_failed, 'an anonymous caller gets 42501';

  perform set_config('request.jwt.claims', v_claims, true);
  perform set_config('request.jwt.claim.sub', v_sub, true);
  assert (select count(*) from public.audit_logs
           where action = 'Reported incident' and record_id = v_viol::text) = 1,
    'the incident is audit-logged';

  raise notice 'ALL PASSED';
end $$;

rollback;
