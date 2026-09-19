-- supabase/resolve_rfid_collisions.sql
--
-- Clears the stale profiles.rfid_card_id for the two profiles
-- fix_and_backfill_student_rfid.sql's Part 3 diagnostic flagged as
-- colliding with a card already correctly held by a different student
-- (Xander Bernardo and Juan A. Dela Cruz respectively). Run
-- diagnose_rfid_collisions.sql FIRST and confirm those two really are
-- the wrong side (e.g. an incomplete/blank-name registration, or your
-- own test account) before running this — this does not touch
-- students.rfid_uid at all, only removes the redundant, unused
-- profiles.rfid_card_id value that was blocking the backfill.
--
-- After running this, re-run fix_and_backfill_student_rfid.sql (or just
-- its Part 2) — these two profiles no longer have anything in
-- profiles.rfid_card_id to backfill, so it'll simply have nothing left
-- to do for them; Part 3's diagnostic should come back empty.

update public.profiles set rfid_card_id = null
where id = '43df5eb8-4de8-41c6-b417-f822c79e2554'; -- blank-name profile, card 4033269951 (Xander Bernardo already holds it)

update public.profiles set rfid_card_id = null
where id = 'fe7c6844-9cfb-4c53-af04-a9df0eeba062'; -- Ruben III N. Banaga, card 4042726335 (Juan A. Dela Cruz already holds it)
