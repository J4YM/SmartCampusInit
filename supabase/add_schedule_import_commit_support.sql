-- supabase/add_schedule_import_commit_support.sql
--
-- Two fixes needed to make the schedule import feature (and the existing
-- manual "Add Class Schedule" form) actually work end to end, including
-- for demo accounts:
--
-- 1. class_section_meetings has no `sequence` column, but
--    lib/data/schedule_import_repository.dart's commitMeetings() has
--    always upserted with `onConflict: 'class_section_id,component,day,
--    sequence'` — flagged as a known gap in that method's own comment
--    when it was first written. Without the column and a matching unique
--    constraint, that upsert fails outright (Postgres rejects an
--    onConflict target with no matching unique index).
--
-- 2. Neither class_sections (INSERT) nor class_section_meetings (INSERT/
--    UPDATE/DELETE) has an anon write policy. Every demo account
--    (lib/auth/static_demo_accounts.dart, including registrar.demo) is a
--    purely client-side check with no real Supabase Auth session — see
--    add_students_update_policy.sql's identical reasoning — so both the
--    existing manual Class Schedule form's "Save" and the new schedule
--    import flow silently write nothing when signed in as registrar.demo
--    today. Tighten before production.
--
-- Run in Supabase SQL Editor, after add_class_sections_insert_policy.sql
-- and add_class_section_meetings_schema.sql. Idempotent: safe to re-run.

alter table public.class_section_meetings
  add column if not exists sequence int not null default 0;

drop index if exists idx_class_section_meetings_unique_slot;
create unique index idx_class_section_meetings_unique_slot
  on public.class_section_meetings (class_section_id, component, day, sequence);

drop policy if exists "class_sections_anon_insert" on public.class_sections;
create policy "class_sections_anon_insert"
on public.class_sections for insert
to anon
with check (true);

drop policy if exists "class_section_meetings_anon_write" on public.class_section_meetings;
create policy "class_section_meetings_anon_write"
on public.class_section_meetings for all
to anon
using (true)
with check (true);
