-- DEMO ONLY: label enough students as dropped for the ML retrain to run.
--
-- The retrain reads the live database and refuses to run unless there are at
-- least 250 students and at least 50 of EACH class (dropped / not dropped).
-- It labels a student "dropped" when every one of their enrollments is
-- 'Dropped' (the same thing demo_drop_students.sql and the Registrar's drop
-- action write).
--
-- Order:
--   1. populating/populate_mock_data.sql   -> 250 mock students (900001-900250)
--   2. the class/CFL uploads, then demo_3_seed_activity.sql
--                                           -> enrollments, attendance, grades,
--                                              GPA, violations for every student
--   3. THIS FILE                            -> marks the highest-risk ones dropped
--
-- Unlike demo_drop_students.sql (which drops the first 15 by id, unrelated to
-- anything), the students dropped here are picked from their seeded absence
-- rate, violation severity and GPA, plus random noise (about +/-15 percentile
-- points) so the label is NOT a clean rule. Without the noise the model would
-- just relearn a threshold and go back to 0% / 100% scores.
--
-- This is still synthetic: a model trained on it learns how this seed data was
-- generated, not real dropout behavior. Replace with real outcomes later.
--
-- Safe to re-run: students already dropped are skipped and the target is
-- topped up, not doubled. Every dropped enrollment is saved in
-- public.demo_dropped_enrollments (same table as demo_drop_students.sql), so the
-- RESTORE block at the bottom puts exactly those rows back.
--
-- Run in the Supabase SQL Editor. Run the PREVIEW first. The change is one
-- transaction; use `rollback;` instead of `commit;` for a dry run.

-- ---------------------------------------------------------------------------
-- PREVIEW (read-only) — run this on its own first.
-- ---------------------------------------------------------------------------
-- select count(*) as students,
--        count(*) filter (where exists (select 1 from public.enrollments e where e.student_id = s.id)) as with_enrollments,
--        count(*) filter (where exists (select 1 from public.enrollments e where e.student_id = s.id)
--                           and not exists (select 1 from public.enrollments e where e.student_id = s.id and e.status <> 'Dropped')) as already_dropped
--   from public.students s;
-- Need: students >= 250 and with_enrollments close to students. If
-- with_enrollments is far lower, run the class uploads + demo_3_seed_activity.sql
-- first; students with no enrollments cannot be labeled here.

-- ---------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------
-- Share of all students to end up dropped. 0.25 on 250 students = 63 dropped,
-- 187 retained (the retrain needs >= 50 of each).

begin;

create table if not exists public.demo_dropped_enrollments (
  enrollment_id uuid primary key,
  student_id uuid not null,
  dropped_at timestamptz not null default now()
);

create temporary table _lbl_params on commit drop as
select 0.25::numeric as drop_share, 0.30::numeric as noise_width;

-- One row per student with a risk score built from the seeded data.
create temporary table _lbl_students on commit drop as
with att as (
  select student_id,
         count(*) filter (where status::text = 'Absent')::numeric / nullif(count(*), 0) as absent_rate
    from public.attendance_records
   group by student_id
),
viol as (
  select v.student_id,
         sum(case o.category::text
               when 'Minor'   then 0.3
               when 'Major_A' then 0.8
               when 'Major_B' then 1.5
               when 'Major_C' then 3.0
               when 'Major_D' then 4.0
               else 0.3 end) as severity
    from public.student_violations v
    join public.handbook_offenses o on o.id = v.offense_id
   where v.status::text = 'Resolved'
     and v.archived_at is null
   group by v.student_id
),
gpa as (
  select distinct on (student_id) student_id, current_term_gpa
    from public.student_gpa_records
   order by student_id, school_year desc, term desc
),
enr as (
  select student_id,
         count(*) as n_enrollments,
         count(*) filter (where status <> 'Dropped') as n_not_dropped
    from public.enrollments
   group by student_id
)
select s.id as student_id,
       s.student_number,
       coalesce(enr.n_enrollments, 0) as n_enrollments,
       coalesce(enr.n_not_dropped, 0) as n_not_dropped,
       -- scales: absences 0.03-0.3 -> 0.3-3 | violations 0-10 -> 0-5 | GPA (1.0 best) 1.2-3.4 -> -0.8-1.4
       coalesce(att.absent_rate, 0) * 10
         + coalesce(viol.severity, 0) * 0.5
         + coalesce(gpa.current_term_gpa - 2.0, 0) as score,
       ((abs(('x' || substr(md5('label-noise:' || s.student_number), 1, 8))::bit(32)::int) % 1000) / 1000.0 - 0.5) as noise
  from public.students s
  left join att on att.student_id = s.id
  left join viol on viol.student_id = s.id
  left join gpa on gpa.student_id = s.id
  left join enr on enr.student_id = s.id;

-- Candidates: students that still have an enrollment to drop, ranked by
-- percentile of risk score plus noise (highest first).
create temporary table _lbl_ranked on commit drop as
select q.student_id,
       row_number() over (order by q.noisy_rank desc) as rk
  from (
    select l.student_id,
           percent_rank() over (order by l.score) + l.noise * p.noise_width as noisy_rank
      from _lbl_students l
      cross join _lbl_params p
     where l.n_not_dropped > 0
  ) q;

-- How many MORE students must be dropped to reach the target share.
create temporary table _lbl_need on commit drop as
select greatest(
         ceil((select count(*) from _lbl_students) * (select drop_share from _lbl_params))::int
         - (select count(*) from _lbl_students where n_enrollments > 0 and n_not_dropped = 0)::int,
         0
       ) as n_more;

with picked as (
  select student_id from _lbl_ranked
   where rk <= (select n_more from _lbl_need)
),
dropped as (
  update public.enrollments e
     set status = 'Dropped'
    from picked p
   where e.student_id = p.student_id
     and e.status <> 'Dropped'
  returning e.id, e.student_id
)
insert into public.demo_dropped_enrollments (enrollment_id, student_id)
select id, student_id from dropped
on conflict (enrollment_id) do nothing;

-- ---------------------------------------------------------------------------
-- Summary — eyeball this before committing. The retrain needs students >= 250,
-- dropped >= 50 and retained >= 50.
-- ---------------------------------------------------------------------------
select count(*) as students,
       count(*) filter (where n_enrollments > 0 and not exists (
         select 1 from public.enrollments e where e.student_id = l.student_id and e.status <> 'Dropped'
       )) as dropped_for_ml,
       count(*) filter (where n_enrollments = 0 or exists (
         select 1 from public.enrollments e where e.student_id = l.student_id and e.status <> 'Dropped'
       )) as retained_for_ml,
       (select n_more from _lbl_need) as newly_dropped_this_run
  from _lbl_students l;

commit;  -- use `rollback;` instead for a dry run

-- ---------------------------------------------------------------------------
-- RESTORE (run separately): reactivates exactly the rows dropped by this
-- script (and by demo_drop_students.sql, which shares the log), then clears it.
--
-- update public.enrollments e
--    set status = 'Active'
--   from public.demo_dropped_enrollments d
--  where e.id = d.enrollment_id
--    and e.status = 'Dropped';
--
-- delete from public.demo_dropped_enrollments;
-- ---------------------------------------------------------------------------
