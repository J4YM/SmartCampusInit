-- supabase/diagnose_rfid_collisions.sql
--
-- Run this to get more detail on the two collisions
-- fix_and_backfill_student_rfid.sql's Part 3 diagnostic found — email and
-- whether each side has actually completed student registration (a
-- students row of its own), to help decide which side is the real owner
-- of the card before clearing the other one by hand.

select
  p.id,
  p.email,
  p.first_name || ' ' || p.last_name as profile_name,
  p.rfid_card_id as stale_card_uid,
  p.created_at,
  (select count(*) from public.students s where s.id = p.id) as has_own_students_row,
  (select student_number from public.students s where s.id = p.id) as own_student_number
from public.profiles p
where p.id in (
  '43df5eb8-4de8-41c6-b417-f822c79e2554',
  'fe7c6844-9cfb-4c53-af04-a9df0eeba062'
);
