-- supabase/add_profiles_employee_id_schema.sql
--
-- The Registrar's Classes+Professor list export identifies each
-- professor by an "Instructor ID" (a school employee ID, e.g.
-- "02000324231") that profiles has no column for today. Needed by
-- lib/data/schedule_import_repository.dart's resolveProfessorId to
-- match professors when the Classes+Professor list is the source (CFL/
-- Room Schedule carry no such ID and match by name instead).
--
-- Run in Supabase SQL Editor. Idempotent: safe to re-run.

alter table public.profiles
  add column if not exists employee_id text;

do $$ begin
  alter table public.profiles add constraint profiles_employee_id_key unique (employee_id);
exception
  when duplicate_object then null;
end $$;
