-- Lets a professor delete a day's attendance (Take Attendance -> date column
-- menu -> "Delete attendance for this day"). add_professor_module_schema.sql
-- only granted select / insert / update on attendance_records, so the delete
-- is rejected (silently, as 0 rows) until this policy exists.
--
-- Same open anon + authenticated model as the rest of that table's policies
-- (the professor console can be signed in through a static demo account that
-- talks to the database as `anon`).
--
-- Run in the Supabase SQL Editor. Idempotent.

drop policy if exists "attendance_records_anon_delete" on public.attendance_records;
create policy "attendance_records_anon_delete"
  on public.attendance_records
  for delete
  to anon, authenticated
  using (true);
