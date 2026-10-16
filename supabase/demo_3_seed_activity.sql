-- DEMO PREP, step 3 of 3 — seed the activity the demo needs.
--
-- Run AFTER demo_1_cleanup.sql and the two pre-demo Registrar uploads (classes +
-- CFL; see the header of demo_1_cleanup.sql for the order). It seeds the 50
-- students in the DB at that moment; the 10-student batch is uploaded live
-- later. Re-running it after that upload also seeds those 10 (safe to re-run). Requires these migrations (all part of
-- the normal setup): add_attendance_per_class_section.sql,
-- add_student_gpa_records_schema.sql, fix_grades_scale_to_gwa.sql. The extra
-- student_violations columns (professor decision, archived_at) are added below.
--
-- For EVERY student currently in public.students (the 50 existing students;
-- or all 60 if re-run after the live batch upload) it creates:
--   1. enrollments    — in every class_section of the student's section, i.e. the
--                       subjects taught by their program's two professors. If the
--                       student's own section has no classes, they are moved to a
--                       same program + year section that does (sections.name 'A' first).
--   2. GPA records    — previous term (2025-2026 / 2nd Term) and current term
--                       (2026-2027 / 1st Term); the uploaded current-term rows are kept.
--   3. grades         — one 1.00-5.00 grade per enrollment.
--   4. attendance     — the last 6 weeks of real meeting days from
--                       class_section_meetings, recorded by the class's professor;
--                       students with no enrolled classes get weekday section-level
--                       attendance instead, so every student has ML data.
--   5. violations     — validated ('Resolved' + professor-confirmed) violations
--                       for the at-risk and middle groups, a couple of unvalidated
--                       reports (Pending / Under_Investigation) that the ML ignores.
--
-- Everyone gets a deterministic "profile" from a hash of their student number:
--   strong 60% | middle 25% | at-risk 15%   (Carl, if present, is pinned to the middle group)
-- so the ML risk model shows a spread of Low / Moderate / High / Critical.
--
-- Safe to re-run: every insert skips rows that already exist, except violations
-- (cleared first for the seeded students so they are not duplicated).
--
-- Whole script is ONE transaction. Triggers on the touched tables are disabled
-- inside it so seeding does not fire SMS / auto-intervention / escalation
-- triggers; they are re-enabled before commit (a failure rolls everything back).

begin;

-- Columns this script writes on student_violations. Normally added by
-- add_student_violations_professor_column.sql, add_professor_violation_confirmation.sql
-- and add_violation_archive_schema.sql; added here (idempotent) so the seed does
-- not depend on those having been run. The professor_decision check mirrors the
-- one in add_professor_violation_confirmation.sql.
alter table public.student_violations
  add column if not exists professor_id uuid references public.profiles(id) on delete set null,
  add column if not exists professor_decision text,
  add column if not exists professor_decision_note text,
  add column if not exists professor_decided_at timestamptz,
  add column if not exists archived_at timestamptz;

do $$
begin
  alter table public.student_violations
    add constraint student_violations_professor_decision_check
    check (professor_decision in ('Confirmed', 'Denied'));
exception when duplicate_object then null;
end $$;

alter table public.student_violations disable trigger user;
alter table public.attendance_records disable trigger user;
alter table public.enrollments disable trigger user;
alter table public.grades disable trigger user;

-- ---------------------------------------------------------------------------
-- 0. Per-student profile (temp table used by every step below).
-- ---------------------------------------------------------------------------
create temporary table _demo_students on commit drop as
select s.id,
       s.student_number,
       s.course,
       s.year_level,
       s.section_id,
       abs(('x' || substr(md5(s.student_number), 1, 8))::bit(32)::int) as h,
       case
         when s.student_number = '338958' then 'middle'
         when abs(('x' || substr(md5(s.student_number), 1, 8))::bit(32)::int) % 100 < 60 then 'strong'
         when abs(('x' || substr(md5(s.student_number), 1, 8))::bit(32)::int) % 100 < 85 then 'middle'
         else 'risk'
       end as profile
  from public.students s;

