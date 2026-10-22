# Endorsements and Guidance Privacy Implementation Plan (piece 1 of 4)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Escalation with Endorsements (any student, no violation needed), route student referrals to the Discipline Officer, hide sanctions from Guidance, and retitle the Guidance dashboard.

**Architecture:** Keep the `escalation_reports` table and the `EscalationReportModel` / `EscalationRepository` / `decide_escalation_report` names (YAGNI: renaming them touches ten files for no behaviour). Add a `kind` and optional `referral_id` to the table, relax what a counseling-only report needs, and change the user-facing words to "Endorsement". The DO's tab lists all students; Guidance reads an endorsed student's violation history through a column-limited SECURITY DEFINER function. Referrals move to the DO module.

**Tech Stack:** Flutter (monorepo, local packages), Supabase Postgres RLS + SECURITY DEFINER functions, `test/support/recording_server.dart` for repository tests, widget tests.

**Spec:** `docs/superpowers/specs/2026-10-22-do-owns-investigations-and-endorsements-design.md` (goals 2-7). Pieces 2-4 (investigations to the DO, Good Moral, ML access) get their own plans; this plan does not touch investigations, Good Moral or ML.

## Global Constraints

- Real staff accounts are `authenticated`; static demo logins are `anon` and cannot call signed-in-only functions. Verify with `demo.*@baliuag.sti.edu.ph`.
- Netlify web build is Flutter 3.24.5: use `Color.withOpacity`, never `withValues`.
- Database role names are unchanged (`Guidance_Counselor`, `Discipline_Officer`); only labels change.
- SQL is an idempotent file in `supabase/` run by the user in the Supabase SQL editor; never `git add -A supabase` (the user has untracked scripts there); stage explicit paths.
- Endorsement "violation history" = offense description, category, incident date and status only. Never sanction, override reason, findings or notes.
- Existing escalation rows become endorsements unchanged (`Pending_GC` / `Approved` / `Rejected`; `violation_ids` may be empty).
- Root `flutter test` is the reliable suite; run package tests by path from the repo root.

## Review Focus

- A counseling-only endorsement must approve without a parent message, channels or an intervention row being created.
- An endorsement for a student with zero violations must work end to end (DO files it, Guidance sees "No violations on record").
- Guidance asking for the history of a student who was never endorsed must get nothing, not an error leak.
- A referral already `Closed` or already linked to an endorsement must not be endorsed twice.
- A student with hundreds of peers: the DO's student list must page and search server-side, not load everyone.

## File Structure

- Create `supabase/add_endorsements.sql`: schema, history function, referral routing, sanction-log removal.
- Create `supabase/test_endorsements.sql`: SQL assertions in the style of `supabase/test_guidance_investigations.sql`.
- Modify `packages/discipline_officer_module/lib/models/escalation_report_model.dart`: `kind`, `referralId`, labels.
- Modify `lib/data/escalation_repository.dart`: `issue`, `decide`, `fetchViolationHistory`.
- Modify `packages/discipline_officer_module/lib/pages/dashboard/parental_intervention_view.dart` into the Endorsements tab (rename the file to `endorsements_view.dart`).
- Modify `packages/discipline_officer_module/lib/pages/dashboard/discipline_officer_dashboard_page.dart` and `lib/ui/discipline_officer_connected_page.dart`: tab label, student list source, Referrals tab.
- Create `packages/discipline_officer_module/lib/pages/referrals/referrals_view.dart` (moved from Guidance) and the model with it.
- Modify `packages/guidance_counselor_module/...` dashboard, escalation view, archive models; delete its `referrals/` folder.

---

### Task 1: Database migration

**Files:**
- Create: `supabase/add_endorsements.sql`
- Create: `supabase/test_endorsements.sql`

**Interfaces:**
- Produces (SQL, used by Tasks 2-5):
  - `escalation_reports.kind text` in `('counseling','parent_intervention','both')`, default `'parent_intervention'`.
  - `escalation_reports.referral_id uuid references student_referrals(id)`, unique where not null.
  - `public.endorsement_violation_history(p_student_id uuid) returns table (violation_id uuid, offense text, category text, incident_at timestamptz, status text)`; callable by `authenticated`; returns rows only for Guidance/Admin/DO callers AND only when an `escalation_reports` row exists for that student; no sanction columns.
  - `decide_escalation_report(...)` unchanged signature; a `kind = 'counseling'` approval skips the `parent_interventions` / `email_outbox` / parent meeting.

