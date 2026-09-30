-- One GPA snapshot per student per school-year/term, batch-uploaded from
-- the registrar's own "Candidates for Academic Honors" export (the same
-- report format the school already generates — see
-- lib/data/grade_import/grade_file_parser.dart's own doc comment for the
-- exact column layout it was built against).
--
-- Deliberately separate from `grades` (add_grades_schema.sql): that table
-- is one row per student PER SUBJECT SECTION on a 0-100 scale (`>=75`
-- passing) and is what the Registrar's own Grades tab reads/edits. This
-- file's source report is a GPA/honors-ranking summary on the Philippine
-- 1.00-5.00 scale (1.00 = best) with free-text course names that don't
-- reliably map to any `class_section_id` — a fundamentally different
-- shape, not a stricter version of the same data. This table exists
-- specifically to feed the behavioral-risk ML service's `current_gwa`/
-- `previous_gwa`/`failing_count` request fields (see
-- API_CONTRACT.md in the separate ML service repo) — "previous" is
-- whatever this same student's most recent OTHER (school_year, term) row
-- already says, so re-uploading a new term's report is what lets that
-- service detect a declining GPA trend.
--
-- Run in Supabase SQL Editor, after add_admin_dashboard_schema.sql
-- (students/profiles must already exist).

create table if not exists public.student_gpa_records (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students(id) on delete cascade,
  school_year text not null,
  term text not null,
  cumulative_gpa numeric(5,3),
  current_term_gpa numeric(5,3),
  failed_courses_count int not null default 0,
  transfer_units numeric(6,3),
  units_taken_cumulative numeric(6,3),
  units_taken_current_term numeric(6,3),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (student_id, school_year, term)
);

create index if not exists idx_student_gpa_records_student
  on public.student_gpa_records(student_id);

alter table public.student_gpa_records enable row level security;

-- Real Microsoft-OAuth accounts: Registrar/Admin only, matching `grades`'s
-- own policy shape (add_grades_schema.sql).
drop policy if exists "student_gpa_records_registrar_all" on public.student_gpa_records;
create policy "student_gpa_records_registrar_all"
  on public.student_gpa_records
  for all
  to authenticated
  using (current_user_role() in ('Registrar'::app_role, 'Admin'::app_role))
  with check (current_user_role() in ('Registrar'::app_role, 'Admin'::app_role));

-- Every demo account (lib/auth/static_demo_accounts.dart, including
-- registrar.demo) has no real Supabase Auth session, so it authenticates
-- as `anon` — matching this project's established pattern (see
-- add_enrollments_write_policy.sql).
drop policy if exists "student_gpa_records_anon_all" on public.student_gpa_records;
create policy "student_gpa_records_anon_all"
  on public.student_gpa_records
  for all
  to anon
  using (true)
  with check (true);

-- Read-only: GuidanceCounselorRepository.fetchStudentRiskAutofill /
-- fetchAllStudentsForBatchAnalysis (lib/data/guidance_counselor_repository.dart)
-- read this table to prefill the Single/Batch Student Analysis tabs'
-- current_gwa/previous_gwa/failing_count fields — a real (non-demo)
-- Guidance Counselor login needs SELECT here despite never writing to this
-- table (that stays Registrar/Admin-only above).
drop policy if exists "student_gpa_records_guidance_counselor_select" on public.student_gpa_records;
create policy "student_gpa_records_guidance_counselor_select"
  on public.student_gpa_records
  for select
  to authenticated
  using (current_user_role() = 'Guidance_Counselor'::app_role);
