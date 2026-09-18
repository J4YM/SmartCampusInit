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
--
-- students.rfid_uid has its own unique constraint (students_rfid_uid_key),
-- separate from profiles.rfid_card_id's — so it's possible for the SAME
-- card number to sit correctly on one student's rfid_uid already, while
-- also sitting (wrongly) in a DIFFERENT student's profiles.rfid_card_id
-- from an accidental double-assignment before the fix. Plain UPDATE...FROM
-- fails outright on the first such collision and rolls back the ENTIRE
-- statement — every other, non-conflicting row along with it. Both steps
-- below explicitly skip a conflicting row instead of aborting, and Step 0
-- lists exactly which ones were skipped so you can look at them by hand.

-- 0. Run this first and read the results: every case where a Student's
--    profiles.rfid_card_id collides with a DIFFERENT student's already-set
--    rfid_uid. Each row here needs a human decision (which student the
--    card really belongs to) — Steps 1-2 below leave these untouched.
select
  p.id as profile_id_with_stale_rfid_card_id,
  p.first_name || ' ' || p.last_name as profile_name,
  p.rfid_card_id as colliding_card_uid,
  s2.id as student_id_already_holding_this_card,
  pr2.first_name || ' ' || pr2.last_name as student_already_holding_it_name
from public.profiles p
join public.students s2 on s2.rfid_uid = p.rfid_card_id
join public.profiles pr2 on pr2.id = s2.id
where p.role = 'Student'::app_role
  and p.rfid_card_id is not null
  and s2.id <> p.id;

-- 1. Copy any RFID sitting in a Student's profiles.rfid_card_id into
--    students.rfid_uid, wherever a matching students row exists, doesn't
--    already have one, AND no OTHER student already holds that same
--    card (see Step 0 — those are skipped here, not overwritten).
update public.students s
set rfid_uid = p.rfid_card_id
from public.profiles p
where p.id = s.id
  and p.role = 'Student'::app_role
  and p.rfid_card_id is not null
  and s.rfid_uid is null
  and not exists (
    select 1 from public.students s2
    where s2.rfid_uid = p.rfid_card_id and s2.id <> p.id
  );

-- 2. Clear the now-redundant profiles.rfid_card_id for students — going
--    forward link_rfid_card() never writes there for a Student, so
--    leaving old values behind would just be confusing clutter. Only
--    clears rows where step 1 actually copied the value across
--    (rfid_uid now matches) — a Step 0 collision keeps its
--    profiles.rfid_card_id untouched, since that's still the only
--    record of that assignment until it's manually resolved.
update public.profiles p
set rfid_card_id = null
where p.role = 'Student'::app_role
  and p.rfid_card_id is not null
  and exists (
    select 1 from public.students s
    where s.id = p.id and s.rfid_uid = p.rfid_card_id
  );