-- ---------------------------------------------------------------------------
-- 1. Sections + enrollments.
-- ---------------------------------------------------------------------------
-- Target section per student: own section if it has classes, else the first
-- same program/year section that does.
create temporary table _demo_target on commit drop as
select d.id as student_id,
       coalesce(
         (select cs.section_id from public.class_sections cs
           where cs.section_id = d.section_id limit 1),
         (select cs.section_id
            from public.class_sections cs
            join public.sections se on se.id = cs.section_id
           where se.program = d.course and se.year_level = d.year_level
           group by cs.section_id, se.name
           order by (se.name ~* 'A$') desc, se.name
           limit 1)
       ) as section_id
  from _demo_students d;

update public.students s
   set section_id = t.section_id
  from _demo_target t
 where t.student_id = s.id
   and t.section_id is not null
   and s.section_id is distinct from t.section_id;

insert into public.enrollments (student_id, class_section_id, status)
select t.student_id, cs.id, 'Active'
  from _demo_target t
  join public.class_sections cs on cs.section_id = t.section_id
 where t.section_id is not null
on conflict (student_id, class_section_id) do nothing;

-- ---------------------------------------------------------------------------
-- 2. GPA records (1.00-5.00, lower = better). Current term is skipped where the
--    Academic Honors upload already provided one.
-- ---------------------------------------------------------------------------
insert into public.student_gpa_records (
  student_id, school_year, term, cumulative_gpa, current_term_gpa,
  failed_courses_count, transfer_units, units_taken_cumulative, units_taken_current_term
)
select d.id, v.school_year, v.term,
       round(v.gpa::numeric, 3), round(v.gpa::numeric, 3),
       v.failed, 0, d.year_level * 21, 21
  from _demo_students d
  cross join lateral (values
    -- previous term
    ('2025-2026', '2nd Term',
       case d.profile
         when 'strong' then 1.20 + (d.h % 60) / 100.0
         when 'middle' then 2.00 + (d.h % 50) / 100.0
         else 2.40 + (d.h % 40) / 100.0 end,
       case d.profile when 'risk' then 1 else 0 end),
    -- current term: strong stays, middle slips a little, at-risk falls off
    ('2026-2027', '1st Term',
       case d.profile
         when 'strong' then 1.15 + ((d.h / 7) % 60) / 100.0
         when 'middle' then 2.20 + ((d.h / 7) % 50) / 100.0
         else 3.00 + ((d.h / 7) % 40) / 100.0 end,
       case d.profile when 'risk' then 2 + (d.h % 3) when 'middle' then (d.h % 2) else 0 end)
  ) as v(school_year, term, gpa, failed)
on conflict (student_id, school_year, term) do nothing;

-- ---------------------------------------------------------------------------
-- 3. Grades — one per enrollment, quarter-point steps within the profile's band.
-- ---------------------------------------------------------------------------
insert into public.grades (class_section_id, student_id, grade)
select e.class_section_id, e.student_id,
       least(5.00, greatest(1.00,
         round((case d.profile
                  when 'strong' then 1.25 + (hh % 75) / 100.0
                  when 'middle' then 2.00 + (hh % 80) / 100.0
                  else case when hh % 4 = 0 then 5.00 else 2.75 + (hh % 60) / 100.0 end
                end) * 4) / 4)::numeric
       )
  from public.enrollments e
  join _demo_students d on d.id = e.student_id
  cross join lateral (
    select abs(('x' || substr(md5(d.student_number || e.class_section_id::text), 1, 8))::bit(32)::int) as hh
  ) x
on conflict (student_id, class_section_id) do nothing;

