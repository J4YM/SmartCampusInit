-- Seeds public.program_aliases (schema added by add_program_aliases_schema.sql,
-- but never populated — confirmed empty live, which is the real reason
-- "BSIT"/"BSBA" batch-enrolled rows couldn't find a matching section even
-- though one existed: it was just created under the full name "BS
-- Information Technology"/"BS Business Administration" instead (e.g. via
-- the Class Schedule tab's manual "Add Schedule" form, which takes a full
-- program name directly) — with the alias table empty, nothing bridged
-- the two spellings together for EnrollmentImportRepository.
-- fetchSectionCandidates (lib/data/enrollment_import_repository.dart) to
-- find it.
--
-- Mappings below are the ones confirmed to actually matter right now —
-- both spellings already have real sections live for each. ("BSA",
-- "BSPsych", "BSCS", "BSEd" from delete_mock_student_batch_upload.sql's
-- own comment are NOT real STI Baliuag programs — deliberately not
-- seeded here.) Add more rows the same way if another abbreviation turns
-- up a mismatch later.
--
-- Run in Supabase SQL Editor, after add_program_aliases_schema.sql.
-- `on conflict (alias) do update` makes re-running this safe.

insert into public.program_aliases (alias, canonical_program)
values
  ('BSIT', 'BS Information Technology'),
  ('BSBA', 'BS Business Administration'),
  ('BSHM', 'BS Hospitality Management'),
  ('BSTM', 'BS Tourism Management')
on conflict (alias) do update set
  canonical_program = excluded.canonical_program;
