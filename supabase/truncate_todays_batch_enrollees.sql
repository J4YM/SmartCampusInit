-- Removes every student created TODAY (calendar date) — cleans up after
-- the Registrar's repeated batch-enrollment attempts that kept stalling
-- partway through on Supabase Auth's account-creation rate limit (see the
-- retry/stop-early fix in enrollment_import_repository.dart /
-- enrollment_import_runner.dart), so a clean re-upload starts from
-- scratch instead of layering on top of the partial rows those failed
-- runs left behind.
--
-- Also removes any guardian (Parent profile) account the same import
-- created that would be left with zero linked students once today's
-- students are gone — otherwise re-uploading leaves dangling Parent
-- accounts with nobody attached. A guardian who is ALSO linked to a
-- student created on a different day is left untouched.
--
-- "Today" is the database's own current_date (session timezone, usually
-- UTC on Supabase) — if that doesn't line up with your local "today"
-- (e.g. something run very late at night), the PREVIEW block below shows
-- every row's actual created_at timestamp so you can catch a mismatch
-- before running the DELETE block. Adjust the `current_date` filters to
-- an explicit date (e.g. `'2026-10-06'`) if you need a different window.
--
-- Run the PREVIEW block first and confirm every row shown is one you
-- expect to clear before running the DELETE block.

-- ---------------------------------------------------------------------------
-- PREVIEW — run this first.
-- ---------------------------------------------------------------------------

select
  s.student_number,
  p.first_name,
  p.last_name,
  s.course,
  s.year_level,
  p.email,
  s.created_at
from public.students s
join public.profiles p on p.id = s.id
where s.created_at::date = current_date
order by s.created_at desc;

select count(*) as todays_student_count
from public.students
where created_at::date = current_date;

-- Guardians that would be left with zero linked students once today's
-- students are removed.
select
  p.id,
  p.first_name,
  p.last_name,
  p.email,
  p.created_at
from public.profiles p
where p.role = 'Parent'
  and exists (
    select 1
    from public.parent_student_links l
    join public.students s on s.id = l.student_id
    where l.parent_id = p.id and s.created_at::date = current_date
  )
  and not exists (
    select 1
    from public.parent_student_links l
    join public.students s on s.id = l.student_id
    where l.parent_id = p.id and s.created_at::date <> current_date
  );

-- ---------------------------------------------------------------------------
-- DELETE — only run this after the preview above looks right. Order
-- matters (child rows before the parents they reference).
-- ---------------------------------------------------------------------------

create temporary table _todays_student_ids as
select id from public.students where created_at::date = current_date;

-- Guardians orphaned by this cleanup, computed BEFORE any links below are
-- deleted — this is what "would have zero links left" means.
create temporary table _orphaned_guardian_ids as
select p.id
from public.profiles p
where p.role = 'Parent'
  and exists (
    select 1 from public.parent_student_links l
    where l.parent_id = p.id
      and l.student_id in (select id from _todays_student_ids)
  )
  and not exists (
    select 1 from public.parent_student_links l
    where l.parent_id = p.id
      and l.student_id not in (select id from _todays_student_ids)
  );

-- enrollments/grades reference students WITHOUT on delete cascade
-- (add_subjects_enrollments_schema.sql / add_grades_schema.sql) — deleting
-- students first would fail with a foreign-key violation if either has a
-- row for one of them. Matches delete_mock_student_batch_upload.sql's own
-- reasoning.
delete from public.enrollments where student_id in (select id from _todays_student_ids);
delete from public.grades where student_id in (select id from _todays_student_ids);

-- parent_student_links and student_violations both predate version
-- control (no tracked CREATE TABLE for either), so their delete behavior
-- can't be verified from the codebase — deleting explicitly here is a
-- safety net in case either lacks cascade, same reasoning
-- delete_mock_student_batch_upload.sql / reset_schedule_import_test_data.sql
-- use for other untracked tables. In practice brand-new, same-day
-- students have no violations yet, so this is a no-op most of the time.
delete from public.student_violations where student_id in (select id from _todays_student_ids);
delete from public.parent_student_links where student_id in (select id from _todays_student_ids);

-- Every other table referencing students (admission_slips,
-- good_moral_requests, parent_interventions, attendance_records,
-- rfid_assignment_requests, rfid_tap_events, risk_assessments,
-- student_gpa_records, sms_outbox) already has on delete cascade or on
-- delete set null, so deleting students here is enough for all of them.
delete from public.students where id in (select id from _todays_student_ids);
delete from public.profiles where id in (select id from _todays_student_ids);
delete from auth.users where id in (select id from _todays_student_ids);

-- Guardians left with nobody linked to them anymore. Their own
-- parent_student_links rows are already gone from the delete-by-
-- student_id above; these two are what's left to clean up.
delete from public.profiles where id in (select id from _orphaned_guardian_ids);
delete from auth.users where id in (select id from _orphaned_guardian_ids);

drop table _todays_student_ids;
drop table _orphaned_guardian_ids;
