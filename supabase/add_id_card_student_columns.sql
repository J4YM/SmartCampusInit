-- supabase/add_id_card_student_columns.sql
--
-- Two new plain columns on `students`, both entered directly on the
-- IT Technician registration form (see RfidRegistrationForm) — neither
-- depends on a linked parent-portal account existing:
--   guardian_contact_no — the ID card back's "Contact No" (emergency
--     contact) field. Distinct from the existing, derived `guardianName`
--     (sourced from parent_student_links elsewhere, out of scope here —
--     see this plan's Global Constraints) — this is a new, independently
--     entered and persisted column.
--   signature_path — Storage object path of the student's captured
--     signature, mirroring the existing photo_path column exactly.
--
-- Run in Supabase SQL Editor. Idempotent: safe to re-run.

alter table public.students
  add column if not exists guardian_contact_no text;

alter table public.students
  add column if not exists signature_path text;
