-- DEMO ONLY: marks ~15 students as withdrawn by soft-dropping every one of
-- their Active enrollments (status = 'Dropped') — the same thing
-- RegistrarRepository.dropStudent() does, in bulk. A student whose
-- enrollments are ALL Dropped is what the ML retrain labels as a dropout.
--
-- Run in Supabase SQL Editor. Safe to re-run: students already dropped have
-- no Active enrollments left, so they are skipped and a fresh batch is
-- picked (change n below, or run the RESTORE section first to start over).
--
-- Every dropped enrollment id is saved to public.demo_dropped_enrollments,
-- so the RESTORE section at the bottom can put exactly those rows back.

-- Step 0 — number of students to drop.
-- (Edit the 15 in the `limit` below.)

-- Step 1 — PREVIEW (read-only): who would be dropped, and how many rows.
-- Run this on its own first if you want to eyeball it.
--
-- select e.student_id, count(*) as active_enrollments
-- from public.enrollments e
-- where e.status = 'Active'
--   and e.student_id in (
--     select student_id from public.enrollments
--     where status = 'Active'
--     group by student_id
--     order by student_id
--     limit 15
--   )
-- group by e.student_id
-- order by e.student_id;

-- Step 2 — DROP
create table if not exists public.demo_dropped_enrollments (
  enrollment_id uuid primary key,
  student_id uuid not null,
  dropped_at timestamptz not null default now()
);

with picked as (
  select student_id
  from public.enrollments
  where status = 'Active'
  group by student_id
  order by student_id
  limit 15
),
dropped as (
  update public.enrollments e
     set status = 'Dropped'
    from picked p
   where e.student_id = p.student_id
     and e.status = 'Active'
  returning e.id, e.student_id
)
insert into public.demo_dropped_enrollments (enrollment_id, student_id)
select id, student_id from dropped
on conflict (enrollment_id) do nothing;

-- Step 3 — verify: students now having zero Active enrollments
select count(distinct d.student_id) as students_dropped,
       count(*)                     as enrollments_dropped
from public.demo_dropped_enrollments d
join public.enrollments e on e.id = d.enrollment_id
where e.status = 'Dropped';

-- ---------------------------------------------------------------------
-- RESTORE (run separately after the demo): reactivates exactly the rows
-- this script dropped, then clears the log.
--
-- update public.enrollments e
--    set status = 'Active'
--   from public.demo_dropped_enrollments d
--  where e.id = d.enrollment_id
--    and e.status = 'Dropped';
--
-- delete from public.demo_dropped_enrollments;
-- ---------------------------------------------------------------------
