-- Lets staff PERMANENTLY DELETE archived records from the dashboards'
-- archives (the "Delete selected" / "Delete all" actions).
--
-- Which archives can be deleted from, and what already permits it:
--   * Violation Queue -> View Archived (student_violations)      -- policy
--     "student_violations_anon_delete_all" (add_violation_archive_schema.sql)
--   * Guidance -> Student Archive (counseling_archive_logs)      -- policies
--     "counseling_logs_gc_delete" / "counseling_logs_anon_delete"
--   * Admin -> Academic Term -> Archived Terms (academic_terms)  -- policy
--     "academic_terms_all"; term_archive_records and
--     student_term_enrollments go with the term (on delete cascade)
--   * IT Technician -> Technical Issues -> View Archived
--     (technical_issue_reports)                                  -- THIS FILE
--
-- technical_issue_reports only had select / insert / update policies for
-- signed-in staff (the demo `anon` role has "technical_issue_reports_anon_all"),
-- so a real IT Technician or Admin session could not delete a resolved issue:
-- the delete silently matched no rows. This adds the missing delete policy,
-- limited to the same two roles that may already update reports.
-- (technical_issue_comments / notifications.report_id cascade with the report.)
--
-- Run in the Supabase SQL Editor. Idempotent.

drop policy if exists "technical_issue_reports_delete" on public.technical_issue_reports;
create policy "technical_issue_reports_delete"
  on public.technical_issue_reports
  for delete
  to authenticated
  using (current_user_role() in ('IT_Technician'::app_role, 'Admin'::app_role));
