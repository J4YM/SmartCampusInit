-- PhilSMS parent alerts: tap-in / tap-out SMS, an end-of-day auto tap-out for
-- students who never tapped out, and Parent Intervention SMS (manual, from
-- Guidance / Student Affairs, or automatic once a student's violations cross
-- a threshold).
--
-- Flow:
--   1. A trigger (rfid_tap_events / parent_interventions) writes one row to
--      public.sms_outbox. The outbox IS the send log.
--   2. An insert into sms_outbox pings the `send-sms` Edge Function through
--      pg_net (one ping per statement, not per row).
--   3. The function claims pending rows, calls PhilSMS, and marks each row
--      sent / failed. A sweeper cron job re-pings every 5 minutes so failed
--      rows are retried (up to 5 attempts).
--   Nothing here blocks the tap or the violation write: every trigger body
--   swallows its own errors, and the SMS call is asynchronous.
--
-- "At most one SMS per tap direction per day" needs no extra logic:
-- record_rfid_tap (add_rfid_tap_daily_limit.sql) already allows exactly one
-- `in` and one `out` per school day, so the first tap-in and the last
-- tap-out are the only two rows there are.
--
-- Run in Supabase SQL Editor, AFTER:
--   add_rfid_reader_network_schema.sql, add_rfid_tap_daily_limit.sql,
--   fix_rfid_school_day_timezone.sql, add_notifications_schema.sql,
--   add_parent_interventions_schema.sql, add_id_card_student_columns.sql.
-- Idempotent: safe to re-run. Each prerequisite file above must already have
-- been run — e.g. a missing add_parent_interventions_schema.sql fails section
-- 7 with `relation "public.parent_interventions" does not exist`, and the
-- SQL Editor then rolls the whole script back.
--
-- ONE-TIME SETUP (not in this file, because they are secrets):
--   a. Deploy the function:   supabase functions deploy send-sms --no-verify-jwt
--   b. Set its secrets:       supabase secrets set PHILSMS_API_TOKEN=... \
--                               PHILSMS_SENDER_ID=... SMS_WEBHOOK_SECRET=<random>
--   c. Point the database at it (run once, with the same random secret):
--        update public.sms_config
--           set function_url  = 'https://<project-ref>.supabase.co/functions/v1/send-sms',
--               shared_secret = '<same SMS_WEBHOOK_SECRET>';

-- ---------------------------------------------------------------------------
-- 0. Extensions
-- ---------------------------------------------------------------------------
create extension if not exists pg_net with schema extensions;
create extension if not exists pg_cron with schema pg_catalog;

-- ---------------------------------------------------------------------------
-- 1. Tables
-- ---------------------------------------------------------------------------

-- Single-row switchboard + the auto-intervention rule. Editable from the
-- Table Editor until an Admin screen exists.
create table if not exists public.sms_settings (
  id boolean primary key default true check (id),
  school_name text not null default 'STI Baliuag',
  tap_alerts_enabled boolean not null default true,
  intervention_alerts_enabled boolean not null default true,
  auto_intervention_enabled boolean not null default true,
  -- Auto-request once a student has this many non-archived violations...
  auto_intervention_violation_count int not null default 3
    check (auto_intervention_violation_count > 0),
  -- ...within this many days...
  auto_intervention_window_days int not null default 30
    check (auto_intervention_window_days > 0),
  -- ...or immediately on any non-Minor (Major_A..D) violation.
  auto_intervention_on_major boolean not null default true
);

insert into public.sms_settings (id) values (true) on conflict (id) do nothing;

-- Where the database should call, and the shared secret it presents. Kept in
-- a table with RLS on and NO policies, so only security-definer functions
-- (and the postgres role) can read it — never the anon/authenticated API.
create table if not exists public.sms_config (
  id boolean primary key default true check (id),
  function_url text,
  shared_secret text
);

insert into public.sms_config (id) values (true) on conflict (id) do nothing;

