-- 72-hour expiry for open violations + archive management.
--
-- A violation still Pending / Under_Investigation 72 hours after it was
-- filed (or after it was last restored) is moved into the archive and
-- flagged `expired_at`, instead of sitting in the queue forever. Nothing in
-- the archive is deleted automatically any more (the old 7-day lazy purge in
-- DisciplineRepository was removed): the Student Affairs officer can
-- Restore, Validate, Modify or permanently Delete each archived report.
--
-- `restored_at` restarts the 72-hour clock when an officer restores a
-- report, otherwise a restored (old) report would be re-expired on the next
-- run.
--
-- expire_stale_violations() is called hourly by pg_cron AND on every
-- dashboard load by the app, so expiry still happens if pg_cron is off.
--
-- Run in Supabase SQL Editor after add_violation_archive_schema.sql.
-- Idempotent.

alter table public.student_violations
  add column if not exists expired_at timestamptz,
  add column if not exists restored_at timestamptz;

create or replace function public.expire_stale_violations()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count int;
begin
  update public.student_violations
     set archived_at = now(),
         expired_at = now()
   where archived_at is null
     and status in ('Pending', 'Under_Investigation')
     and coalesce(restored_at, created_at) < now() - interval '72 hours';
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke all on function public.expire_stale_violations() from public;
grant execute on function public.expire_stale_violations() to anon, authenticated;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid) from cron.job where jobname = 'expire-stale-violations';
    perform cron.schedule('expire-stale-violations', '0 * * * *',
                          'select public.expire_stale_violations()');
  end if;
end $$;
