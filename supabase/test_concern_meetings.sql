-- Assertions for add_concern_meetings.sql. Run in the Supabase SQL Editor on a
-- DEV project as an Admin session, AFTER add_concern_reports.sql,
-- add_endorsement_meetings.sql, add_parent_credential_access.sql,
-- add_meeting_completion_log.sql, add_concern_investigations.sql and
-- add_concern_meetings.sql. Needs a student with a linked parent. Rolled back at
-- the end. Run once BEFORE the migration (fails) and once AFTER (prints
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

do $$
declare
  v_student uuid; v_parent uuid; v_c1 uuid; v_c2 uuid;
  v_m1 uuid; v_m2 uuid; v_m3 uuid;
  v_gc_before int; v_log_before int; v_failed boolean; v_file jsonb;
  v_t1 timestamptz := now() + interval '3 days';
  v_claims text := current_setting('request.jwt.claims', true);
  v_sub text := current_setting('request.jwt.claim.sub', true);
begin
  select l.student_id, l.parent_id into v_student, v_parent
    from public.parent_student_links l limit 1;
  assert v_student is not null, 'need a student with a linked parent';

  insert into public.concern_reports (student_id, concern, details)
  values (v_student, 'bullying', 'Someone keeps taking my lunch money')
  returning id into v_c1;

  select count(*) into v_gc_before from public.notifications
   where target_role::text = 'Guidance_Counselor';
  select count(*) into v_log_before from public.counseling_archive_logs;

  -- (a) The DO schedules a meeting with student and parent.
  v_m1 := public.schedule_concern_meeting(v_c1, v_t1, 'Student Affairs Office', 'both');
  assert (select concern_id from public.guidance_meetings where id = v_m1) = v_c1,
    'the meeting belongs to the concern';
  assert (select student_id from public.guidance_meetings where id = v_m1) = v_student,
    'the meeting is with the student who filed it';
  assert (select status from public.guidance_meetings where id = v_m1) = 'Proposed';
  assert (select escalation_report_id from public.guidance_meetings where id = v_m1) is null
     and (select investigation_id from public.guidance_meetings where id = v_m1) is null,
    'a concern meeting has no endorsement or investigation behind it';
  assert (select status from public.concern_reports where id = v_c1) = 'In_Progress',
    'scheduling moves a pending concern to In_Progress';
  assert (select count(*) from public.notifications
           where target_role::text = 'Student' and user_id = v_student
             and title = 'Meeting scheduled') >= 1, 'the student is invited';
  assert (select count(*) from public.notifications
           where target_role::text = 'Parent' and user_id = v_parent
             and title = 'Meeting scheduled') >= 1, 'the parent is invited';

  -- (b) A new invitation replaces the live one.
  v_m2 := public.schedule_concern_meeting(v_c1, v_t1 + interval '1 day', null, 'student');
  assert (select status from public.guidance_meetings where id = v_m1) = 'Cancelled',
    'the earlier invitation is cancelled';
  assert (select status from public.guidance_meetings where id = v_m2) = 'Proposed';

  -- (c) Refusals.
  v_failed := false;
  begin perform public.schedule_concern_meeting(v_c1, now() - interval '1 hour', null, 'both');
  exception when others then v_failed := sqlerrm like '%future%'; end;
  assert v_failed, 'a past time is refused';

  v_failed := false;
  begin perform public.schedule_concern_meeting(v_c1, v_t1, null, 'teacher');
  exception when others then v_failed := sqlerrm like '%Invitee%'; end;
  assert v_failed, 'an unknown invitee is refused';

  insert into public.concern_reports (student_id, concern, details, status)
  values (v_student, 'safety', 'x', 'Closed') returning id into v_c2;
  v_failed := false;
  begin perform public.schedule_concern_meeting(v_c2, v_t1, null, 'both');
  exception when others then v_failed := sqlerrm like '%closed%'; end;
  assert v_failed, 'a closed concern cannot get a meeting';

  -- (d) The case file lists the concern's own meetings.
  v_file := public.concern_case_file(v_c1);
  assert jsonb_array_length(v_file->'meetings') = 2, 'both meetings are in the case file';

  -- (e) The parent replies (credential path); only the DO is told.
  v_m3 := public.schedule_concern_meeting(v_c1, v_t1 + interval '2 days', null, 'parent');
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  perform public.respond_to_meeting(v_m3, true, 'We will be there', v_parent);
  perform set_config('request.jwt.claims', v_claims, true);
  perform set_config('request.jwt.claim.sub', v_sub, true);
  assert (select status from public.guidance_meetings where id = v_m3) = 'Confirmed';

  -- (f) The DO records the outcome; nothing reaches Guidance or its archive.
  perform public.set_meeting_outcome(v_m3, 'Completed');
  assert (select status from public.guidance_meetings where id = v_m3) = 'Completed';
  assert (select count(*) from public.counseling_archive_logs) = v_log_before,
    'a DO-only meeting is not written to the counselor archive';
  assert (select count(*) from public.notifications
           where target_role::text = 'Guidance_Counselor') = v_gc_before,
    'no Guidance Counselor notification for a DO-only meeting';

  -- (g) Only the DO or Admin can schedule.
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  v_failed := false;
  begin perform public.schedule_concern_meeting(v_c1, v_t1, null, 'both');
  exception when others then v_failed := sqlstate = '42501'; end;
  assert v_failed, 'an anonymous caller cannot schedule';

  raise notice 'ALL PASSED';
end $$;

rollback;
