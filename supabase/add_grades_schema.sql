-- supabase/add_grades_schema.sql
--
-- One grade per student per class_sections offering (subject + section +
-- school year + term, via the existing class_sections table — no separate
-- school_year/term/section columns needed here). Registrar/Admin-only, no
-- student/parent access — unlike good_moral_requests, nothing else needs a
-- narrower insert-only policy for this table.
--
-- Run in Supabase SQL Editor, after add_subjects_enrollments_schema.sql.

create table if not exists public.grades (
  id uuid primary key default gen_random_uuid(),
  class_section_id uuid not null references public.class_sections(id),
  student_id uuid not null references public.students(id),
  grade numeric(5,2) not null check (grade >= 0 and grade <= 100),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (student_id, class_section_id)
);

create index if not exists idx_grades_class_section on public.grades(class_section_id);
create index if not exists idx_grades_student on public.grades(student_id);

alter table public.grades enable row level security;

drop policy if exists "grades_registrar_all" on public.grades;
create policy "grades_registrar_all"
on public.grades for all
to authenticated
using (current_user_role() in ('Registrar'::app_role, 'Admin'::app_role))
with check (current_user_role() in ('Registrar'::app_role, 'Admin'::app_role));
