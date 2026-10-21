-- Assertions for change_violation_expiry_to_flag.sql. Run in the Supabase SQL
-- Editor on a DEV project. Rolled back at the end.
-- Expected: final NOTICE "ALL PASSED".

begin;

do $$
declare
  v_student uuid; v_reporter uuid; v_id uuid;
  v_notes_before int; v_hours numeric;
begin
  -- Friday 17:00 -> Monday 08:00 Manila = 7h Friday + 8h Monday = 15 weekday hours.
  v_hours := public.weekday_hours_between(
    timestamptz '2026-10-16 17:00+08', timestamptz '2026-10-19 08:00+08');
  assert v_hours = 15, format('expected 15, got %s', v_hours);

  -- A pure weekend counts for nothing.
  assert public.weekday_hours_between(
    timestamptz '2026-10-17 00:00+08', timestamptz '2026-10-19 00:00+08') = 0,
    'weekend must be 0';

  -- Reversed range is 0.
  assert public.weekday_hours_between(now(), now() - interval '1 day') = 0;

  select id into v_student from public.students limit 1;
  select id into v_reporter from public.profiles limit 1;
  v_id := public.submit_incident_report(v_student, now() - interval '1 hour', 'late', '{}', v_reporter);

  -- Filed Friday 17:00; on Monday 08:00 it is NOT expired (15 weekday hours).
  update public.student_violations
     set created_at = timestamptz '2026-10-16 17:00+08' where id = v_id;
  -- (the function uses now(); assert the pure maths instead of waiting)
  assert public.weekday_hours_between(
    timestamptz '2026-10-16 17:00+08', timestamptz '2026-10-19 08:00+08') < 72;
  -- Wed 17:00 is 7 + 24 + 24 + 17 = 72 weekday hours -> expired.
  assert public.weekday_hours_between(
    timestamptz '2026-10-16 17:00+08', timestamptz '2026-10-21 17:00+08') = 72 + 0;

  -- A long-overdue Pending case is flagged, not archived, and notifies once.
  update public.student_violations
     set created_at = now() - interval '30 days' where id = v_id;
  select count(*) into v_notes_before from public.notifications where urgent;
  perform public.expire_stale_violations();
  assert (select expired_at is not null and archived_at is null
            from public.student_violations where id = v_id),
    'expired flagged but not archived';
  perform public.expire_stale_violations();
  assert (select count(*) from public.notifications where urgent) = v_notes_before + 1,
    'exactly one urgent notification per case';

  raise notice 'ALL PASSED';
end $$;

rollback;
