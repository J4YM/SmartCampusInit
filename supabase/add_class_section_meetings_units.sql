-- Adds class_section_meetings.units — the per Lecture/Laboratory unit
-- count the school's own "SCHEDULE OF CLASSES" template shows (e.g.
-- Lecture 2 units, Laboratory 1 unit for the same subject, which can
-- legitimately differ). Meeting-level, not subject-level: the
-- Confirmation of Faculty Loading (CFL) format already supplies a "Units"
-- value per Lecture/Laboratory row (see parseFacultyLoading in
-- lib/data/schedule_import/schedule_file_parser.dart) but it was being
-- parsed and then discarded — never persisted anywhere. Room Schedule
-- imports never carry a Units column at all, so those meetings simply
-- leave this null.
--
-- Run in Supabase SQL Editor. Idempotent: safe to re-run.

alter table public.class_section_meetings add column if not exists units numeric;
