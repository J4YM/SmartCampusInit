-- supabase/backfill_student_rfid_from_profiles.sql
--
-- One-time data fix for anything assigned through Admin's RFID Card
-- Mapping page BEFORE fix_link_rfid_card_for_students.sql — a card given
-- to a Student-role profile went into profiles.rfid_card_id, a column
-- the kiosk's student lookup (StudentsRepository.fetchStudentByRfidUid)
-- never reads. The value isn't lost, just filed under the wrong column;
-- this moves it to students.rfid_uid, where it actually takes effect.
--
-- Run this AFTER fix_link_rfid_card_for_students.sql. Idempotent: safe to
-- re-run — after the first run nothing will match either update anymore.

-- 1. Copy any RFID sitting in a Student's profiles.rfid_card_id into
--    students.rfid_uid, wherever a matching students row exists and
--    doesn't already have one (never overwrites an existing rfid_uid).
update public.students s
set rfid_uid = p.rfid_card_id
from public.profiles p
where p.id = s.id
  and p.role = 'Student'::app_role
  and p.rfid_card_id is not null
  and s.rfid_uid is null;

-- 2. Clear the now-redundant profiles.rfid_card_id for students — going
--    forward link_rfid_card() never writes there for a Student, so
--    leaving old values behind would just be confusing clutter. Only
--    clears rows where a students row actually exists to have received
--    the value in step 1, so nothing is silently discarded for an edge
--    case profile with role Student but no completed registration yet.
update public.profiles p
set rfid_card_id = null
where p.role = 'Student'::app_role
  and p.rfid_card_id is not null
  and exists (select 1 from public.students s where s.id = p.id);
