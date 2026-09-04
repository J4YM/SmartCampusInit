-- Registers the Attendance Tap Monitor's dedicated entrance reader.
-- usb_serial is a placeholder — update it once the physical reader's real
-- serial is known (whoever does hardware setup edits this row, or reruns
-- this insert with the correct value before the app goes live).
--
-- Run in Supabase SQL Editor. Idempotent: safe to re-run.

insert into public.rfid_readers (label, usb_serial, location, is_kiosk_reader)
values ('Attendance Entrance Reader', 'ATTENDANCE-ENTRANCE-001', 'Main Entrance', false)
on conflict (usb_serial) do nothing;

-- ---------------------------------------------------------------------------
-- Realtime — the attendance_display app subscribes to inserts on
-- rfid_tap_events via Postgres Changes (attendance_display/lib/
-- tap_feed_controller.dart). Postgres Changes only delivers events for
-- tables in the supabase_realtime publication, so without this the display
-- never receives a single tap. Matches add_notifications_schema.sql's
-- pattern for the same thing. Idempotent (errors if already a member).
-- ---------------------------------------------------------------------------
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public' and tablename = 'rfid_tap_events'
  ) then
    alter publication supabase_realtime add table public.rfid_tap_events;
  end if;
end $$;
