-- supabase/add_class_section_meetings_schema.sql
--
-- class_sections today assumes one room + one day-set + one time range
-- per offering. Real school schedule data needs multiple meetings per
-- offering (a Lecture row and a Laboratory row, each with its own
-- room/day/time; a single component can meet on two different days at
-- two different times). This table carries that per-meeting detail;
-- class_sections.room/schedule_days/start_time/end_time stay as they
-- are (a compatibility shim for the existing one-row-at-a-time manual
-- entry form) and are not touched by this migration.
--
-- Run in Supabase SQL Editor. Idempotent: safe to re-run.

create table if not exists public.class_section_meetings (
  id uuid primary key default gen_random_uuid(),
  class_section_id uuid not null references public.class_sections(id) on delete cascade,
  component text check (component in ('Lecture', 'Laboratory')),
  day text not null check (day in ('M','T','W','TH','F','S')),
  start_time time not null,
  end_time time not null,
  room text not null,
  created_at timestamptz not null default now()
);

create index if not exists idx_class_section_meetings_class_section
  on public.class_section_meetings(class_section_id);

alter table public.class_section_meetings enable row level security;

-- Catalog-like data (same reasoning as class_sections/subjects): visible
-- to anon and authenticated alike.
drop policy if exists "class_section_meetings_anon_select" on public.class_section_meetings;
create policy "class_section_meetings_anon_select"
on public.class_section_meetings for select
to anon
using (true);

drop policy if exists "class_section_meetings_authenticated_select" on public.class_section_meetings;
create policy "class_section_meetings_authenticated_select"
on public.class_section_meetings for select
to authenticated
using (true);

-- Write access: Registrar/Admin only for now (matches class_sections'
-- existing write shape). The Scheduling Officer role does not exist yet
-- in this plan — a later plan adds 'Scheduling_Officer'::app_role to
-- this policy alongside introducing that role.
drop policy if exists "class_section_meetings_write" on public.class_section_meetings;
create policy "class_section_meetings_write"
on public.class_section_meetings for all
to authenticated
using (current_user_role() in ('Registrar'::app_role, 'Admin'::app_role))
with check (current_user_role() in ('Registrar'::app_role, 'Admin'::app_role));

-- Appended to the end of add_class_section_meetings_schema.sql.
-- Placeholder professors (e.g. "New IT Faculty 2") get a real profiles
-- row with this status rather than 'approved'/'pending' — see
-- lib/data/schedule_import_repository.dart's resolveProfessorId.
alter type public.approval_status add value if not exists 'Placeholder';
