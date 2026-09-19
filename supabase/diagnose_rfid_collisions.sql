-- supabase/diagnose_rfid_collisions.sql
--
-- Run this to get more detail on the two collisions
-- fix_and_backfill_student_rfid.sql's Part 3 diagnostic found — email,
-- whether each side has completed student registration, and (crucially)
-- what each colliding profile's OWN students.rfid_uid currently holds —
-- if it's already set to something else, the stale profiles.rfid_card_id
-- is harmless leftover junk regardless of who really owns the disputed
-- card; if it's null, this is a real "which of two students actually
-- holds this physical card" question only you can answer.

select
  p.id,
  p.email,
  p.first_name || ' ' || p.last_name as profile_name,
  p.rfid_card_id as stale_card_uid_in_profiles,
  p.created_at as profile_created_at,
  s.student_number as own_student_number,
  s.rfid_uid as own_current_rfid_uid,
  s.created_at as own_students_row_created_at
from public.profiles p
left join public.students s on s.id = p.id
where p.id in (
  '43df5eb8-4de8-41c6-b417-f822c79e2554',
  'fe7c6844-9cfb-4c53-af04-a9df0eeba062'
);

-- Also pull the same detail for the two students already correctly
-- holding these cards, for side-by-side comparison.
select
  p.id,
  p.email,
  p.first_name || ' ' || p.last_name as profile_name,
  s.student_number,
  s.rfid_uid,
  s.created_at as students_row_created_at
from public.students s
join public.profiles p on p.id = s.id
where s.rfid_uid in ('4033269951', '4042726335');
