-- "Delete" on the Discipline Officer Dashboard's Violation Preview panel
-- (packages/discipline_officer_module) soft-deletes a report instead of
-- removing it outright: pressing Delete stamps `archived_at`, which pulls
-- the report out of the active queue immediately. The officer can still
-- view (read-only) anything archived within the last 7 days via "View
-- Archived"; `DisciplineRepository.fetchArchivedViolations` lazily purges
-- (hard-deletes) anything older than that on each read, so no scheduled
-- job/cron is required.
--
-- Run in Supabase SQL Editor, after add_discipline_officer_schema.sql and
-- rls_discipline_demo_anon.sql.

alter table public.student_violations
  add column if not exists archived_at timestamptz;

create index if not exists student_violations_archived_at_idx
  on public.student_violations (archived_at)
  where archived_at is not null;

-- Archiving itself is a plain UPDATE (sets archived_at), already covered by
-- the existing `student_violations_anon_update_all` policy in
-- rls_discipline_demo_anon.sql. Only the lazy-purge hard delete needs a new
-- policy — same broad demo-mode shape as the existing select/update/insert
-- policies on this table (see rls_discipline_demo_anon.sql for the
-- production-hardening caveat that applies here too).
drop policy if exists "student_violations_anon_delete_all" on public.student_violations;
create policy "student_violations_anon_delete_all"
  on public.student_violations
  for delete
  to anon, authenticated
  using (true);