create table if not exists public.sms_outbox (
  id uuid primary key default gen_random_uuid(),
  -- 'tap_in' | 'tap_out' | 'auto_tap_out' | 'intervention'
  kind text not null,
  student_id uuid references public.students(id) on delete set null,
  -- The source row (tap event / intervention) — with `kind`, makes queueing
  -- idempotent: the same event can never produce two SMS.
  related_id uuid not null,
  -- 639XXXXXXXXX, or null when skipped.
  recipient text,
  message text not null,
  -- 'pending' | 'sending' | 'sent' | 'failed' | 'skipped'
  status text not null default 'pending',
  attempts int not null default 0,
  error text,
  provider_response jsonb,
  created_at timestamptz not null default now(),
  last_attempt_at timestamptz,
  sent_at timestamptz,
  unique (kind, related_id)
);

create index if not exists sms_outbox_status_idx
  on public.sms_outbox (status, created_at);
create index if not exists sms_outbox_student_idx
  on public.sms_outbox (student_id, created_at desc);

alter table public.rfid_tap_events
  add column if not exists auto_generated boolean not null default false;

-- ---------------------------------------------------------------------------
-- 2. RLS — staff can read the log; nobody writes it from the client.
-- ---------------------------------------------------------------------------
alter table public.sms_settings enable row level security;
alter table public.sms_config enable row level security;
alter table public.sms_outbox enable row level security;

drop policy if exists "sms_outbox_staff_select" on public.sms_outbox;
create policy "sms_outbox_staff_select"
  on public.sms_outbox
  for select
  to authenticated
  using (
    current_user_role() in
      ('Admin'::app_role, 'Guidance_Counselor'::app_role,
       'Discipline_Officer'::app_role)
  );

drop policy if exists "sms_settings_admin_all" on public.sms_settings;
create policy "sms_settings_admin_all"
  on public.sms_settings
  for all
  to authenticated
  using (current_user_role() = 'Admin'::app_role)
  with check (current_user_role() = 'Admin'::app_role);

-- ---------------------------------------------------------------------------
-- 3. Helpers
-- ---------------------------------------------------------------------------

-- 09171234567 / +63 917 123 4567 / 9171234567 -> 639171234567; anything that
-- is not a PH mobile number -> null (the row is then 'skipped', not sent).
create or replace function public.normalize_ph_mobile(p_raw text)
returns text
language sql
immutable
as $$
  select case
    when d ~ '^639[0-9]{9}$' then d
    when d ~ '^09[0-9]{9}$' then '63' || substr(d, 2)
    when d ~ '^9[0-9]{9}$' then '63' || d
    else null
  end
  from (select regexp_replace(coalesce(p_raw, ''), '[^0-9]', '', 'g') as d) t;
$$;

