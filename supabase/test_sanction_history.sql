-- Assertions for add_sanction_history.sql. Run in the Supabase SQL Editor on a
-- DEV project as an Admin session, AFTER add_sanctions_schema.sql and
-- add_sanction_history.sql. It needs a student with a linked parent and a
-- handbook offense. Rolled back at the end. Run once BEFORE the migration
-- (fails: function does not exist) and once AFTER (prints "ALL PASSED").

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
  v_student uuid; v_parent uuid; v_other_parent uuid; v_offense uuid;
  v_viol uuid; v_viol2 uuid;
  v_failed boolean;
begin
  select l.student_id, l.parent_id into v_student, v_parent
    from public.parent_student_links l limit 1;
  assert v_student is not null, 'need a student with a linked parent';
  select p.id into v_other_parent from public.profiles p
   where p.role::text = 'Parent'
     and not exists (select 1 from public.parent_student_links l
                      where l.parent_id = p.id and l.student_id = v_student)
   limit 1;
  assert v_other_parent is not null, 'need a second, unlinked parent';
  select id into v_offense from public.handbook_offenses limit 1;
  assert v_offense is not null, 'need a handbook offense';

  -- No sanctions yet: zero rows for the linked parent.
  assert (select count(*) from public.my_sanction_history(v_student, v_parent)) = 0,
    'no sanctions yet means no rows';

  -- Two sanctions: one open-ended (ends_on null), one with an end date.
  insert into public.student_violations (student_id, offense_id, status, incident_at, reported_by)
  values (v_student, v_offense, 'Pending', now(), auth.uid()) returning id into v_viol;
  insert into public.sanctions
    (violation_id, student_id, basis, sanction_type, description,
     effective_on, ends_on, affects_enrollment, override_reason)
  values (v_viol, v_student, 'custom', 'warning', 'Verbal warning',
          current_date - 5, null, false, 'internal only');

  insert into public.student_violations (student_id, offense_id, status, incident_at, reported_by)
  values (v_student, v_offense, 'Pending', now(), auth.uid()) returning id into v_viol2;
  insert into public.sanctions
    (violation_id, student_id, basis, sanction_type, description,
     effective_on, ends_on, affects_enrollment)
  values (v_viol2, v_student, 'custom', 'suspension', '3-day suspension',
          current_date - 1, current_date + 2, false);

  -- (a) the linked parent (anon-style p_parent_id) sees both, newest first.
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  assert (select count(*) from public.my_sanction_history(v_student, v_parent)) = 2,
    'the linked parent sees both sanctions';
  assert (select sanction_type from public.my_sanction_history(v_student, v_parent)
           limit 1) = 'suspension', 'newest effective date comes first';
  assert (select count(*) from public.my_sanction_history(v_student, v_parent)
           where ends_on is null) = 1, 'an open-ended sanction has a null end';

  -- (b) an unlinked parent id is refused.
  v_failed := false;
  begin
    perform * from public.my_sanction_history(v_student, v_other_parent);
  exception when others then v_failed := sqlstate = '42501'; end;
  assert v_failed, 'an unlinked parent gets 42501';

  -- (c) the columns are exactly the safe seven: no override reason, decider
  -- or basis.
  assert (select count(*) from jsonb_object_keys(
            (select to_jsonb(h) from public.my_sanction_history(v_student, v_parent) h limit 1))) = 7,
    'exactly seven columns are returned';
  assert not exists (
    select 1 from jsonb_object_keys(
      (select to_jsonb(h) from public.my_sanction_history(v_student, v_parent) h limit 1)) k
     where k in ('override_reason', 'decided_by', 'basis', 'handbook_offense_id')),
    'internal fields are never returned';

  raise notice 'ALL PASSED';
end $$;

rollback;
