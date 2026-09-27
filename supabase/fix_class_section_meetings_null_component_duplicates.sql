-- Root cause of the "duplicate subjects" bug reported across multiple
-- BSTM sections — every visible field (day/time/room/instructor) is
-- byte-for-byte identical between the "duplicate" rows, unlike every
-- earlier duplicate bug fixed this session (which always differed in
-- spelling/formatting, e.g. "Mr. Jayson Villafuerte" vs "Jayson V.
-- Villafuerte"). Confirmed via a direct query: both duplicate rows share
-- the exact same class_section_id, component, day, and sequence — only
-- their own `id`/`created_at` differ. That means the "upsert" in
-- ScheduleImportRepository.commitMeetings never collided at all.
--
-- The unique index that's supposed to make that upsert idempotent,
--
--   create unique index ... on class_section_meetings
--     (class_section_id, component, day, sequence);
--
-- never actually applies whenever `component` is null — standard
-- Postgres UNIQUE indexes treat NULL as distinct from every other NULL,
-- so two rows with the same (class_section_id, day, sequence) but
-- component = NULL never collide, and `onConflict` silently falls
-- through to a plain INSERT every time. `component` IS null for every
-- subject with no Lecture/Laboratory split (GE subjects, NSTP, PATHFIT,
-- Risk Management, etc. — exactly the subjects reported duplicated;
-- subjects that DO split into Lecture/Laboratory rows were never
-- affected, since their `component` is never null). Re-processing the
-- same meeting even once (a re-upload, or the same offering appearing on
-- more than one sheet within one file) has been silently duplicating it
-- since this index was added.
--
-- Fix: NULLS NOT DISTINCT (Postgres 15+) makes NULL compare equal to
-- NULL for this index specifically, so the exact same upsert now
-- collides and updates in place as originally intended. No Dart code
-- change is needed — commitMeetings' onConflict target was already
-- correct.
--
-- Run in Supabase SQL Editor. Idempotent: safe to re-run.
--
-- Cleanup runs FIRST, then the index rebuild — rebuilding the unique
-- index before removing the duplicates it should have prevented fails
-- outright ("could not create unique index ... is duplicated"), since
-- the existing duplicate rows would themselves violate the new,
-- correctly-behaving constraint.

-- Cleanup: removes the duplicate rows this bug already created, keeping
-- only the most recently created row per real (class_section_id,
-- component, day, sequence) slot. Window-function PARTITION BY (unlike a
-- plain UNIQUE index) already treats NULL component values as equal, so
-- this correctly groups the null-component duplicates the bug produced
-- without needing a COALESCE workaround.
delete from public.class_section_meetings csm
where csm.id in (
  select id from (
    select
      id,
      row_number() over (
        partition by class_section_id, component, day, sequence
        order by created_at desc, id desc
      ) as rn
    from public.class_section_meetings
  ) ranked
  where rn > 1
);

drop index if exists idx_class_section_meetings_unique_slot;
create unique index idx_class_section_meetings_unique_slot
  on public.class_section_meetings (class_section_id, component, day, sequence)
  nulls not distinct;
