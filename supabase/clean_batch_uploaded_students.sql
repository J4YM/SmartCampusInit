-- Cleans out students (and their guardians) that were created by the batch
-- enrollment upload, while leaving every older student already in the system.
--
-- How batch rows are recognised: EnrollmentImportRepository mints new students
-- and guardians through create_batch_student_account /
-- create_batch_guardian_account (add_batch_enrollment_rpc.sql), which insert an
-- auth.users row with raw_app_meta_data.provider = 'system'. Real
-- self-registered students are provider 'anonymous'/'azure', so they are never
-- matched. The email domain can't be used here: batch students get the real
-- school domain (lastname.NNNNNN@baliuag.sti.edu.ph).
--
-- "Old vs new" is decided by a cutoff: only batch rows created AT OR AFTER
-- the cutoff are removed. Older batch rows (and everything else) stay.
--
-- 1. Run STEP 1 and look at the per-day counts to find the day(s) of the
--    upload(s) you want gone.
-- 2. Set the cutoff in STEP 2 / STEP 3 (the one `cutoff` line, both places).
-- 3. Run STEP 2 (preview), then STEP 3 (delete) — STEP 3 runs in one
--    transaction; replace the final `commit` with `rollback` for a dry run.

-- ---------------------------------------------------------------------------
-- STEP 1 — how many batch-created students exist, per creation day.
-- ---------------------------------------------------------------------------
select date_trunc('day', p.created_at) as created_day,
       count(*) as batch_students
from public.profiles p
join auth.users u on u.id = p.id
where p.role = 'Student'
  and u.raw_app_meta_data ->> 'provider' = 'system'
group by 1
order by 1 desc;

-- ---------------------------------------------------------------------------
-- STEP 2 — PREVIEW what STEP 3 would delete. Edit the cutoff.
-- ---------------------------------------------------------------------------
with params as (select timestamptz '2026-10-01 00:00:00+08' as cutoff)
select s.student_number, p.first_name, p.last_name, s.course, s.year_level,
       p.email, p.created_at
from public.profiles p
join public.students s on s.id = p.id
join auth.users u on u.id = p.id
cross join params
where p.role = 'Student'
  and u.raw_app_meta_data ->> 'provider' = 'system'
  and p.created_at >= params.cutoff
order by p.created_at desc;

-- ---------------------------------------------------------------------------
-- STEP 3 — DELETE. Same cutoff as STEP 2. Children before parents.
-- ---------------------------------------------------------------------------
begin;

create temporary table _batch_student_ids on commit drop as
select p.id
from public.profiles p
join auth.users u on u.id = p.id
where p.role = 'Student'
  and u.raw_app_meta_data ->> 'provider' = 'system'
  and p.created_at >= timestamptz '2026-10-01 00:00:00+08';  -- << cutoff

-- Guardians created by the same batch whose ONLY linked children are being
-- deleted. A guardian who also has an older (kept) child is left alone.
create temporary table _batch_guardian_ids on commit drop as
select p.id
from public.profiles p
join auth.users u on u.id = p.id
where p.role = 'Parent'
  and u.raw_app_meta_data ->> 'provider' = 'system'
  and exists (select 1 from public.parent_student_links l
              where l.parent_id = p.id
                and l.student_id in (select id from _batch_student_ids))
  and not exists (select 1 from public.parent_student_links l
                  where l.parent_id = p.id
                    and l.student_id not in (select id from _batch_student_ids));

-- enrollments/grades have no ON DELETE CASCADE to students.
delete from public.enrollments where student_id in (select id from _batch_student_ids);
delete from public.grades      where student_id in (select id from _batch_student_ids);
delete from public.parent_student_links
 where student_id in (select id from _batch_student_ids);

-- Everything else referencing students cascades.
delete from public.students where id in (select id from _batch_student_ids);

-- parent_credentials cascades from profiles.
delete from public.profiles where id in (select id from _batch_guardian_ids);
delete from public.profiles where id in (select id from _batch_student_ids);
delete from auth.users
 where id in (select id from _batch_guardian_ids)
    or id in (select id from _batch_student_ids);

commit;  -- use `rollback;` instead for a dry run

-- Sections the import auto-created ("BSIT 1B", ...) are left in place; empty
-- ones are harmless and may be reused by the next upload.
