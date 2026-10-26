-- Assertions for add_concern_reports.sql. Run in the Supabase SQL Editor on a
-- DEV project as an Admin session (needs current_user_role() to resolve).
-- Rolled back at the end. Run it once BEFORE the migration (fails at the first
-- assertion) and once AFTER (prints "ALL PASSED").

begin;

do $$
declare
  v_student uuid; v_other uuid; v_id uuid; v_legacy uuid; v_failed boolean;
begin
  select id into v_student from public.students limit 1;
  select id into v_other from public.students where id <> v_student limit 1;
  assert v_other is not null, 'need a second student';

  -- Blank details are refused.
  v_failed := false;
  begin
    perform public.submit_concern_report(v_student, 'bullying', '   ', false);
  exception when others then
    v_failed := sqlerrm like '%Please describe your concern.%';
  end;
  assert v_failed, 'blank details must raise "Please describe your concern."';

  -- A normal report is saved Pending / Normal and listed for the reporter.
  v_id := public.submit_concern_report(v_student, 'attendance', 'Seatmate skips class.', false);
  assert (select status from public.concern_reports where id = v_id) = 'Pending';
  assert (select urgency from public.concern_reports where id = v_id) = 'Normal';
  assert (select student_id from public.concern_reports where id = v_id) = v_student;
  assert exists (select 1 from public.my_concern_reports(v_student) m where m.id = v_id),
    'reporter sees the report in my_concern_reports';

  -- Safety / bullying are never routine.
  v_id := public.submit_concern_report(v_student, 'safety', 'Strangers near the gate.', false);
  assert (select urgency from public.concern_reports where id = v_id) = 'Urgent',
    'a safety concern is Urgent';

  -- The Discipline Officer is told.
  assert exists (
    select 1 from public.notifications
     where target_role = 'Discipline_Officer'::app_role
       and title in ('New concern report', 'Urgent concern report')
       and created_at >= now() - interval '1 minute'),
    'DO notified of a new concern report';

  -- Legacy classmate referral: migrated under the reporter, same id,
  -- the classmate kept as about_student_id. (Re-running the migration's
  -- INSERT must not duplicate it.)
  insert into public.student_referrals
    (student_id, referred_by, is_self, concern, details)
  values (v_other, v_student, false, 'bullying', 'Worried about my classmate.')
  returning id into v_legacy;
  insert into public.concern_reports
    (id, student_id, about_student_id, concern, details, urgency, status, created_at)
  select r.id, r.referred_by, case when r.is_self then null else r.student_id end,
         r.concern, r.details, r.urgency, r.status, r.created_at
    from public.student_referrals r
   where r.id = v_legacy
  on conflict (id) do nothing;
  assert (select student_id from public.concern_reports where id = v_legacy) = v_student;
  assert (select about_student_id from public.concern_reports where id = v_legacy) = v_other;

  raise notice 'ALL PASSED';
end $$;

rollback;
