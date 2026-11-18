-- Assertions for add_guidance_investigations.sql. Run in the Supabase SQL
-- Editor on a DEV project as an Admin session (Admin passes the DO and
-- Guidance role checks). Rolled back at the end.
-- The student/parent-only respond_to_meeting rule needs a real login as that
-- user; here we only assert the "not invited" refusal for the Admin caller.
-- Expected: final NOTICE "ALL PASSED".

begin;

-- Act as an Admin for the whole script. The SQL Editor has no logged-in user
-- (auth.uid() is null, so current_user_role() is null and every role check
-- fails); this impersonates an existing Admin profile for this transaction.
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
  v_student uuid; v_reporter uuid; v_minor uuid;
  v_vio uuid; v_inv uuid; v_m1 uuid; v_m2 uuid;
  v_failed boolean;
begin
  select id into v_student from public.students limit 1;
  v_reporter := auth.uid();  -- must be the caller: the session is "authenticated"
  select id into v_minor from public.handbook_offenses limit 1;

  v_vio := public.submit_incident_report(v_student, now() - interval '1 hour', 'fight', '{}', v_reporter);

  -- Unclassified cannot be escalated.
  v_failed := false;
  begin perform public.escalate_to_guidance(v_vio); v_failed := true;
  exception when others then null; end;
  assert not v_failed, 'unclassified escalate must raise';

  perform public.classify_violation(v_vio, array[v_minor]);
  v_inv := public.escalate_to_guidance(v_vio);
  assert (select status::text from public.student_violations where id = v_vio) = 'Under_Investigation';

  -- Only one investigation per case.
  v_failed := false;
  begin perform public.escalate_to_guidance(v_vio); v_failed := true;
  exception when others then null; end;
  assert not v_failed, 'second escalate must raise';

  -- Past meeting rejected.
  v_failed := false;
  begin
    perform public.schedule_guidance_meeting(v_inv, now() - interval '1 day', 'Room 1', 'both');
    v_failed := true;
  exception when others then null; end;
  assert not v_failed, 'past meeting must raise';

  v_m1 := public.schedule_guidance_meeting(v_inv, now() + interval '2 days', 'Guidance Office', 'both');
  assert (select status from public.guidance_meetings where id = v_m1) = 'Proposed';

  -- Non-invited caller cannot respond.
  v_failed := false;
  begin perform public.respond_to_meeting(v_m1, true, null); v_failed := true;
  exception when others then null; end;
  assert not v_failed, 'non-invited respond must raise';

  -- Declined meeting does not block scheduling a new one.
  update public.guidance_meetings set status = 'Declined' where id = v_m1;
  v_m2 := public.schedule_guidance_meeting(v_inv, now() + interval '3 days', 'Guidance Office', 'parent');
  assert v_m2 is not null;

  -- Findings are required.
  v_failed := false;
  begin perform public.complete_investigation(v_inv, '  ', 'Proven'); v_failed := true;
  exception when others then null; end;
  assert not v_failed, 'blank findings must raise';

  perform public.complete_investigation(v_inv, 'Both parties spoke; mutual altercation.', 'Proven', 'Warning');
  assert (select status::text from public.student_violations where id = v_vio) = 'Investigation_Complete';
  assert (select status from public.guidance_meetings where id = v_m2) = 'Cancelled';

  raise notice 'ALL PASSED';
end $$;

rollback;
