-- Soft-delete for rfid_readers. Without this, removing a reader would
-- CASCADE-delete every tap event it ever produced (the FK on
-- rfid_tap_events.reader_id, from add_rfid_reader_network_schema.sql, is
-- ON DELETE CASCADE) — fine for referential integrity, bad for an admin
-- "remove this reader" button, which should never silently destroy
-- attendance history. Deactivating instead of hard-deleting keeps the
-- history intact and the FK unchanged.
--
-- Run in Supabase SQL Editor, after add_rfid_reader_network_schema.sql.

alter table public.rfid_readers
  add column if not exists is_active boolean not null default true;

-- record_rfid_tap must reject taps from a deactivated reader — otherwise a
-- "removed" reader (e.g. one physically decommissioned but its serial
-- reused by mistake) could still silently write attendance data.
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
  v_last_direction public.rfid_tap_direction;
  v_next_direction public.rfid_tap_direction;
  v_tap_id uuid;
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

  if v_student_id is not null then
    select tap_direction into v_last_direction
      from public.rfid_tap_events
      where student_id = v_student_id
        and tapped_at::date = p_tapped_at::date
      order by tapped_at desc
      limit 1;
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