- [ ] **Step 1: Write `supabase/test_endorsements.sql`** asserting, inside a rolled-back transaction as in `test_guidance_investigations.sql`: (a) a counseling-only report with empty `channels` and empty `message` inserts and approves with no `parent_interventions` row; (b) the history function returns 0 rows for an un-endorsed student and the offense/date/status rows for an endorsed one, and the returned columns contain no `sanction`; (c) a second report with the same `referral_id` is rejected; (d) after the migration `counseling_archive_logs` has no `log_type = 'sanction'` rows and the trigger `log_sanction_to_archive` is gone; (e) a Guidance caller cannot `select` from `sanctions`.
- [ ] **Step 2: Run it** in the Supabase SQL editor against the pre-migration database. Expected: FAIL on (a).
- [ ] **Step 3: Write `supabase/add_endorsements.sql`**, idempotent:
  1. Add `kind` and `referral_id` (unique partial index); drop `escalation_reports_channels_check` and re-add it allowing empty arrays; make `message` default `''`; allow `kind` check.
  2. `create or replace function public.endorsement_violation_history(uuid)` as described, `security definer`, `set search_path = public`, `revoke ... from public, anon`, `grant ... to authenticated`.
  3. Replace `decide_escalation_report` (drop the 7-argument version first, as `add_escalation_meeting_and_sanction_log.sql` did) so a counseling-only report skips the parent branch; the Discipline Officer notification text says "endorsement".
  4. Referrals: change `student_referrals_staff_select` and `staff_update` to `Admin` and `Discipline_Officer` only; change `trg_notify_student_referral` to notify `'Discipline_Officer'::app_role` and say "Review it under Referrals."; when an endorsement with a `referral_id` is inserted, set that referral `In_Progress` and `handled_by = auth.uid()` (a trigger on `escalation_reports`).
  5. Remove sanction logs: `drop trigger if exists log_sanction_to_archive on public.sanctions; drop function if exists public.trg_log_sanction_to_archive();` `delete from public.counseling_archive_logs where log_type = 'sanction';` then recreate `counseling_archive_logs_type_check` without `'sanction'`.
  6. Remove Guidance from `sanctions_staff_select` (keep Admin, DO, Registrar).
- [ ] **Step 4: Re-run the test script.** Expected: all assertions pass, and the migration runs twice without error.
- [ ] **Step 5: Commit** `git add supabase/add_endorsements.sql supabase/test_endorsements.sql` (explicit paths).

### Task 2: Data layer

**Files:**
- Modify: `packages/discipline_officer_module/lib/models/escalation_report_model.dart`
- Modify: `lib/data/escalation_repository.dart`
- Create: `test/endorsement_repository_test.dart`

**Interfaces:**
- Consumes: Task 1 columns and function.
- Produces:
  - `enum EndorsementKind { counseling, parentIntervention, both }` with `dbValue` (`'counseling'`, `'parent_intervention'`, `'both'`), `label` (`'Counseling'`, `'Parent intervention'`, `'Counseling and parent intervention'`), `bool get notifiesParent`.
  - `EscalationDraft` gains `required EndorsementKind kind` and `String? referralId`; `violationIds` may be empty; `message`/`channels` are ignored unless `kind.notifiesParent`.
  - `EscalationReportModel` gains `final EndorsementKind kind` and `final String? referralId` (defaults keep existing constructors compiling: `kind = parentIntervention`).
  - `class EndorsedViolation { String id, offense; String? category; DateTime? incidentAt; String status; }`
  - `EscalationRepository.fetchViolationHistory(String studentId) -> Future<List<EndorsedViolation>>` calling RPC `endorsement_violation_history` with `{'p_student_id': studentId}`.

