-- The Professor dashboard's "Excuse" button saves status 'Excuse', but the
-- attendance_status enum (add_professor_module_schema.sql) only has Present,
-- Absent and Late, so excusing a student failed with:
--   invalid input value for enum attendance_status: "Excuse"
--
-- Run in Supabase SQL Editor — on its own, as a single statement (Postgres
-- does not allow a new enum value to be used in the transaction that adds it).
-- Idempotent.

alter type public.attendance_status add value if not exists 'Excuse';
