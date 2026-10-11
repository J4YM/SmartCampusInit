-- Removes the placeholder "Floor 1 / Floor 2 / Floor 3 Reader" rows that
-- add_rfid_reader_network_schema.sql used to seed. Run once in the Supabase
-- SQL Editor on a database that already has them.
--
-- Nothing of value is destroyed:
--   * a starter reader that never recorded a tap is deleted outright;
--   * one that did record taps is only DEACTIVATED, which takes it off the
--     IT Technician "Kiosk & Readers" list (inactive readers are hidden
--     there) and stops it recording, but keeps its attendance history —
--     rfid_tap_events.reader_id is ON DELETE CASCADE, so deleting it would
--     erase those taps.
--
-- Real floor readers are registered through IT Technician > Kiosk & Readers
-- > Add Reader. Safe to re-run.

-- 1. Never used: delete.
delete from public.rfid_readers r
 where r.usb_serial in (
         'FLOOR-1-READER-001',
         'FLOOR-2-READER-001',
         'FLOOR-3-READER-001'
       )
   and not exists (
         select 1 from public.rfid_tap_events e where e.reader_id = r.id
       );

-- 2. Has history: keep the history, retire the reader.
update public.rfid_readers
   set is_active = false
 where usb_serial in (
         'FLOOR-1-READER-001',
         'FLOOR-2-READER-001',
         'FLOOR-3-READER-001'
       );

-- Check what is left:
-- select label, usb_serial, is_active from public.rfid_readers order by label;
