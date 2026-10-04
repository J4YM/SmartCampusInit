-- A kiosk that was offline sends its queued taps when it reconnects
-- (kiosk_offline replays them through record_rfid_tap with their ORIGINAL
-- p_tapped_at). This fixes one case that goes wrong when the outage spans the
-- 6:30 PM auto tap-out (auto_tap_out_open_students, add_sms_alerts_schema.sql).
--
-- The problem
--   The student tapped in (say 8:00 AM) and tapped out (say 4:00 PM) while the
--   kiosk was offline. At 6:30 PM the cron job finds an open `in` and inserts an
--   auto-generated `out` stamped 6:29:59 PM (and texts the parent "did not tap
--   out"). When the real 4:00 PM tap-out arrives later, record_rfid_tap sees the
--   6:29:59 row as the student's latest tap, computes (4:00 PM - 6:29:59 PM) =
--   a NEGATIVE interval, which is "< 5 seconds", and silently treats the real
--   tap as a double-tap: nothing is recorded, no SMS, and the record keeps the
--   automatic 6:29:59 PM out.
--
-- The fix (the only behaviour change)
--   If the student's latest tap that school day is AUTO-GENERATED and the
--   incoming tap is EARLIER than it, the incoming tap is a late real tap:
--     * it is checked against the student's REAL (non-auto) taps at that time,
--       with the same rules as always (double-tap echo, "already tapped in and
--       out", minimum wait after tapping in);
--     * if it is a valid tap-out, the auto-generated `out` is deleted and the
--       real `out` is inserted in its place, so attendance shows the real time
--       and the normal tap SMS trigger texts the parent "tapped OUT at ...".
--   Live taps use now() as their time, which is never earlier than a row that
--   already exists, so this branch cannot run for a live tap. Every other path
--   is unchanged.
--
-- Also: last_seen_at on the reader no longer moves BACKWARDS when an old tap is
-- replayed (it used to be set to the tap's timestamp, which made the kiosk
-- reader look offline on the admin dashboards after a replay).
--
-- This file REPLACES record_rfid_tap and INCLUDES fix_rfid_school_day_timezone.sql
-- (the Manila-time school day). Run THIS ONE; you do not need to also run that
-- file (if you do, run it BEFORE this one, never after: the last one wins).
--
-- >>> THE ONE SETTING TO CHECK: the tap-out wait. <<<
--   Set below as v_min_wait / v_wait_label. It is 5 seconds (dev) to match what
--   your database does today. For production change BOTH to '1 hour'. It must
--   match the kiosk build's KIOSK_TAP_OUT_MIN_WAIT_SECONDS (5 dev / 3600 prod).
--
-- BEFORE YOU RUN IT (30 seconds, strongly recommended):
--   Save the current function so you can put it back:
--     select pg_get_functiondef('public.record_rfid_tap'::regprocedure);
--   copy the result somewhere safe. Rolling back = running that text again.
--
-- AFTER YOU RUN IT: run supabase/test_late_replay_after_auto_tap_out.sql. It
-- writes nothing permanent (it rolls itself back) and ends with an error that
-- says TEST PASSED.
--
-- Same signature and return shape as before, so the kiosk, the Python reader
-- service and the in-app simulator need no change. Idempotent: safe to re-run.

create or replace function public.record_rfid_tap(
  p_reader_usb_serial text,
  p_rfid_uid text,
  p_tapped_at timestamptz default now()
)
returns table (
  tap_id uuid,
  reader_id uuid,
  student_id uuid,
  tap_direction public.rfid_tap_direction,
  tapped_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  -- ===== the tap-out wait: change both together (see the header) =====
  v_min_wait constant interval := interval '5 seconds';
  v_wait_label constant text := '5 seconds';
  -- ===================================================================

  v_reader_id uuid;
  v_is_active boolean;
  v_student_id uuid;
  v_last_tap_id uuid;
  v_last_reader_id uuid;
  v_last_direction public.rfid_tap_direction;
  v_last_tapped_at timestamptz;
  v_last_auto boolean;
  v_real_id uuid;
  v_real_reader_id uuid;
  v_real_direction public.rfid_tap_direction;
  v_real_tapped_at timestamptz;
  v_next_direction public.rfid_tap_direction;
  v_tap_id uuid;
  v_school_day date;
begin
  select id, is_active into v_reader_id, v_is_active
    from public.rfid_readers
    where usb_serial = p_reader_usb_serial;

  if v_reader_id is null then
    raise exception 'Unknown reader serial: %', p_reader_usb_serial;
  end if;

  if not v_is_active then
    raise exception 'Reader % is deactivated and cannot record taps.', p_reader_usb_serial;
  end if;

  -- greatest(): a replayed (old) tap must never move last_seen_at backwards.
  update public.rfid_readers
    set last_seen_at = greatest(coalesce(last_seen_at, p_tapped_at), p_tapped_at)
    where id = v_reader_id;

  select id into v_student_id
    from public.students
    where rfid_uid = p_rfid_uid;

  -- School day rolls over at 6:30 PM MANILA time (see
  -- fix_rfid_school_day_timezone.sql for why `at time zone` is needed).
  v_school_day := ((p_tapped_at at time zone 'Asia/Manila') + interval '5 hours 30 minutes')::date;

  if v_student_id is not null then
    -- Table alias required: RETURNS TABLE(...) declares tap_id/reader_id/
    -- student_id/tap_direction/tapped_at as variables in scope for the whole
    -- body, so unqualified references to same-named columns are ambiguous.
    select rte.id, rte.tap_direction, rte.tapped_at, rte.reader_id, rte.auto_generated
      into v_last_tap_id, v_last_direction, v_last_tapped_at, v_last_reader_id, v_last_auto
      from public.rfid_tap_events rte
      where rte.student_id = v_student_id
        and ((rte.tapped_at at time zone 'Asia/Manila') + interval '5 hours 30 minutes')::date = v_school_day
      order by rte.tapped_at desc
      limit 1;

    -- ---- NEW: a late real tap that happened BEFORE the auto tap-out ----
    if v_last_tap_id is not null
       and v_last_auto
       and p_tapped_at < v_last_tapped_at then

      -- The student's latest REAL (non-auto) tap at or before this moment.
      select rte.id, rte.tap_direction, rte.tapped_at, rte.reader_id
        into v_real_id, v_real_direction, v_real_tapped_at, v_real_reader_id
        from public.rfid_tap_events rte
        where rte.student_id = v_student_id
          and not rte.auto_generated
          and ((rte.tapped_at at time zone 'Asia/Manila') + interval '5 hours 30 minutes')::date = v_school_day
          and rte.tapped_at <= p_tapped_at
        order by rte.tapped_at desc
        limit 1;

      -- No real tap before it: not the case this branch handles. Fall through
      -- to the normal rules below, which behave exactly as they always did.
      if v_real_id is not null then
        -- A double tap of that real tap: echo it, record nothing new.
        if p_tapped_at - v_real_tapped_at < interval '5 seconds' then
          return query
            select v_real_id, v_real_reader_id, v_student_id, v_real_direction, v_real_tapped_at;
          return;
        end if;

        if v_real_direction = 'out' then
          raise exception 'You have already tapped in and out for today.';
        end if;

        if p_tapped_at - v_real_tapped_at < v_min_wait then
          raise exception
            'Please wait at least % after tapping in before tapping out.', v_wait_label;
        end if;

        -- Valid late tap-out: swap the auto-generated out for the real one.
        -- (The insert fires the normal tap SMS trigger.)
        delete from public.rfid_tap_events where id = v_last_tap_id;

        insert into public.rfid_tap_events (
          reader_id, rfid_uid, student_id, tap_direction, tapped_at
        )
        values (
          v_reader_id, p_rfid_uid, v_student_id, 'out', p_tapped_at
        )
        returning id into v_tap_id;

        return query
          select v_tap_id, v_reader_id, v_student_id,
                 'out'::public.rfid_tap_direction, p_tapped_at;
        return;
      end if;
    end if;
    -- ---- end NEW ----

    -- Debounce: an accidental double-tap within 5 seconds just echoes back
    -- the tap that already got recorded, instead of toggling again.
    if v_last_tap_id is not null
       and p_tapped_at - v_last_tapped_at < interval '5 seconds' then
      return query
        select v_last_tap_id, v_last_reader_id, v_student_id, v_last_direction, v_last_tapped_at;
      return;
    end if;

    if v_last_direction is null then
      -- No tap yet this school day.
      v_next_direction := 'in';
    elsif v_last_direction = 'in' then
      if p_tapped_at - v_last_tapped_at < v_min_wait then
        raise exception
          'Please wait at least % after tapping in before tapping out.', v_wait_label;
      end if;
      v_next_direction := 'out';
    else
      -- Already tapped in and out this school day — no 3rd tap.
      raise exception 'You have already tapped in and out for today.';
    end if;
  else
    -- Unrecognized card: unchanged behavior, always logs as 'in'.
    v_next_direction := 'in';
  end if;

  insert into public.rfid_tap_events (
    reader_id, rfid_uid, student_id, tap_direction, tapped_at
  )
  values (
    v_reader_id, p_rfid_uid, v_student_id, v_next_direction, p_tapped_at
  )
  returning id into v_tap_id;

  return query
    select v_tap_id, v_reader_id, v_student_id, v_next_direction, p_tapped_at;
end;
$$;
