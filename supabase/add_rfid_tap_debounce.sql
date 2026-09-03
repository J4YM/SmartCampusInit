-- Adds a 5-second debounce to record_rfid_tap so an accidental double-tap
-- of the same card doesn't toggle in/out twice. Minimal change to the
-- existing function (supabase/add_rfid_reader_network_schema.sql) — same
-- signature, same return shape, one added early-return branch.
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
  v_student_id uuid;
  v_last_tap_id uuid;
  v_last_direction public.rfid_tap_direction;
  v_last_tapped_at timestamptz;
  v_next_direction public.rfid_tap_direction;
  v_tap_id uuid;
begin
  select id into v_reader_id
    from public.rfid_readers
    where usb_serial = p_reader_usb_serial;

  if v_reader_id is null then
    raise exception 'Unknown reader serial: %', p_reader_usb_serial;
  end if;

  update public.rfid_readers
    set last_seen_at = p_tapped_at
    where id = v_reader_id;

  select id into v_student_id
    from public.students
    where rfid_uid = p_rfid_uid;

  if v_student_id is not null then
    select id, tap_direction, tapped_at
      into v_last_tap_id, v_last_direction, v_last_tapped_at
      from public.rfid_tap_events
      where student_id = v_student_id
        and tapped_at::date = p_tapped_at::date
      order by tapped_at desc
      limit 1;

    -- Debounce: an accidental double-tap within 5 seconds just echoes back
    -- the tap that already got recorded, instead of toggling again.
    if v_last_tap_id is not null
       and p_tapped_at - v_last_tapped_at < interval '5 seconds' then
      return query
        select v_last_tap_id, v_reader_id, v_student_id, v_last_direction, v_last_tapped_at;
      return;
    end if;
  end if;

  v_next_direction := case
    when v_last_direction = 'in' then 'out'::public.rfid_tap_direction
    else 'in'::public.rfid_tap_direction
  end;

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
