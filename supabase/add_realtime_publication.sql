-- Enables Supabase Realtime change events on `student_violations`, so the
-- Discipline Officer dashboard (lib/ui/discipline_officer_connected_page.dart)
-- can live-refresh its Approval Queue when a violation is inserted (e.g. from
-- the Virtual Admission Kiosk, see add_kiosk_violation_insert_schema.sql) or
-- updated (Validate/Modify/Deny) by anyone, without a manual page reload.
--
-- Idempotent: `alter publication ... add table` errors if the table is
-- already a publication member, so this checks pg_publication_tables first.
--
-- Run in Supabase SQL Editor.

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'student_violations'
  ) then
    alter publication supabase_realtime add table public.student_violations;
  end if;
end $$;
