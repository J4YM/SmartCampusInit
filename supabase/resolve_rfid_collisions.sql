-- supabase/resolve_rfid_collisions.sql
--
-- Clears the stale profiles.rfid_card_id for a profile
-- fix_and_backfill_student_rfid.sql's Part 3 diagnostic flagged as
-- colliding with a card already correctly held by a different student.
-- This does not touch students.rfid_uid at all — only removes the
-- redundant, unused profiles.rfid_card_id value that was blocking the
-- backfill and the collision diagnostic.

-- Matunan (43df5eb8-4de8-41c6-b417-f822c79e2554): confirmed via
-- diagnose_rfid_collisions.sql to have has_own_students_row = 0 — never
-- completed student self-registration, so this stale value is genuinely
-- unused junk. Xander Bernardo already correctly holds card 4033269951.
--
-- NOTE: this alone does not let a new card be assigned to Matunan yet.
-- link_rfid_card() requires an existing `students` row to attach a card
-- to (old or new) and the Admin RFID Mapping page's "Unclaimed Profiles"
-- list now requires one too (see fetchProfilesMissingRfidCard's inner
-- join to students) — Matunan needs to log in and finish the student
-- self-registration form first. Once that creates their `students` row,
-- they'll reappear in "Unclaimed Profiles" and a new card can be
-- assigned normally.
update public.profiles set rfid_card_id = null
where id = '43df5eb8-4de8-41c6-b417-f822c79e2554';

-- Ruben III N. Banaga (fe7c6844-9cfb-4c53-af04-a9df0eeba062), card
-- 4042726335 (Juan A. Dela Cruz already holds it) — LEFT UNRESOLVED.
-- Ruben has a completed students row (student_number 250559), so this
-- needs to know what his OWN students.rfid_uid currently holds before
-- deciding anything — see diagnose_rfid_collisions.sql's second query.
-- Do not run the line below until that's confirmed:
-- update public.profiles set rfid_card_id = null where id = 'fe7c6844-9cfb-4c53-af04-a9df0eeba062';