-- ---------------------------------------------------------------------------
-- 4. Attendance — last 42 days, only on days the class actually meets.
--    absent chance: strong ~3% | middle ~9% | at-risk ~22% plus a forced
--    5-day absence streak 8-12 days ago (feeds max-consecutive-absences).
-- ---------------------------------------------------------------------------
insert into public.attendance_records (
  student_id, section_id, class_section_id, session_date, status, recorded_by
)
select e.student_id, cs.section_id, cs.id, g.d::date,
       (case
          when d.profile = 'risk' and g.d::date between current_date - 12 and current_date - 8
            then 'Absent'
          when r < case d.profile when 'strong' then 0.03 when 'middle' then 0.09 else 0.22 end
            then 'Absent'
          when r < case d.profile when 'strong' then 0.07 when 'middle' then 0.17 else 0.32 end
            then 'Late'
          else 'Present'
        end)::public.attendance_status,
       cs.professor_id
  from public.enrollments e
  join _demo_students d on d.id = e.student_id
  join public.class_sections cs on cs.id = e.class_section_id
  join (
    select distinct class_section_id,
           case day when 'M' then 1 when 'T' then 2 when 'W' then 3
                    when 'TH' then 4 when 'F' then 5 else 6 end as dow
      from public.class_section_meetings
  ) m on m.class_section_id = cs.id
  cross join generate_series(current_date - 42, current_date - 1, interval '1 day') as g(d)
  cross join lateral (
    select (abs(('x' || substr(md5(d.student_number || cs.id::text || g.d::date::text), 1, 8))::bit(32)::int) % 1000) / 1000.0 as r
  ) rr
 where extract(isodow from g.d) = m.dow
on conflict do nothing;

-- 4b. Fallback: any student still without attendance (no enrolled classes or no
--     schedule meetings uploaded yet) gets section-level daily attendance
--     (class_section_id null — the same legacy rows the ML already counts) on
--     weekdays, so the risk model has data for every student regardless of
--     whether the class/CFL uploads ran first. Same absence rates and streak.
insert into public.attendance_records (
  student_id, section_id, class_section_id, session_date, status
)
select d.id, coalesce(t.section_id, d.section_id), null, g.d::date,
       (case
          when d.profile = 'risk' and g.d::date between current_date - 12 and current_date - 8
            then 'Absent'
          when r < case d.profile when 'strong' then 0.03 when 'middle' then 0.09 else 0.22 end
            then 'Absent'
          when r < case d.profile when 'strong' then 0.07 when 'middle' then 0.17 else 0.32 end
            then 'Late'
          else 'Present'
        end)::public.attendance_status
  from _demo_students d
  join _demo_target t on t.student_id = d.id
  cross join generate_series(current_date - 42, current_date - 1, interval '1 day') as g(d)
  cross join lateral (
    select (abs(('x' || substr(md5(d.student_number || g.d::date::text), 1, 8))::bit(32)::int) % 1000) / 1000.0 as r
  ) rr
 where coalesce(t.section_id, d.section_id) is not null
   and extract(isodow from g.d) between 1 and 5
   and not exists (select 1 from public.attendance_records a where a.student_id = d.id)
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- 5. Violations. Validated = status 'Resolved' (what the ML counts) and a
--    professor 'Confirmed' decision. Clear any earlier seeded rows first.
-- ---------------------------------------------------------------------------
delete from public.student_violations
 where student_id in (select id from _demo_students);

create temporary table _demo_reporter on commit drop as
select coalesce(
  (select id from public.profiles
    where role = 'Discipline_Officer'::app_role and status = 'approved'::approval_status
    order by created_at limit 1),
  (select id from public.profiles
    where role = 'Teacher'::app_role order by created_at limit 1)
) as id;

-- Offense picked per category (first by description, so it is stable).
create temporary table _demo_offense on commit drop as
select distinct on (category) category::text as category, id
  from public.handbook_offenses
 order by category, description;

-- How many validated violations of which category each student gets.
create temporary table _demo_plan on commit drop as
select d.id as student_id, c.category, c.n
  from _demo_students d
  cross join lateral (values
    ('Minor',   case d.profile when 'risk' then 3 when 'middle' then 1 else (d.h % 2) end),
    ('Major_A', case d.profile when 'risk' then 1 + (d.h % 2) when 'middle' then (d.h % 2) else 0 end),
    ('Major_B', case d.profile when 'risk' then (d.h / 3) % 2 else 0 end),
    ('Major_C', case d.profile when 'risk' then (d.h / 5) % 2 else 0 end),
    ('Major_D', case when d.profile = 'risk' and d.h % 7 = 0 then 1 else 0 end)
  ) as c(category, n)
 where c.n > 0;

