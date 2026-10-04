-- Replaces record_rfid_tap's old "toggle indefinitely" behavior with three
-- new rules per student:
--   1. At most one tap-in and one tap-out per school day — a 3rd tap this
--      school day is rejected instead of toggling back to 'in' again.
--   2. Tap-out is only allowed at least 1 hour after that same day's
--      tap-in (a school day's shortest class is ~1 hour; this is the
--      "attended at least one class" floor).
--   3. "School day" is not the calendar day — it resets at 6:30 PM (the
--      end of all classes), not midnight, so e.g. a tap at 7 PM starts a
--      *new* school day's in/out cycle rather than counting against the
--      day that's ending. Implemented by shifting the clock forward 5h30m
--      before taking `::date`: a timestamp's date only advances once it
--      crosses 6:30 PM, not midnight.
--
-- Layered on top of the existing function (supabase/add_rfid_tap_debounce.sql)
-- — same signature, same return shape. The debounce lookup and the new
-- rules reuse one query (both need "this student's latest tap this school
-- day"), same as the debounce version reused the toggle lookup.
--
-- An unrecognized card (student_id null) is unaffected — it keeps logging
-- as 'in' every time, same as before; these rules only apply once a card
-- resolves to a real student.
--
-- Run in Supabase SQL Editor. Idempotent: safe to re-run.

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
  v_reader_id uuid;
  v_is_active boolean;
  v_student_id uuid;
  v_last_tap_id uuid;
  v_last_reader_id uuid;
  v_last_direction public.rfid_tap_direction;
  v_last_tapped_at timestamptz;
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

  update public.rfid_readers
    set last_seen_at = p_tapped_at
    where id = v_reader_id;

  select id into v_student_id
    from public.students
    where rfid_uid = p_rfid_uid;

  -- Shifting by 5h30m before truncating to a date moves the rollover point
  -- from midnight to 6:30 PM: a tap at 18:29 keeps today's date, a tap at
  -- 18:30 already belongs to tomorrow's school day.
  v_school_day := (p_tapped_at + interval '5 hours 30 minutes')::date;

  if v_student_id is not null then
    -- Table alias required: this function's RETURNS TABLE(...) clause
    -- declares tap_id/reader_id/student_id/tap_direction/tapped_at as
    -- implicit PL/pgSQL variables in scope for the whole function body, so
    -- any unqualified reference to rfid_tap_events' same-named columns is
    -- ambiguous (Postgres error 42702) — only surfaces at actual runtime,
    -- not at CREATE FUNCTION time, and only on this branch (a recognized
    -- student's tap).
    select rte.id, rte.tap_direction, rte.tapped_at, rte.reader_id
      into v_last_tap_id, v_last_direction, v_last_tapped_at, v_last_reader_id
      from public.rfid_tap_events rte
      where rte.student_id = v_student_id
        and (rte.tapped_at + interval '5 hours 30 minutes')::date = v_school_day
      order by rte.tapped_at desc
      limit 1;

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
      if p_tapped_at - v_last_tapped_at < interval '5 seconds' then
        raise exception
          'Please wait at least 5 seconds after tapping in before tapping out.';
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
