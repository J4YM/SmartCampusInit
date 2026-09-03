-- Registers the Attendance Tap Monitor's dedicated entrance reader.
-- usb_serial is a placeholder — update it once the physical reader's real
-- serial is known (whoever does hardware setup edits this row, or reruns
-- this insert with the correct value before the app goes live).
--
-- Run in Supabase SQL Editor. Idempotent: safe to re-run.

insert into public.rfid_readers (label, usb_serial, location, is_kiosk_reader)
values ('Attendance Entrance Reader', 'ATTENDANCE-ENTRANCE-001', 'Main Entrance', false)
on conflict (usb_serial) do nothing;