-- Carl (demo student): two minors + one Major A, deliberate and predictable.
update _demo_plan p set n = case p.category when 'Minor' then 2 else 1 end
 where p.student_id = (select id from _demo_students where student_number = '338958')
   and p.category in ('Minor', 'Major_A');
insert into _demo_plan (student_id, category, n)
select s.id, c, case c when 'Minor' then 2 else 1 end
  from _demo_students s, (values ('Minor'), ('Major_A')) v(c)
 where s.student_number = '338958'
   and not exists (select 1 from _demo_plan p where p.student_id = s.id and p.category = v.c);

insert into public.student_violations (
  student_id, offense_id, reported_by, professor_id, status, is_escalated,
  penalty_imposed, professor_decision, professor_decided_at, created_at, updated_at
)
select p.student_id, o.id, rep.id,
       (select cs.professor_id
          from public.enrollments e
          join public.class_sections cs on cs.id = e.class_section_id
         where e.student_id = p.student_id and cs.professor_id is not null
         order by md5(e.id::text || gs.n::text) limit 1),
       'Resolved'::violation_status,
       p.category in ('Major_C', 'Major_D'),
       case p.category when 'Minor' then 'Verbal warning issued.'
                       when 'Major_A' then 'Written warning on file.'
                       else 'Parent conference; case reviewed by the Discipline Board.' end,
       'Confirmed',
       now() - ((3 + (gs.n * 9) + abs(('x' || substr(md5(p.student_id::text || p.category), 1, 6))::bit(24)::int) % 20)
                * interval '1 day') + interval '2 hours',
       now() - ((3 + (gs.n * 9) + abs(('x' || substr(md5(p.student_id::text || p.category), 1, 6))::bit(24)::int) % 20)
                * interval '1 day'),
       now() - ((3 + (gs.n * 9) + abs(('x' || substr(md5(p.student_id::text || p.category), 1, 6))::bit(24)::int) % 20)
                * interval '1 day') + interval '1 day'
  from _demo_plan p
  join _demo_offense o on o.category = p.category
  cross join _demo_reporter rep
  cross join lateral generate_series(1, p.n) as gs(n);

-- Unvalidated reports (not counted by the ML): ~1 in 6 students.
insert into public.student_violations (
  student_id, offense_id, reported_by, status, is_escalated, created_at, updated_at
)
select d.id, o.id, rep.id,
       (case when d.h % 2 = 0 then 'Pending' else 'Under_Investigation' end)::violation_status,
       false,
       now() - ((1 + d.h % 4) * interval '1 day'),
       now() - ((1 + d.h % 4) * interval '1 day')
  from _demo_students d
  join _demo_offense o on o.category = 'Minor'
  cross join _demo_reporter rep
 where d.h % 6 = 1;

alter table public.student_violations enable trigger user;
alter table public.attendance_records enable trigger user;
alter table public.enrollments enable trigger user;
alter table public.grades enable trigger user;

-- ---------------------------------------------------------------------------
-- Summary — eyeball this before trusting the demo.
-- ---------------------------------------------------------------------------
select 'students' as what, count(*) from _demo_students
union all select 'enrollments', count(*) from public.enrollments
union all select 'grades', count(*) from public.grades
union all select 'attendance_records', count(*) from public.attendance_records
union all select 'gpa_records', count(*) from public.student_gpa_records
union all select 'violations (Resolved)', count(*) from public.student_violations where status = 'Resolved'
union all select 'violations (open)', count(*) from public.student_violations where status <> 'Resolved'
union all select 'students with NO enrollment', count(*)
  from _demo_students d where not exists (select 1 from public.enrollments e where e.student_id = d.id)
union all select 'profile: ' || profile, count(*) from _demo_students group by profile;

commit;  -- use `rollback;` instead for a dry run
