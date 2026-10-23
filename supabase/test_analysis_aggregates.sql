-- Assertions for add_analysis_aggregates.sql. Run in the Supabase SQL Editor on a
-- DEV project as an Admin session (like the other test_*.sql files it needs a
-- session whose current_user_role() resolves). Rolled back at the end. Run it
-- once BEFORE the migration (it fails at the first assertion) and once AFTER
-- (it prints "ALL PASSED").

begin;

do $$
declare
  v_student uuid; v_reporter uuid; v_offense uuid; v_vio uuid;
  v_cols text[];
begin
  -- The aggregate function exists and exposes only counts and a last date.
  assert to_regprocedure('public.analysis_violation_counts(timestamptz, uuid, boolean)') is not null,
    'analysis_violation_counts must exist';
  select proargnames into v_cols
    from pg_proc where proname = 'analysis_violation_counts';
  assert not exists (
    select 1 from unnest(v_cols) as n
     where n ilike '%description%' or n ilike '%notes%' or n ilike '%penalty%'
        or n ilike '%sanction%' or n ilike '%reporter%'),
    'the aggregates must not carry details';

  -- A resolved violation shows up as one counted row for its category.
  select id into v_student from public.students limit 1;
  select id into v_reporter from public.profiles limit 1;
  select id into v_offense from public.handbook_offenses limit 1;
  v_vio := public.submit_incident_report(v_student, now() - interval '1 hour', 'fight', '{}', v_reporter);
  perform public.classify_violation(v_vio, array[v_offense]);
  perform public.record_sanction(v_vio, 'custom', null, 'warning', 'Warned.',
                                 current_date, null, false, null);
  assert exists (
    select 1 from public.analysis_violation_counts(now() - interval '1 day', v_student, true)
     where violation_count >= 1),
    'a sanctioned violation is counted';

  -- Guidance no longer reads violation rows directly.
  assert not exists (
    select 1 from pg_policies
     where tablename = 'student_violations'
       and cmd in ('SELECT', 'ALL')
       and roles::text not ilike '%anon%'
       and (qual ilike '%Guidance_Counselor%')),
    'Guidance must not read student_violations directly';

  raise notice 'ALL PASSED';
end $$;

rollback;
