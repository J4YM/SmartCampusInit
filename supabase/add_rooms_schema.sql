-- A real room inventory — previously the only "room" data in this schema
-- was `room_aliases` (a free-text spelling-correction lookup with no
-- capacity, building, or type), and room values only ever arrived from a
-- manually-uploaded CFL/Room Schedule file. This table is what
-- RoomAssignmentRepository.autoAssignRooms (lib/data/room_assignment_repository.dart)
-- allocates from to auto-generate room assignments instead — see that
-- file's own doc comment for the full design.
--
-- Run in Supabase SQL Editor, after add_scheduling_officer_role.sql.
-- Seeded below with STI Baliuag's real room list (from a campus directory
-- photo) — capacities are PLACEHOLDERS (not from that photo, which has no
-- capacity info) and should be corrected via Table Editor once you have
-- the real numbers; everything else (room numbers, building, type, the
-- GYM's PE-only restriction) is as given.

create table if not exists public.rooms (
  id uuid primary key default gen_random_uuid(),
  room_number text not null unique,
  building text,
  capacity int not null check (capacity > 0),
  -- Free text, not an enum — only "does this say Lecture or not" is ever
  -- checked (see room_assignment_algorithm.dart's _roomTypeMatches), so a
  -- new lab-ish type (e.g. "Science Laboratory") needs no schema change to
  -- become eligible for Laboratory meetings.
  room_type text not null,
  created_at timestamptz not null default now()
);

-- `create table if not exists` is a no-op if this table already exists
-- from an earlier run of this file (e.g. before `restricted_subject_keyword`
-- was added below) — this additive alter makes re-running safe regardless
-- of which columns are already there, same pattern as
-- add_risk_assessments_schema.sql.
alter table public.rooms
  -- When set, this room is eligible ONLY for a meeting whose subject
  -- title/code contains this keyword (case-insensitive) — e.g. the GYM is
  -- usable for PE classes only, not every other "Laboratory"-component
  -- meeting a plain room_type match would otherwise let in. Null (the
  -- common case) means no such restriction — matched by room_type alone.
  add column if not exists restricted_subject_keyword text;

create index if not exists idx_rooms_room_type on public.rooms(room_type);

alter table public.rooms enable row level security;

-- Catalog-like data (same reasoning as subjects/class_sections): visible
-- to anon and authenticated alike.
drop policy if exists "rooms_anon_select" on public.rooms;
create policy "rooms_anon_select"
  on public.rooms
  for select
  to anon
  using (true);

drop policy if exists "rooms_authenticated_select" on public.rooms;
create policy "rooms_authenticated_select"
  on public.rooms
  for select
  to authenticated
  using (true);

-- Write access: Registrar/Scheduling_Officer/Admin, matching
-- class_section_meetings' own write policy shape
-- (add_scheduling_officer_role.sql).
drop policy if exists "rooms_staff_write" on public.rooms;
create policy "rooms_staff_write"
  on public.rooms
  for all
  to authenticated
  using (current_user_role() in (
    'Registrar'::app_role, 'Scheduling_Officer'::app_role, 'Admin'::app_role
  ))
  with check (current_user_role() in (
    'Registrar'::app_role, 'Scheduling_Officer'::app_role, 'Admin'::app_role
  ));

-- Every demo account (lib/auth/static_demo_accounts.dart, including
-- scheduling.demo) has no real Supabase Auth session, so it authenticates
-- as `anon` — matching this project's established pattern (see
-- add_enrollments_write_policy.sql).
drop policy if exists "rooms_anon_write" on public.rooms;
create policy "rooms_anon_write"
  on public.rooms
  for all
  to anon
  using (true)
  with check (true);

-- ---------------------------------------------------------------------------
-- Seed data — STI Baliuag's real rooms. `on conflict (room_number) do
-- update` makes re-running this safe (e.g. after fixing a capacity number)
-- without duplicating rows.
-- ---------------------------------------------------------------------------

insert into public.rooms (room_number, building, capacity, room_type, restricted_subject_keyword)
values
  ('LR 101', 'Main', 40, 'Lecture', null),
  ('LR 102', 'Main', 40, 'Lecture', null),
  ('LR 104', 'Main', 40, 'Lecture', null),
  ('LR 201', 'Main', 40, 'Lecture', null),
  ('LR 202', 'Main', 40, 'Lecture', null),
  ('LR 203', 'Main', 40, 'Lecture', null),
  ('LR 204', 'Main', 40, 'Lecture', null),
  ('LR 205', 'Main', 40, 'Lecture', null),
  ('LR 207', 'Main', 40, 'Lecture', null),
  ('LR 208', 'Main', 40, 'Lecture', null),
  ('LR 301', 'Main', 40, 'Lecture', null),
  ('LR 302', 'Main', 40, 'Lecture', null),
  ('LR 303', 'Main', 40, 'Lecture', null),
  ('LR 304', 'Main', 40, 'Lecture', null),
  ('LR 305', 'Main', 40, 'Lecture', null),
  -- Regular lecture rooms, same as any LR — per explicit instruction.
  ('AVR 1', 'Main', 60, 'Lecture', null),
  ('AVR 2', 'Main', 60, 'Lecture', null),
  -- PE classes only — see `restricted_subject_keyword`'s own doc comment.
  -- Matches against the subject's title/code, so this assumes PE subjects
  -- have "PE" somewhere in their code or title (e.g. "PE 1", "PE-101");
  -- adjust the keyword here if STI Baliuag's actual subject codes differ.
  ('GYM', 'Main', 150, 'Laboratory', 'PE'),
  ('Computer Lab 1', 'Main', 30, 'Computer Laboratory', null),
  ('Computer Lab 2', 'Main', 30, 'Computer Laboratory', null),
  ('Computer Lab 3', 'Main', 30, 'Computer Laboratory', null),
  ('Annex 303', 'Annex', 40, 'Lecture', null),
  ('Annex 304', 'Annex', 40, 'Lecture', null),
  ('Annex 305', 'Annex', 40, 'Lecture', null),
  ('Kitchen Lab 1', 'Annex', 25, 'Laboratory', null),
  ('Mock Hotel', 'Annex', 20, 'Laboratory', null)
on conflict (room_number) do update set
  building = excluded.building,
  capacity = excluded.capacity,
  room_type = excluded.room_type,
  restricted_subject_keyword = excluded.restricted_subject_keyword;
