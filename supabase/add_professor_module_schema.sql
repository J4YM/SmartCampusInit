-- Schema additions for the Professor Dashboard (packages/professor_module),
-- which was 100% mock data until now — no `class_sections` assignment
-- concept and no attendance-taking capability existed anywhere in this
-- project.
--
-- Two new tables:
--   1. class_assignments — which sections a professor teaches. Many-to-many
--      (a professor teaches several sections; a section has several subject
--      teachers), unlike the one-adviser-per-section shape `sections` itself
--      implies.
--   2. attendance_records — one row per student per class session. Written
--      by the new "Take Attendance" action on the Attendance tab (there was
--      previously no way to record attendance anywhere in this system, only
--      to display it).
--
-- The Conduct Report tab needs no new schema — it writes to the existing
-- `student_violations` / `handbook_offenses` tables, exactly like the
-- Discipline Officer dashboard already reads from.
--
-- Run in Supabase SQL Editor, after add_admin_dashboard_schema.sql (needs
-- `public.students`, `public.sections`) and add_kiosk_violation_insert_schema.sql
-- (needs pgcrypto enabled).

-- ---------------------------------------------------------------------------
-- 1. class_assignments
-- ---------------------------------------------------------------------------
create table if not exists public.class_assignments (
  id uuid primary key default gen_random_uuid(),
  professor_id uuid not null references public.profiles(id) on delete cascade,
  section_id uuid not null references public.sections(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (professor_id, section_id)
);

create index if not exists class_assignments_professor_id_idx
  on public.class_assignments (professor_id);

alter table public.class_assignments enable row level security;

drop policy if exists "class_assignments_anon_select" on public.class_assignments;
create policy "class_assignments_anon_select"
  on public.class_assignments
  for select
  to anon, authenticated
  using (true);

-- ---------------------------------------------------------------------------
-- 2. attendance_records
-- ---------------------------------------------------------------------------
-- `exception when duplicate_object then null` (the pattern used elsewhere
-- in this repo, e.g. add_admin_dashboard_schema.sql's audit_severity) only
-- guards against *this script* re-running — if a same-named enum already
-- existed from anywhere else with different labels, it silently keeps
-- those instead, and every insert below then fails with "invalid input
-- value for enum attendance_status". Adding each label individually
-- instead is safe either way: a fresh type gets all three, an existing one
-- gets only whatever it's actually missing.
do $$ begin
  create type public.attendance_status as enum ('Present', 'Absent', 'Late');
exception
  when duplicate_object then null;
end $$;

alter type public.attendance_status add value if not exists 'Present';
alter type public.attendance_status add value if not exists 'Absent';
alter type public.attendance_status add value if not exists 'Late';

create table if not exists public.attendance_records (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students(id) on delete cascade,
  section_id uuid not null references public.sections(id) on delete cascade,
  session_date date not null,
  status public.attendance_status not null,
  recorded_by uuid references public.profiles(id) on delete set null,
  recorded_at timestamptz not null default now(),
  -- One record per student per section per day — resubmitting "Take
  -- Attendance" for the same session overwrites rather than duplicates
  -- (see ProfessorRepository.submitAttendance's upsert).
  unique (student_id, section_id, session_date)
);

create index if not exists attendance_records_section_date_idx
  on public.attendance_records (section_id, session_date);

alter table public.attendance_records enable row level security;

drop policy if exists "attendance_records_anon_select" on public.attendance_records;
create policy "attendance_records_anon_select"
  on public.attendance_records
  for select
  to anon, authenticated
  using (true);

drop policy if exists "attendance_records_anon_insert" on public.attendance_records;
create policy "attendance_records_anon_insert"
  on public.attendance_records
  for insert
  to anon, authenticated
  with check (true);

drop policy if exists "attendance_records_anon_update" on public.attendance_records;
create policy "attendance_records_anon_update"
  on public.attendance_records
  for update
  to anon, authenticated
  using (true)
  with check (true);

-- ---------------------------------------------------------------------------
-- 3. Demo professor system profile — same reasoning and pattern as the
--    Kiosk system profile in add_kiosk_violation_insert_schema.sql: the
--    static `teacher.demo` account (lib/auth/static_demo_accounts.dart)
--    never calls Supabase Auth, so it has no real `profiles.id` to satisfy
--    `student_violations.reported_by` / `attendance_records.recorded_by` /
--    `class_assignments.professor_id`. This fixed id is referenced directly
--    by lib/ui/professor_connected_page.dart — keep the two in sync if it
--    ever changes. Real Microsoft-authenticated Teacher accounts use their
--    own actual profile id instead and never touch this row.
-- ---------------------------------------------------------------------------
do $$
declare
  v_professor_id uuid := '00000000-0000-4000-8000-000000000002';
begin
  insert into auth.users (
    id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, is_anonymous, created_at, updated_at
  )
  values (
    v_professor_id, '00000000-0000-0000-0000-000000000000'::uuid, 'authenticated', 'authenticated',
    'teacher.demo@baliuag.sti.edu.ph', crypt('demo-system-not-a-real-login', gen_salt('bf')), now(),
    '{"provider":"system","providers":["system"]}'::jsonb, '{}'::jsonb, false, now(), now()
  )
  on conflict (id) do nothing;

  insert into public.profiles (
    id, email, first_name, last_name, role, status, department, is_active, created_at
  )
  values (
    v_professor_id, 'teacher.demo@baliuag.sti.edu.ph',
    'Faculty', 'Member', 'Teacher'::app_role, 'approved'::approval_status,
    'Faculty', true, now()
  )
  on conflict (id) do update set
    role = excluded.role,
    status = excluded.status,
    department = excluded.department,
    is_active = excluded.is_active;
end $$;

-- Assigns the demo professor to a handful of existing sections so the
-- dashboard's Section List isn't empty out of the box. Safe to rerun
-- (unique constraint + on conflict).
insert into public.class_assignments (professor_id, section_id)
select '00000000-0000-4000-8000-000000000002'::uuid, s.id
from public.sections s
where s.name in ('BSIT-1A', 'BSIT-2A', 'BSHM-1A', 'BSBA-1A', 'BSTM-1A')
on conflict (professor_id, section_id) do nothing;

-- ---------------------------------------------------------------------------
-- 4. Conduct Report free-text notes
-- ---------------------------------------------------------------------------
-- `student_violations` has no per-incident free-text column of its own —
-- the Discipline Officer dashboard's "Comments" box (see
-- DisciplineRepository._toCaseModel) actually just displays
-- `handbook_offenses.penalty_info`, the offense's generic boilerplate, not
-- anything specific to one report. The Conduct Report tab's "Comments"
-- field needs somewhere real to persist, so this adds one; DisciplineRepository
-- now prefers it (when present) over the generic offense text.
alter table public.student_violations
  add column if not exists incident_notes text;
