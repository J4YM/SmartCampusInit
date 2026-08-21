-- Multi-reader floor attendance infrastructure: a registry of physical RFID
-- readers (each identified by a stable USB vendor/product/serial descriptor,
-- not a mutable OS device path) and the raw tap events they produce. This is
-- entirely separate from `attendance_records` (packages/professor_module) —
-- taps here are a supplementary signal a teacher cross-checks, never an
-- automatic write to the teacher's own manual attendance record.
--
-- Run in Supabase SQL Editor, after add_professor_module_schema.sql (needs
-- `public.students`) and add_oauth_role_approval_schema.sql (needs
-- `public.profiles`, referenced only in comments below).

-- ---------------------------------------------------------------------------
-- 1. Reader registry
-- ---------------------------------------------------------------------------

create table if not exists public.rfid_readers (
  id uuid primary key default gen_random_uuid(),
  label text not null,
  -- Stable hardware identity (e.g. "VID:PID:SERIAL" or a simulator-assigned
  -- id) — NOT an OS-level device path, which can change across reconnects.
  usb_serial text not null,
  location text,
  is_kiosk_reader boolean not null default false,
  created_at timestamptz not null default now(),
  last_seen_at timestamptz
);

create unique index if not exists rfid_readers_usb_serial_key
  on public.rfid_readers (usb_serial);

alter table public.rfid_readers enable row level security;

-- Demo-mode: same broad anon access as the rest of this project's tables
-- (see rls_discipline_demo_anon.sql) — tighten before production.
drop policy if exists "rfid_readers_anon_all" on public.rfid_readers;
create policy "rfid_readers_anon_all"
  on public.rfid_readers
  for all
  to anon, authenticated
  using (true)
  with check (true);

-- ---------------------------------------------------------------------------
-- 2. Raw tap event log
-- ---------------------------------------------------------------------------

do $$ begin
  create type public.rfid_tap_direction as enum ('in', 'out');
exception
  when duplicate_object then null;
end $$;

create table if not exists public.rfid_tap_events (
  id uuid primary key default gen_random_uuid(),
  reader_id uuid not null references public.rfid_readers(id) on delete cascade,
  rfid_uid text not null,
  student_id uuid references public.students(id) on delete set null,
  tap_direction public.rfid_tap_direction not null,
  tapped_at timestamptz not null default now()
);

create index if not exists rfid_tap_events_student_day_idx
  on public.rfid_tap_events (student_id, tapped_at desc);

create index if not exists rfid_tap_events_reader_idx
  on public.rfid_tap_events (reader_id, tapped_at desc);

alter table public.rfid_tap_events enable row level security;

drop policy if exists "rfid_tap_events_anon_all" on public.rfid_tap_events;
create policy "rfid_tap_events_anon_all"
  on public.rfid_tap_events
  for all
  to anon, authenticated
  using (true)
  with check (true);

-- ---------------------------------------------------------------------------
-- 3. record_rfid_tap — the one entry point the central reader-service (and
--    the dev-mode simulator) calls. Owns the in/out toggle logic and the
--    reader heartbeat update in a single transaction so that logic lives in
--    one place, not duplicated in every client that could produce a tap.
-- ---------------------------------------------------------------------------

create or replace function public.record_rfid_tap(
  p_reader_usb_serial text,
  p_rfid_uid text,
  p_tapped_at timestamptz default now()
)
returns table (
  tap_id uuid,
  reader_id uuid,
  student_id uuid,
  tap_direction public.rfid_tap_direction,
  tapped_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_reader_id uuid;
  v_student_id uuid;
  v_last_direction public.rfid_tap_direction;
  v_next_direction public.rfid_tap_direction;
  v_tap_id uuid;
begin
  -- 1. Resolve the reader by its stable hardware serial, and stamp its
  --    heartbeat in the same transaction — a reader that never taps still
  --    needs `last_seen_at` updated some other way (a periodic no-op ping),
  --    but every real tap doubles as proof of life for free.
  select id into v_reader_id
    from public.rfid_readers
    where usb_serial = p_reader_usb_serial;

  if v_reader_id is null then
    raise exception 'Unknown reader serial: %', p_reader_usb_serial;
  end if;

  update public.rfid_readers
    set last_seen_at = p_tapped_at
    where id = v_reader_id;

  -- 2. Resolve the card to a student (a tap from an unregistered card is
  --    still logged — student_id stays null — rather than silently dropped,
  --    so a bad/unlinked card shows up as a data-quality signal instead of
  --    disappearing).
  select id into v_student_id
    from public.students
    where rfid_uid = p_rfid_uid;

  -- 3. Toggle in/out per student per calendar day: this student's most
  --    recent tap today decides the next direction. No prior tap today (or
  --    an unresolved card) defaults to 'in'.
  if v_student_id is not null then
    select tap_direction into v_last_direction
      from public.rfid_tap_events
      where student_id = v_student_id
        and tapped_at::date = p_tapped_at::date
      order by tapped_at desc
      limit 1;
  end if;

  v_next_direction := case
    when v_last_direction = 'in' then 'out'::public.rfid_tap_direction
    else 'in'::public.rfid_tap_direction
  end;

  -- 4. Write the event.
  insert into public.rfid_tap_events (
    reader_id, rfid_uid, student_id, tap_direction, tapped_at
  )
  values (
    v_reader_id, p_rfid_uid, v_student_id, v_next_direction, p_tapped_at
  )
  returning id into v_tap_id;

  return query
    select v_tap_id, v_reader_id, v_student_id, v_next_direction, p_tapped_at;
end;
$$;

revoke all on function public.record_rfid_tap(text, text, timestamptz) from public;
grant execute on function public.record_rfid_tap(text, text, timestamptz)
  to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 4. Seed a starter reader roster — the kiosk's own reader plus a few floor
--    readers so the simulator has something to pick from immediately. Safe
--    to edit/extend later via the RFID Mapping admin page.
-- ---------------------------------------------------------------------------

insert into public.rfid_readers (label, usb_serial, location, is_kiosk_reader)
values
  ('Main Kiosk', 'KIOSK-MAIN-001', 'Ground Floor — Lobby', true),
  ('Floor 1 Reader', 'FLOOR-1-READER-001', 'Floor 1 — Main Hallway', false),
  ('Floor 2 Reader', 'FLOOR-2-READER-001', 'Floor 2 — Main Hallway', false),
  ('Floor 3 Reader', 'FLOOR-3-READER-001', 'Floor 3 — Main Hallway', false)
on conflict (usb_serial) do nothing;
