-- No more automatic tap-out: a student who does not tap out is shown as
-- "Did not tap out".
--
-- The 6:30 PM job used to insert a fake `out` tap for every student still
-- tapped in, and the parent got an SMS saying the student "was automatically
-- tapped out". That was misleading: it looked like the student left at 6:30.
-- Now:
--
--   * missed_tap_outs records (student, school day) for a student whose last
--     tap of the day is still `in`. Nothing is added to rfid_tap_events.
--   * The same 6:30 PM job queues the SMS "<name> did not tap out today.",
--     once per student per school day, and one staff notification.
--   * Old automatic tap-outs (auto_generated) become missed_tap_outs rows and
--     the fabricated taps are deleted, so history reads "Did not tap out".
--   * auto_tap_out_open_students and its cron job are removed.
--
-- A school day runs until 6:30 PM Manila (see record_rfid_tap), so the job
-- only reports once that moment has passed.
--
-- Run in Supabase SQL Editor after add_sms_alerts_schema.sql (and
-- fix_late_replay_after_auto_tap_out.sql if it was run). Idempotent.
-- test_late_replay_after_auto_tap_out.sql calls the removed function: it no
-- longer applies.

-- ---------------------------------------------------------------------------
-- 1. The record
-- ---------------------------------------------------------------------------

create table if not exists public.missed_tap_outs (
  student_id uuid not null references public.students(id) on delete cascade,
  school_day date not null,
  created_at timestamptz not null default now(),
  primary key (student_id, school_day)
);

create index if not exists missed_tap_outs_day_idx
  on public.missed_tap_outs (school_day desc);

alter table public.missed_tap_outs enable row level security;

-- Staff read everything; a student their own days; a parent their child's.
drop policy if exists "missed_tap_outs_staff_select" on public.missed_tap_outs;
create policy "missed_tap_outs_staff_select" on public.missed_tap_outs
  for select to authenticated
  using (coalesce(current_user_role() not in ('Student'::app_role, 'Parent'::app_role), false));

drop policy if exists "missed_tap_outs_student_select" on public.missed_tap_outs;
create policy "missed_tap_outs_student_select" on public.missed_tap_outs
  for select to authenticated
  using (student_id = auth.uid());

drop policy if exists "missed_tap_outs_parent_select" on public.missed_tap_outs;
create policy "missed_tap_outs_parent_select" on public.missed_tap_outs
  for select to authenticated
  using (exists (
    select 1 from public.parent_student_links l
     where l.student_id = missed_tap_outs.student_id and l.parent_id = auth.uid()));

-- Demo mode: static demo accounts run under the anon key (same tradeoff as
-- add_sms_alerts_schema.sql). Tighten before production.
drop policy if exists "missed_tap_outs_anon_select" on public.missed_tap_outs;
create policy "missed_tap_outs_anon_select" on public.missed_tap_outs
  for select to anon using (true);

-- ---------------------------------------------------------------------------
-- 2. The old automatic tap-outs become "did not tap out"
-- ---------------------------------------------------------------------------

insert into public.missed_tap_outs (student_id, school_day, created_at)
select e.student_id,
       ((e.tapped_at at time zone 'Asia/Manila') + interval '5 hours 30 minutes')::date,
       e.tapped_at
  from public.rfid_tap_events e
 where e.auto_generated and e.student_id is not null
on conflict (student_id, school_day) do nothing;

delete from public.rfid_tap_events where auto_generated;

-- ---------------------------------------------------------------------------
-- 3. The nightly job: record the miss and tell the parent
-- ---------------------------------------------------------------------------

drop function if exists public.auto_tap_out_open_students(timestamptz);

-- Same school-day arithmetic as the old job. Returns the number of students
-- newly recorded. Re-running is harmless: the primary key and the SMS queue's
-- (kind, related_id) key both ignore a repeat.
create or replace function public.record_missed_tap_outs(
  p_run_at timestamptz default now()
)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  s public.sms_settings;
  v_school_day date;
  v_cutoff timestamptz;
  v_count int := 0;
  v_names text[] := '{}';
  v_listed text;
  v_inserted int;
  r record;
