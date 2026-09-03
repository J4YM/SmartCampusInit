-- Adds subjects/class_sections/enrollments — see
-- docs/superpowers/specs/2026-09-04-irregular-students-schema-design.md
-- for the full design rationale (Approach A: uniform enrollment).
--
-- Purely additive: no existing table or column changes. Safe to run
-- alongside every existing feature (Registrar, RFID kiosk, Discipline
-- Officer, Professor modules) with zero behavior change to any of them —
-- nothing today reads these tables yet.
--
-- Run in Supabase SQL Editor. Idempotent: safe to re-run.

create table if not exists public.subjects (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  title text not null,
  program text,
  year_level int,
  created_at timestamptz not null default now()
);

create table if not exists public.class_sections (
  id uuid primary key default gen_random_uuid(),
  subject_id uuid not null references public.subjects(id),
  section_id uuid not null references public.sections(id),
  professor_id uuid references public.profiles(id),
  room text,
  schedule_days text[],
  start_time time,
  end_time time,
  school_year text not null,
  term text not null,
  created_at timestamptz not null default now()
);

create index if not exists idx_class_sections_subject on public.class_sections(subject_id);
create index if not exists idx_class_sections_section on public.class_sections(section_id);

create table if not exists public.enrollments (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students(id),
  class_section_id uuid not null references public.class_sections(id),
  status text not null default 'Active',
  created_at timestamptz not null default now(),
  unique (student_id, class_section_id)
);

create index if not exists idx_enrollments_student on public.enrollments(student_id);
create index if not exists idx_enrollments_class_section on public.enrollments(class_section_id);

-- RLS. `subjects`/`class_sections` are catalog-like data (which subjects
-- exist, which offerings exist) — granted to both `anon` and
-- `authenticated`, matching this repo's existing convention for reference
-- tables the anonymous self-registration flow may need to resolve (see
-- supabase/rls_sections_select.sql). `enrollments` ties a specific
-- student to specific offerings, so it's kept to `authenticated` only.
alter table public.subjects enable row level security;
alter table public.class_sections enable row level security;
alter table public.enrollments enable row level security;

drop policy if exists "subjects_anon_select" on public.subjects;
create policy "subjects_anon_select"
on public.subjects for select
to anon
using (true);

drop policy if exists "subjects_authenticated_select" on public.subjects;
create policy "subjects_authenticated_select"
on public.subjects for select
to authenticated
using (true);

drop policy if exists "class_sections_anon_select" on public.class_sections;
create policy "class_sections_anon_select"
on public.class_sections for select
to anon
using (true);

drop policy if exists "class_sections_authenticated_select" on public.class_sections;
create policy "class_sections_authenticated_select"
on public.class_sections for select
to authenticated
using (true);

drop policy if exists "enrollments_authenticated_select" on public.enrollments;
create policy "enrollments_authenticated_select"
on public.enrollments for select
to authenticated
using (true);
