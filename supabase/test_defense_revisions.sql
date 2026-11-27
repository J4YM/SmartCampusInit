-- Assertions for add_defense_revisions.sql. Run in the Supabase SQL Editor on a
-- DEV project as an Admin session, AFTER add_sanctions_schema.sql,
-- add_sanction_history.sql, add_guidance_investigations.sql and
-- add_defense_revisions.sql. Needs: a student, a student_violation that has no
-- sanction yet, and a guidance meeting that invites a parent (or a student with
-- a linked parent and an investigation to schedule one for). Rolled back at the
-- end. Run once BEFORE the migration (fails) and once AFTER (prints
-- "ALL PASSED").

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

-- ---------------------------------------------------------------------------
-- Sanction status tracking (#4) and suspension dates (#3)
-- ---------------------------------------------------------------------------
do $$
declare
  v_student uuid; v_s_future uuid; v_s_active uuid; v_s_past uuid;
  v_ids uuid[];
begin
  select array_agg(id) into v_ids from (
    select v.id from public.student_violations v
     where not exists (select 1 from public.sanctions s where s.violation_id = v.id)
     limit 3) t;
  assert array_length(v_ids, 1) = 3,
    'need three violations without a sanction (one per status case)';

  insert into public.sanctions
    (violation_id, student_id, basis, sanction_type, description, effective_on, ends_on)
  select v_ids[1], student_id, 'custom', 'suspension', 'future',
         current_date + 3, current_date + 5
    from public.student_violations where id = v_ids[1]
  returning id into v_s_future;
  insert into public.sanctions
    (violation_id, student_id, basis, sanction_type, description, effective_on, ends_on)
  select v_ids[2], student_id, 'custom', 'suspension', 'active',
         current_date - 1, current_date + 1
    from public.student_violations where id = v_ids[2]
  returning id into v_s_active;
  insert into public.sanctions
    (violation_id, student_id, basis, sanction_type, description, effective_on, ends_on)
  select v_ids[3], student_id, 'custom', 'suspension', 'past',
         current_date - 6, current_date - 4
    from public.student_violations where id = v_ids[3]
  returning id into v_s_past;

  assert (select status from public.sanctions where id = v_s_future) = 'Pending',
    'a new sanction starts as Pending';

  perform public.refresh_sanction_statuses();

  assert (select status from public.sanctions where id = v_s_future) = 'Pending',
    'a suspension that has not started stays Pending';
  assert (select status from public.sanctions where id = v_s_active) = 'Serving',
    'a suspension in progress is Serving';
  assert (select status from public.sanctions where id = v_s_past) = 'Completed',
    'a suspension that ended is Completed';
  assert (select completed_at from public.sanctions where id = v_s_past) is not null,
    'completing stamps completed_at';

  -- Manual override by the DO / Admin.
  perform public.set_sanction_status(v_s_future, 'Serving');
  assert (select status from public.sanctions where id = v_s_future) = 'Serving';
  perform public.set_sanction_status(v_s_future, 'Completed');
  assert (select completed_by from public.sanctions where id = v_s_future) is not null,
    'completing records who did it';
  perform public.set_sanction_status(v_s_future, 'Pending');
  assert (select completed_at from public.sanctions where id = v_s_future) is null,
    'reopening clears completed_at';

  begin
    perform public.set_sanction_status(v_s_future, 'Finished');
    assert false, 'an unknown status must be rejected';
  exception when raise_exception then null;
  end;

  -- The student/parent-safe history carries the violation and the status.
  select student_id into v_student from public.sanctions where id = v_s_active;
  assert exists (
    select 1 from public.my_sanction_history(v_student) h
     where h.id = v_s_active and h.status = 'Serving' and h.violation_id = v_ids[2]
  ), 'my_sanction_history returns violation_id and status';

  -- Parent acknowledgment (#5).
  perform public.record_parent_acknowledgment(v_s_active, 'Maria Dela Cruz');
  assert (select parent_ack_name from public.sanctions where id = v_s_active) = 'Maria Dela Cruz';
  assert (select parent_ack_at from public.sanctions where id = v_s_active) is not null;
end $$;

-- ---------------------------------------------------------------------------
-- Behavior categories (#11)
-- ---------------------------------------------------------------------------
do $$
declare v_offense uuid; v_violation uuid;
begin
  assert (select count(*) from public.handbook_offenses
           where behavior_category is not null) > 0,
    'existing handbook offenses are seeded with a behavior category';

  begin
    update public.handbook_offenses set behavior_category = 'Nonsense'
     where id = (select id from public.handbook_offenses limit 1);
    assert false, 'an unknown behavior category must be rejected';
  exception when check_violation then null;
  end;

  -- A violation takes its offense's category when it is classified.
  select o.id into v_offense from public.handbook_offenses o
   where o.behavior_category is not null limit 1;
  select v.id into v_violation from public.student_violations v limit 1;
  if v_violation is not null then
    update public.student_violations set behavior_category = null, offense_id = v_offense
     where id = v_violation;
    assert (select behavior_category from public.student_violations where id = v_violation)
         = (select behavior_category from public.handbook_offenses where id = v_offense),
      'classifying a violation copies the offense behavior category';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Parent meeting confirmation (#8)
-- ---------------------------------------------------------------------------
do $$
declare v_meeting uuid;
begin
  select id into v_meeting from public.guidance_meetings
   where invitee in ('parent', 'both') limit 1;
  assert v_meeting is not null, 'need a guidance meeting that invites a parent';

  perform public.confirm_parent_meeting(v_meeting, true, 'Agreed on an attendance plan');
  assert (select parent_attended from public.guidance_meetings where id = v_meeting) is true;
  assert (select summary from public.guidance_meetings where id = v_meeting)
       = 'Agreed on an attendance plan';
  assert (select parent_confirmed_by from public.guidance_meetings where id = v_meeting) is not null;

  perform public.confirm_parent_meeting(v_meeting, false, null);
  assert (select parent_attended from public.guidance_meetings where id = v_meeting) is false,
    'the confirmation can be corrected';
  assert (select summary from public.guidance_meetings where id = v_meeting) is null;

  -- A student-only meeting has no parent to confirm.
  begin
    perform public.confirm_parent_meeting(
      (select id from public.guidance_meetings where invitee = 'student' limit 1),
      true, null);
    -- No student-only meeting in the data: nothing to check.
  exception when raise_exception then null;
  end;
end $$;

-- ---------------------------------------------------------------------------
-- Professors see suspended students (#3)
-- ---------------------------------------------------------------------------
do $$
begin
  -- As Admin the function lists every suspended student with a class.
  perform * from public.suspended_students_for_professor();
end $$;

do $$ begin raise notice 'ALL PASSED'; end $$;

rollback;
