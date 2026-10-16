-- Resets TODAY for a fresh demo: clears the day's attendance records AND the
-- kiosk tap log, so students can tap in/out again and the professor dashboard
-- shows "Not recorded" / "No tap yet".
--
-- Two different things hold a day's state:
--   * public.attendance_records — the status a professor sees (Present/Absent..)
--   * public.rfid_tap_events    — the kiosk's tap-in / tap-out log. THIS is what
--     makes the kiosk say "You have already tapped in and out for today."
--
-- The kiosk's "school day" is not the calendar day: it rolls over at 6:30 PM
-- Philippine time (record_rfid_tap shifts by 5h30m before taking the date), so
-- a tap at 7:00 PM already belongs to TOMORROW's school day. Taps are cleared
-- by that same rule.
--
-- NOTE: the kiosk app also keeps its own local copy of today's taps on the
-- kiosk PC (kiosk_offline.sqlite) and checks that first — see the instructions
-- at the bottom. Clearing only the server is not enough.
--
-- Run in the Supabase SQL Editor. Run the PREVIEW first. The DELETE is one
-- transaction; change the final `commit` to `rollback` for a dry run.

-- PREVIEW (read-only)
select (now() at time zone 'Asia/Manila')::date as calendar_date,
       ((now() at time zone 'Asia/Manila') + interval '5 hours 30 minutes')::date as kiosk_school_day,
       (select count(*) from public.attendance_records
         where session_date = (now() at time zone 'Asia/Manila')::date) as attendance_rows_today,
       (select count(*) from public.rfid_tap_events
         where ((tapped_at at time zone 'Asia/Manila') + interval '5 hours 30 minutes')::date
             = ((now() at time zone 'Asia/Manila') + interval '5 hours 30 minutes')::date) as tap_events_this_school_day;

-- DELETE
begin;

delete from public.attendance_records
 where session_date = (now() at time zone 'Asia/Manila')::date;

delete from public.rfid_tap_events
 where ((tapped_at at time zone 'Asia/Manila') + interval '5 hours 30 minutes')::date
     = ((now() at time zone 'Asia/Manila') + interval '5 hours 30 minutes')::date;

select (select count(*) from public.attendance_records
         where session_date = (now() at time zone 'Asia/Manila')::date) as attendance_left,
       (select count(*) from public.rfid_tap_events
         where ((tapped_at at time zone 'Asia/Manila') + interval '5 hours 30 minutes')::date
             = ((now() at time zone 'Asia/Manila') + interval '5 hours 30 minutes')::date) as taps_left;  -- expect 0 / 0

commit;  -- use `rollback;` instead for a dry run

-- ---------------------------------------------------------------------------
-- ON THE KIOSK PC (after the SQL above):
--   1. Close the STI Baliuag Kiosk app.
--   2. Delete its local database so it forgets today's taps (it re-downloads
--      students/cards the next time it starts; any taps still waiting to sync
--      are lost, which is what you want for a reset). In PowerShell:
--
--        Get-ChildItem $env:APPDATA -Recurse -Filter "kiosk_offline.sqlite*" |
--          Remove-Item -Force
--
--      (This removes kiosk_offline.sqlite and its -wal / -shm files.)
--   3. Start the kiosk again.
-- ---------------------------------------------------------------------------
