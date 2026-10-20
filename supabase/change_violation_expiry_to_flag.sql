-- 72-hour expiry now FLAGS instead of archiving, skips weekends, and alerts.
--
--   * A Pending case (waiting for the Discipline Officer) older than 72
--     WEEKDAY hours - Saturday and Sunday (Asia/Manila) do not count - gets
--     `expired_at` set and stays in the active queue. Nothing is archived.
--   * 12 hours before that (60 weekday hours) the DO gets a "due soon" alert.
--   * Both alerts are rows in `notifications` with `urgent = true`, sent once
--     per case (tracked by expiry_warned_at / expiry_notified_at).
--
-- Cases with Guidance (Under_Investigation) are not expired: they are
-- waiting on the counselor, not the DO. Previously archived rows are left
-- as they are. No holiday table in this version.
--
-- Run in Supabase SQL Editor after add_violation_72h_expiry.sql and
-- add_notifications_schema.sql. Idempotent.

alter table public.student_violations
  add column if not exists expiry_warned_at timestamptz,
  add column if not exists expiry_notified_at timestamptz;

alter table public.notifications
  add column if not exists urgent boolean not null default false;

-- Hours between two instants that fall on Monday-Friday (Asia/Manila).
create or replace function public.weekday_hours_between(
  p_from timestamptz,
  p_to timestamptz
)
returns numeric
language sql
stable
as $$
  with bounds as (
    select (p_from at time zone 'Asia/Manila') as f,
           (p_to   at time zone 'Asia/Manila') as t
  ),
  days as (
    select d::timestamp as day_start
      from bounds,
           generate_series(date_trunc('day', f), date_trunc('day', t), interval '1 day') d
     where p_to > p_from
       and extract(isodow from d) < 6
  )
  select coalesce(sum(
    greatest(0, extract(epoch from (
      least((select t from bounds), day_start + interval '1 day')
      - greatest((select f from bounds), day_start)
    )) / 3600.0)
  ), 0)::numeric
  from days;
$$;

create or replace function public.expire_stale_violations()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  v_count int := 0;
begin
  for r in
    select id, student_id
      from public.student_violations
     where archived_at is null
       and expired_at is null
       and status = 'Pending'
       and public.weekday_hours_between(coalesce(restored_at, created_at), now()) >= 72
     for update skip locked
  loop
    update public.student_violations
       set expired_at = now(), expiry_notified_at = now()
     where id = r.id;
    v_count := v_count + 1;

    begin
      insert into public.notifications (target_role, title, message, urgent)
      values (
        'Discipline_Officer'::app_role,
        'URGENT: violation report expired',
        public.sms_student_name(r.student_id)
          || '''s report has been waiting 72 hours for action. Review it now.',
        true
      );
    exception when others then
      raise warning 'expire_stale_violations notify failed: %', sqlerrm;
    end;
  end loop;
  return v_count;
end;
$$;

revoke all on function public.expire_stale_violations() from public;
grant execute on function public.expire_stale_violations() to anon, authenticated;

create or replace function public.warn_expiring_violations()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  v_count int := 0;
begin
  for r in
    select id, student_id
      from public.student_violations
     where archived_at is null
       and expired_at is null
       and expiry_warned_at is null
       and status = 'Pending'
       and public.weekday_hours_between(coalesce(restored_at, created_at), now()) >= 60
     for update skip locked
  loop
    update public.student_violations set expiry_warned_at = now() where id = r.id;
    v_count := v_count + 1;

    begin
      insert into public.notifications (target_role, title, message, urgent)
      values (
        'Discipline_Officer'::app_role,
        'Violation report expires in 12 hours',
        public.sms_student_name(r.student_id)
          || '''s report will pass 72 hours soon. Classify and act on it.',
        true
      );
    exception when others then
      raise warning 'warn_expiring_violations notify failed: %', sqlerrm;
    end;
  end loop;
  return v_count;
end;
$$;

revoke all on function public.warn_expiring_violations() from public;
grant execute on function public.warn_expiring_violations() to anon, authenticated;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid) from cron.job
     where jobname in ('expire-stale-violations', 'warn-expiring-violations');
    perform cron.schedule('expire-stale-violations', '0 * * * *',
                          'select public.expire_stale_violations()');
    perform cron.schedule('warn-expiring-violations', '5 * * * *',
                          'select public.warn_expiring_violations()');
  end if;
end $$;