create or replace function public.sms_student_name(p_student_id uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(nullif(btrim(coalesce(p.first_name, '') || ' ' || coalesce(p.last_name, '')), ''), 'Your child')
  from public.profiles p
  where p.id = p_student_id;
$$;

-- Plain-text auto message for a conduct-based intervention. The Flutter
-- dialog builds the same default text client-side so staff can edit it
-- before sending.
create or replace function public.build_conduct_intervention_message(
  p_name text,
  p_violation_count int,
  p_is_major boolean,
  p_window_days int
)
returns text
language sql
immutable
as $$
  select case
    when p_is_major then
      p_name || ' was reported for a major conduct violation. '
      || 'Please visit the Guidance Office to discuss. Thank you.'
    else
      p_name || ' has ' || p_violation_count || ' conduct violations in the last '
      || p_window_days || ' days. Please visit the Guidance Office to discuss. Thank you.'
  end;
$$;

-- Queue one SMS to the student's guardian. Resolves + validates the number
-- here so a bad/missing number is logged as 'skipped' with a reason instead
-- of failing at the provider.
create or replace function public.queue_sms(
  p_kind text,
  p_student_id uuid,
  p_related_id uuid,
  p_message text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_raw text;
  v_to text;
begin
  select s.guardian_contact_no into v_raw
    from public.students s
    where s.id = p_student_id;

  v_to := public.normalize_ph_mobile(v_raw);

  insert into public.sms_outbox
    (kind, student_id, related_id, recipient, message, status, error)
  values (
    p_kind, p_student_id, p_related_id, v_to, p_message,
    case when v_to is null then 'skipped' else 'pending' end,
    case
      when v_to is not null then null
      when coalesce(btrim(v_raw), '') = '' then 'No guardian contact number on file'
      else 'Guardian contact number is not a valid PH mobile number: ' || v_raw
    end
  )
  on conflict (kind, related_id) do nothing;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Dispatcher ping (database -> Edge Function)
-- ---------------------------------------------------------------------------
create or replace function public.ping_sms_dispatcher()
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  c public.sms_config;
begin
  select * into c from public.sms_config where id;
  if c.function_url is null or c.shared_secret is null then
    raise warning 'sms_config is not set up; SMS stay pending until it is.';
    return;
  end if;

  perform net.http_post(
    url := c.function_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-sms-secret', c.shared_secret
    ),
    body := '{}'::jsonb,
    -- pg_net's default is 5s; a batch of PhilSMS calls can take about that
    -- long, which logged noisy "Timeout of 5000 ms" rows even though the
    -- function finished its work.
    timeout_milliseconds := 30000
  );
exception when others then
  raise warning 'ping_sms_dispatcher failed: %', sqlerrm;
end;
$$;

-- Statement-level on purpose: the 6:30 PM auto tap-out can queue hundreds of
-- rows in one statement, and the function drains the whole queue per call.
create or replace function public.trg_ping_sms_dispatcher()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if exists (select 1 from new_rows where status = 'pending') then
    perform public.ping_sms_dispatcher();
  end if;
  return null;
end;
$$;

drop trigger if exists sms_outbox_ping on public.sms_outbox;
create trigger sms_outbox_ping
  after insert on public.sms_outbox
  referencing new table as new_rows
  for each statement
  execute function public.trg_ping_sms_dispatcher();

-- Atomically hands the Edge Function a batch of rows to send. `skip locked`
-- lets overlapping invocations (trigger ping + sweeper) split the queue
-- instead of double-sending. A row stuck in 'sending' for 10+ minutes (the
-- function died mid-batch) is reclaimable.
create or replace function public.claim_sms_batch(p_limit int default 20)
returns setof public.sms_outbox
language sql
security definer
set search_path = public
as $$
  update public.sms_outbox o
     set status = 'sending',
         attempts = o.attempts + 1,
         last_attempt_at = now()
   where o.id in (
     select q.id
       from public.sms_outbox q
      where q.attempts < 5
        and (
          q.status in ('pending', 'failed')
          or (q.status = 'sending' and q.last_attempt_at < now() - interval '10 minutes')
        )
      order by q.created_at
      limit p_limit
      for update skip locked
   )
  returning o.*;
$$;

revoke all on function public.claim_sms_batch(int) from public, anon, authenticated;
grant execute on function public.claim_sms_batch(int) to service_role;

-- ---------------------------------------------------------------------------
-- 5. Tap alerts (+ the auto tap-out's SMS: same trigger)
-- ---------------------------------------------------------------------------
create or replace function public.trg_queue_tap_sms()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  s public.sms_settings;
  v_name text;
  v_time text;
  v_kind text;
  v_msg text;
begin
  if new.student_id is null then
    return new;
  end if;

  select * into s from public.sms_settings where id;
  if not coalesce(s.tap_alerts_enabled, true) then
    return new;
  end if;

  v_name := public.sms_student_name(new.student_id);
  v_time := to_char(new.tapped_at at time zone 'Asia/Manila', 'FMHH12:MI AM "on" FMMon FMDD');

  if new.auto_generated then
    v_kind := 'auto_tap_out';
    v_msg := coalesce(s.school_name, 'STI Baliuag') || ': ' || v_name
      || ' did not tap out today and was automatically tapped out at 6:30 PM.';
  elsif new.tap_direction = 'out' then
    v_kind := 'tap_out';
    v_msg := coalesce(s.school_name, 'STI Baliuag') || ': ' || v_name
      || ' tapped OUT at ' || v_time || '.';
  else
    v_kind := 'tap_in';
    v_msg := coalesce(s.school_name, 'STI Baliuag') || ': ' || v_name
      || ' tapped IN at ' || v_time || '.';
  end if;

  perform public.queue_sms(v_kind, new.student_id, new.id, v_msg);
  return new;
exception when others then
  -- Never let an SMS problem fail a tap.
  raise warning 'trg_queue_tap_sms failed: %', sqlerrm;
  return new;
end;
$$;

drop trigger if exists rfid_tap_events_queue_sms on public.rfid_tap_events;
create trigger rfid_tap_events_queue_sms
  after insert on public.rfid_tap_events
  for each row
  execute function public.trg_queue_tap_sms();

-- ---------------------------------------------------------------------------
-- 6. End-of-day auto tap-out
-- ---------------------------------------------------------------------------
-- Run by pg_cron at 6:30 PM Manila time. For every student whose latest tap
-- of the school day is still `in`, inserts an `out` flagged auto_generated.
--
-- tapped_at is 6:29:59 PM, deliberately NOT 6:30:00: record_rfid_tap's school
-- day rolls over at exactly 18:30, so a row stamped 18:30:00 would land in
-- TOMORROW's school day and leave today's `in` unmatched.
--
-- Inserting `out` directly (not via record_rfid_tap) deliberately skips the
-- "wait 1 hour after tapping in" rule — a late tap-in must still be closed.
-- Re-running is harmless: the latest tap is then `out`, so nothing matches.
--
-- Returns the number of students auto-tapped-out.
create or replace function public.auto_tap_out_open_students(
  p_run_at timestamptz default now()
)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_school_day date;
  v_cutoff timestamptz;
  v_count int := 0;
  v_names text[] := '{}';
  v_listed text;
  r record;
begin
  v_school_day :=
    (((p_run_at - interval '1 minute') at time zone 'Asia/Manila')
      + interval '5 hours 30 minutes')::date;
  v_cutoff := (v_school_day + time '18:29:59') at time zone 'Asia/Manila';

  -- Never stamp a tap in the future (e.g. a manual run at noon).
  if v_cutoff > p_run_at then
    return 0;
  end if;

  for r in
    select distinct on (e.student_id)
           e.student_id, e.reader_id, e.rfid_uid, e.tap_direction
      from public.rfid_tap_events e
     where e.student_id is not null
       and ((e.tapped_at at time zone 'Asia/Manila') + interval '5 hours 30 minutes')::date
           = v_school_day
     order by e.student_id, e.tapped_at desc
  loop
    if r.tap_direction = 'in' then
      insert into public.rfid_tap_events
        (reader_id, rfid_uid, student_id, tap_direction, tapped_at, auto_generated)
      values
        (r.reader_id, r.rfid_uid, r.student_id, 'out', v_cutoff, true);

      v_count := v_count + 1;
      if array_length(v_names, 1) is null or array_length(v_names, 1) < 5 then
        v_names := v_names || public.sms_student_name(r.student_id);
      end if;
    end if;
  end loop;

  if v_count > 0 then
    v_listed := array_to_string(v_names, ', ')
      || case when v_count > array_length(v_names, 1)
              then ' and ' || (v_count - array_length(v_names, 1)) || ' more'
              else '' end;

    insert into public.notifications (target_role, title, message)
    select t.target, 'Students not tapped out',
           v_count || ' student(s) did not tap out and were automatically tapped out at 6:30 PM: '
           || v_listed || '.'
      from (values ('Guidance_Counselor'::app_role), ('Discipline_Officer'::app_role)) as t(target);
  end if;

  return v_count;
end;
$$;

revoke all on function public.auto_tap_out_open_students(timestamptz)
  from public, anon, authenticated;
grant execute on function public.auto_tap_out_open_students(timestamptz) to service_role;

-- ---------------------------------------------------------------------------
-- 7. Parent Intervention SMS
-- ---------------------------------------------------------------------------
create or replace function public.trg_queue_intervention_sms()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  s public.sms_settings;
  v_body text;
begin
  select * into s from public.sms_settings where id;
  if not coalesce(s.intervention_alerts_enabled, true) then
    return new;
  end if;

  v_body := coalesce(nullif(btrim(new.message), ''), new.title);
  perform public.queue_sms(
    'intervention', new.student_id, new.id,
    coalesce(s.school_name, 'STI Baliuag') || ' Guidance: ' || v_body
  );
  return new;
exception when others then
  raise warning 'trg_queue_intervention_sms failed: %', sqlerrm;
  return new;
end;
$$;

drop trigger if exists parent_interventions_queue_sms on public.parent_interventions;
create trigger parent_interventions_queue_sms
  after insert on public.parent_interventions
  for each row
  execute function public.trg_queue_intervention_sms();

-- Auto-request: a new violation either is itself Major (any non-Minor
-- category) or pushes the student to the configured count within the window.
-- At most one auto request per student per window, so a 4th, 5th, ...
-- violation does not text the parent again.
create or replace function public.trg_auto_parent_intervention()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  s public.sms_settings;
  v_is_major boolean;
  v_count int;
begin
  select * into s from public.sms_settings where id;
  if not coalesce(s.auto_intervention_enabled, true) then
    return new;
  end if;
  if new.student_id is null or new.archived_at is not null then
    return new;
  end if;

  select (o.category::text <> 'Minor') into v_is_major
    from public.handbook_offenses o
   where o.id = new.offense_id;

  select count(*) into v_count
    from public.student_violations v
   where v.student_id = new.student_id
     and v.archived_at is null
     and v.created_at >= now() - make_interval(days => s.auto_intervention_window_days);

  if not (
    (s.auto_intervention_on_major and coalesce(v_is_major, false))
    or v_count >= s.auto_intervention_violation_count
  ) then
    return new;
  end if;

  if exists (
    select 1
      from public.parent_interventions i
     where i.student_id = new.student_id
       and i.kind = 'conduct'
       and i.sent_by = 'System (auto)'
       and i.created_at >= now() - make_interval(days => s.auto_intervention_window_days)
  ) then
    return new;
  end if;

  insert into public.parent_interventions
    (student_id, title, message, kind, sent_by, action_required)
  values (
    new.student_id,
    'Parent conference requested',
    public.build_conduct_intervention_message(
      public.sms_student_name(new.student_id),
      v_count,
      coalesce(v_is_major, false),
      s.auto_intervention_window_days
    ),
    'conduct',
    'System (auto)',
    true
  );
  return new;
exception when others then
  raise warning 'trg_auto_parent_intervention failed: %', sqlerrm;
  return new;
end;
$$;

drop trigger if exists student_violations_auto_intervention on public.student_violations;
create trigger student_violations_auto_intervention
  after insert on public.student_violations
  for each row
  execute function public.trg_auto_parent_intervention();

-- ---------------------------------------------------------------------------
-- 8. Schedules (pg_cron runs in UTC; Manila is UTC+8, no DST)
-- ---------------------------------------------------------------------------
-- 6:30 PM Manila = 10:30 UTC.
select cron.schedule(
  'auto-tap-out-open-students',
  '30 10 * * *',
  $$select public.auto_tap_out_open_students();$$
);

-- Retry sweeper: re-pings the function every 5 minutes so 'failed' rows
-- (and anything left 'pending' because a ping was lost) are re-attempted.
select cron.schedule(
  'sms-outbox-sweeper',
  '*/5 * * * *',
  $$select public.ping_sms_dispatcher()
    where exists (
      select 1 from public.sms_outbox
       where attempts < 5 and status in ('pending', 'failed', 'sending')
    );$$
);