- [ ] **Step 1: Write failing tests** in `test/endorsement_repository_test.dart` (recording-server style, as `test/escalation_decide_meeting_test.dart`): `issue` with `kind: counseling` and no violations posts to `/rest/v1/escalation_reports` a body containing `'kind': 'counseling'`, `'violation_ids': []`, `'channels': []`; `issue` with `referralId: 'ref1'` includes `'referral_id': 'ref1'`; `fetchViolationHistory('s1')` posts `{'p_student_id': 's1'}` to the RPC and maps one row to `EndorsedViolation(offense: 'Fighting', status: 'Pending', ...)`; `EscalationReportModel` built from a row without `kind` reads `parentIntervention`.
- [ ] **Step 2: Run** `flutter test test/endorsement_repository_test.dart`. Expected: FAIL (undefined names).
- [ ] **Step 3: Implement** the interface above. `_select` adds `kind, referral_id`; `_toModel` reads them.
- [ ] **Step 4: Run** the test, plus `flutter test test/escalation_decide_meeting_test.dart`. Expected: PASS.
- [ ] **Step 5: Commit.**

### Task 3: DO "Endorsements" tab (all students)

**Files:**
- Rename: `parental_intervention_view.dart` -> `endorsements_view.dart` (update the export in `discipline_officer_module.dart` and the imports in tests)
- Modify: `discipline_officer_dashboard_page.dart`, `lib/ui/discipline_officer_connected_page.dart`, `lib/data/discipline_repository.dart`
- Test: `packages/discipline_officer_module/test/endorsements_view_test.dart` (replaces `parental_intervention_view_test.dart`)

**Interfaces:**
- Consumes: Task 2's `EscalationDraft`, `EndorsementKind`.
- Produces:
  - `EndorsementsView({reports, loadStudents, onIssue})` where `loadStudents: Future<({List<StudentDirectoryEntryModel> items, int totalCount})> Function({required int page, String query})`.
  - `DisciplineRepository.fetchStudentDirectoryPage({required int page, int pageSize, String query = ''})` filtering name or student number case-insensitively server-side.
  - `DashboardTab.parentalIntervention` stays as the enum value; its label becomes `'Endorsements'`.

- [ ] **Step 1: Write failing widget tests**: the left card is titled "Students" and lists a student with no violations; typing in `Key('endorsement-student-search')` calls `loadStudents` with that query after the existing debounce pattern; the row's `Key('endorse-<studentNumber>')` button opens a dialog with a kind selector (`Key('endorsement-kind-counseling'|'parent_intervention'|'both')`), a required reason field, and no message/channels fields while `counseling` is selected; submitting counseling with no violations calls `onIssue` with an `EscalationDraft` whose `violationIds` is empty and `kind` is `counseling`; the violation tick-boxes appear only when the student has violations; the right card is titled "Endorsements" and shows `report.kind.label` on each tile.
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Implement** the view and wiring. The old "Escalated Violation History" card and the `CaseProgressBadge` status column are removed from this tab (the DO's investigation status returns in piece 2's Investigations tab; keep `caseProgress` and `CaseProgressBadge` in a new `lib/widgets/case_progress_badge.dart` so piece 2 can reuse them, with their existing tests moved to match). The connected page passes `loadStudents` from `fetchStudentDirectoryPage`.
- [ ] **Step 4: Run** `flutter test packages/discipline_officer_module/test/endorsements_view_test.dart test/discipline_*`. Expected: PASS.
- [ ] **Step 5: Commit.**

### Task 4: Guidance "Endorsement Approvals" and the retitle

**Files:**
- Modify: `packages/guidance_counselor_module/lib/pages/escalation/escalation_approvals_view.dart`, `.../dashboard/guidance_counselor_dashboard_page.dart`, `lib/ui/guidance_counselor_connected_page.dart`
- Test: `packages/guidance_counselor_module/test/escalation_and_archive_tabs_test.dart`

**Interfaces:**
- Consumes: Task 2's `EndorsedViolation`, `EscalationRepository.fetchViolationHistory`.
- Produces: `EscalationApprovalsView` gains `Future<List<EndorsedViolation>> Function(String studentId)? onLoadHistory` (null hides the history section).

- [ ] **Step 1: Write failing tests**: the tab label and card title read "Endorsement Approvals"; the dashboard title is "Guidance Associate Dashboard"; opening a report shows its `kind.label`, the DO's reason, and a "Violation history" section listing offense/date/status from `onLoadHistory` (or "No violations on record"); no text containing "sanction" is shown; approving a `counseling` report shows no "Message to the parent", no meeting picker, and `onDecide` receives `message: null`; approving a parent-intervention report keeps the message field and the 2026-10-21 meeting picker.
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Implement.** Rename strings only (enum value `escalationApprovals` stays). The detail dialog loads history with a `FutureBuilder` keyed on the report id.
- [ ] **Step 4: Run** the guidance package tests by path. Expected: PASS.
- [ ] **Step 5: Commit.**

