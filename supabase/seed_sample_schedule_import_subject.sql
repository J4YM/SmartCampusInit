-- supabase/seed_sample_schedule_import_subject.sql
--
-- Optional. scripts/generate_sample_schedule_xlsx.dart's sample file
-- carries "Human Computer Interaction" with no course code (the
-- Confirmation of Faculty Loading format never has one) — with no
-- existing subject to match by title, ScheduleImportRepository.
-- resolveSubjectId correctly refuses to invent a code for a brand-new
-- subject, so importing the sample as-is reports one "could not
-- resolve" error and commits nothing. That's the intended, real
-- behavior for a genuinely new subject — this file exists only so you
-- can ALSO see the full successful path (offering created, both
-- meetings committed, visible on the Professor's My Schedule tab) by
-- pre-seeding a match first.
--
-- Run in Supabase SQL Editor, before importing the sample file, only if
-- you want the full success path. Idempotent: safe to re-run.

insert into public.subjects (code, title)
values ('CITE1099-DEMO', 'Human Computer Interaction')
on conflict (code) do nothing;
