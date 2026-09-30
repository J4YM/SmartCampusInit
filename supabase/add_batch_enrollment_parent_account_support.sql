-- Support for two batch-enrollment features added to
-- lib/data/enrollment_import_repository.dart's EnrollmentImportRepository:
--
--   1. Re-deriving each student's school email (lastname.NNNNNN@
--      baliuag.sti.edu.ph, matching handle_new_auth_user's own regex in
--      add_oauth_role_approval_schema.sql) on every batch upload, even for
--      an already-existing student row — the batch file is the source of
--      truth, so a re-upload always overwrites whatever email is on file
--      (including one set by a prior self-registration) rather than
--      trusting it might already be correct.
--   2. Auto-creating (or linking to an existing) Parent account from the
--      file's "Parent/s Email" / "Guardian/s Email" columns, via
--      `parent_student_links` — mirrors the anonymous-sign-in primitive
--      StudentsRepository.create() already uses for students (see that
--      file's own doc comment on why: no service-role API is available
--      from a client app to mint an auth identity any other way).
--
-- Both run under the same `anon` session every demo account uses (no real
-- Supabase Auth session — see add_enrollments_write_policy.sql's own
-- comment on this project's established pattern), so both need explicit
-- anon policies or they silently write nothing:
--
--   - `profiles` has no anon UPDATE policy at all today (only
--     "update own row", authenticated — rls_student_self_insert.sql). That
--     already silently no-ops EnrollmentImportRepository's existing-
--     student-update branch in the demo environment; this policy fixes
--     that as a side effect of fixing the same gap for the new email/
--     guardian-name overwrite.
--   - `parent_student_links` has SELECT policies only
--     (rls_students_list_anon.sql) — nothing lets a batch upload create
--     the link row itself.
--
-- Run in Supabase SQL Editor. Idempotent: safe to re-run.

drop policy if exists "profiles_anon_update" on public.profiles;
create policy "profiles_anon_update"
  on public.profiles
  for update
  to anon
  using (true)
  with check (true);

drop policy if exists "parent_student_links_anon_insert" on public.parent_student_links;
create policy "parent_student_links_anon_insert"
  on public.parent_student_links
  for insert
  to anon
  with check (true);

drop policy if exists "parent_student_links_authenticated_insert" on public.parent_student_links;
create policy "parent_student_links_authenticated_insert"
  on public.parent_student_links
  for insert
  to authenticated
  with check (true);