### Task 5: Referrals move to the Discipline Officer

**Files:**
- Move: `packages/guidance_counselor_module/lib/pages/referrals/referrals_view.dart` -> `packages/discipline_officer_module/lib/pages/referrals/referrals_view.dart` (with `StudentReferralModel`); export from `discipline_officer_module.dart`
- Modify: `lib/data/referrals_repository.dart` (import path), both connected pages, both dashboard pages
- Test: `packages/discipline_officer_module/test/referrals_view_test.dart`, `test/referrals_repository_test.dart` (if present, update imports)

**Interfaces:**
- Consumes: Task 2's `EscalationDraft.referralId`.
- Produces: `DashboardTab.referrals` (label "Referrals") in the DO dashboard; `ReferralsView({referrals, onUpdate, onEndorse})` where `onEndorse(StudentReferralModel)` opens the Task 3 endorsement dialog prefilled with the student and `referralId`, and is hidden for a `Closed` referral.

- [ ] **Step 1: Write failing tests**: the DO dashboard shows a Referrals tab listing referrals with concern, urgency and status; an open referral row has an "Endorse" action that calls `onEndorse`; a `Closed` one has none; the Guidance dashboard no longer has a Referrals tab (`GuidanceCounselorTab` has no `referrals` value).
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Implement.** The DO view uses the DO module's table chrome (`DisciplineOfficerColors` + `dashboard_layout` table widgets), not `guidance_tab_chrome.dart`; the Guidance folder and its enum value, wiring and `studentReferrals` / `onUpdateReferral` parameters are deleted. The student portal's "counselor note" label stays; the note is now written by the DO.
- [ ] **Step 4: Run** `flutter test` (root) and the DO and Guidance package tests. Expected: PASS.
- [ ] **Step 5: Commit.**

### Task 6: Remove the Sanction log type

**Files:**
- Modify: `packages/guidance_counselor_module/lib/pages/student_archive/student_archive_models.dart`, `.../student_archive_view.dart`
- Modify: `packages/guidance_counselor_module/test/archive_log_type_test.dart`

**Interfaces:**
- Produces: `ArchiveLogType` without `sanction`; `manualChoices` removed (the Add log dropdown uses `ArchiveLogType.values` again).

- [ ] **Step 1: Change the test** to assert `ArchiveLogType.fromDb('sanction') == ArchiveLogType.other` and that no value has `dbValue == 'sanction'`.
- [ ] **Step 2: Run it.** Expected: FAIL.
- [ ] **Step 3: Implement** the removal; the view uses `ArchiveLogType.values`.
- [ ] **Step 4: Run** `flutter test packages/guidance_counselor_module/test/`. Expected: PASS.
- [ ] **Step 5: Commit.**

### Task 7: Demo checklist and full verification

**Files:**
- Modify: `docs/superpowers/demo-checklist.md`

- [ ] **Step 1:** Add `supabase/add_endorsements.sql` to the setup order after `add_escalation_meeting_and_sanction_log.sql`, and a short demo script: DO endorses a student with no violations for counseling -> Guidance approves -> logs a session by hand; a student referral appears under the DO's Referrals and is endorsed from there.
- [ ] **Step 2:** Run `flutter test` (root), then the guidance and DO package tests by path, then `flutter analyze lib packages/discipline_officer_module/lib packages/guidance_counselor_module/lib` and confirm no new errors.
- [ ] **Step 3: Commit.**

---

## Self-review notes

- Spec coverage: goals 2, 3, 5, 6, 7 are Tasks 1-6; goal 4 (counseling session logging) already exists as Intervention Logs and needs no change here; goals 1, 8, 9 belong to pieces 2-4.
- Deliberately not here: removing Guidance's direct read of `student_violations` (it feeds the analysis screens; piece 4 replaces that read with the aggregate path in the same change) and moving investigations (piece 2). Until piece 2, Guidance still sees the Investigations tab.
- Renamed-for-users-only: `EscalationReportModel`, `escalation_reports`, `decide_escalation_report`, `DashboardTab.parentalIntervention`, `GuidanceCounselorTab.escalationApprovals`.