begin
  v_school_day :=
    (((p_run_at - interval '1 minute') at time zone 'Asia/Manila')
      + interval '5 hours 30 minutes')::date;
  v_cutoff := (v_school_day + time '18:29:59') at time zone 'Asia/Manila';

  -- The school day is not over yet (e.g. a manual run at noon).
  if v_cutoff > p_run_at then
    return 0;
  end if;

  select * into s from public.sms_settings where id;

  for r in
    select distinct on (e.student_id) e.student_id, e.tap_direction
      from public.rfid_tap_events e
     where e.student_id is not null
       and ((e.tapped_at at time zone 'Asia/Manila') + interval '5 hours 30 minutes')::date
           = v_school_day
     order by e.student_id, e.tapped_at desc
  loop
    if r.tap_direction = 'in' then
      insert into public.missed_tap_outs (student_id, school_day)
      values (r.student_id, v_school_day)
      on conflict (student_id, school_day) do nothing;
      get diagnostics v_inserted = row_count;

      if v_inserted > 0 then
        v_count := v_count + 1;
        if array_length(v_names, 1) is null or array_length(v_names, 1) < 5 then
          v_names := v_names || public.sms_student_name(r.student_id);
        end if;

        if coalesce(s.tap_alerts_enabled, true) then
          begin
            perform public.queue_sms(
              'no_tap_out', r.student_id,
              md5(r.student_id::text || '|no_tap_out|' || v_school_day::text)::uuid,
              coalesce(s.school_name, 'STI Baliuag') || ': '
                || public.sms_student_name(r.student_id)
                || ' did not tap out today.');
          exception when others then
            raise warning 'record_missed_tap_outs sms failed: %', sqlerrm;
          end;
        end if;
      end if;
    end if;
  end loop;

  if v_count > 0 then
    v_listed := array_to_string(v_names, ', ')
      || case when v_count > array_length(v_names, 1)
              then ' and ' || (v_count - array_length(v_names, 1)) || ' more'
              else '' end;

    insert into public.notifications (target_role, title, message)
    select t.target, 'Students did not tap out',
           v_count || ' student(s) did not tap out today: ' || v_listed || '.'
      from (values ('Guidance_Counselor'::app_role), ('Discipline_Officer'::app_role)) as t(target);
  end if;

  return v_count;
end;
$$;

revoke all on function public.record_missed_tap_outs(timestamptz)
  from public, anon, authenticated;
grant execute on function public.record_missed_tap_outs(timestamptz) to service_role;

-- ---------------------------------------------------------------------------
-- 4. Schedule (pg_cron runs in UTC; 6:30 PM Manila = 10:30 UTC)
-- ---------------------------------------------------------------------------

do $$
begin
  if exists (select 1 from cron.job where jobname = 'auto-tap-out-open-students') then
    perform cron.unschedule('auto-tap-out-open-students');
  end if;
end $$;

select cron.schedule(
  'missed-tap-outs',
  '30 10 * * *',
  $$select public.record_missed_tap_outs();$$
);

-- ---------------------------------------------------------------------------
-- 5. A late real tap-out replaces the "did not tap out" record
-- ---------------------------------------------------------------------------
-- When a kiosk was offline, the 4:00 PM tap-out replays after the 6:30 PM job
-- already recorded the miss (and texted the parent). The real tap-out is
-- inserted normally, so the miss is removed here: the day then reads
-- "Tapped out 4:00 PM" everywhere.

create or replace function public.trg_clear_missed_tap_out()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.tap_direction = 'out' and new.student_id is not null then
    delete from public.missed_tap_outs
     where student_id = new.student_id
       and school_day =
         ((new.tapped_at at time zone 'Asia/Manila') + interval '5 hours 30 minutes')::date;
  end if;
  return new;
end;
$$;

drop trigger if exists rfid_tap_events_clear_missed on public.rfid_tap_events;
create trigger rfid_tap_events_clear_missed
  after insert on public.rfid_tap_events
  for each row execute function public.trg_clear_missed_tap_out();
