# Student Affairs gaps Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add sanction history (staff, student, parent), a manual incident report, concern-to-investigation plus a returned-endorsement fix, investigation scheduling through the endorsement flow, and automatic intervention-log entries for completed meetings.

**Architecture:** New idempotent SQL migrations (security-definer RPCs, hand-run in the Supabase SQL editor) plus thin Dart repositories and widgets in the existing app and portal packages. Availability rounds and meetings are extended to belong to an investigation as well as an endorsement, so one flow serves both.

**Tech Stack:** Flutter/Dart (`lib/`, `packages/*_module`), Supabase Postgres + PostgREST, `flutter test`, SQL assertion scripts (`supabase/test_*.sql`).

**Spec:** `docs/superpowers/specs/2026-11-19-student-affairs-gaps-design.md`

## Global Constraints

- Branch `feat/student-affairs-gaps`; commit after every task. Five increments (Tasks 1-5, 6-7, 8-9, 10-11, 12) are each tested and merged on their own.
- Every migration is idempotent (`create or replace`, `if not exists`, `drop ... if exists`). SQL has to be run by the user in the Supabase SQL editor: at every "Run SQL" step the executor stops and asks the user to run the file and report the result.
- Credential parents and demo students run on the `anon` role (`auth.uid()` is null). Parent-facing RPCs are granted to `anon, authenticated` and take `p_parent_id uuid default null`, used via `coalesce(auth.uid(), p_parent_id)` (same as `supabase/add_parent_credential_access.sql`). Student-facing ones follow `my_concern_reports(p_reporter_id)` in `supabase/add_concern_reports.sql`. Test-grade security only.
- Students and parents never receive `override_reason`, `decided_by` or the handbook basis of a sanction.
- Saving a manual incident or starting an investigation sends nothing to the parent or student. Parent messages go only through an explicit "Notify parent" choice.
- A concern can always be updated or closed with the status picker.
- Do not change endorsement scheduling behaviour. Re-run `supabase/test_endorsement_meetings.sql` and `supabase/test_parent_availability_scheduling.sql` after Task 10.
- SQL files written by tools use LF; normalise CRLF when copying existing function bodies.
- Package code under `packages/*` cannot import `lib/`; the connected pages in `lib/ui/` map app records to each package's own view models.

## Review Focus

- A parent with two linked children sees only the selected child's sanctions (Task 4).
- Student and parent sanction reads return no override reason or decider (Task 1).
- A manual incident with "Notify parent" off creates no `parent_interventions` or parent `notifications` row (Task 6).
- Closing a concern whose investigation is still open works; endorsing an already closed concern is still rejected (Task 8).
- An investigation availability round (no `escalation_report_id`) survives cancel and the 48-hour reminder job, and never notifies the guidance counselor (Task 10).
- Completing the same meeting twice, or via the DO who cannot write the archive directly, yields exactly one log entry (Task 12).

---

## Increment 1: Sanction history

### Task 1: Student/parent sanction history RPC

**Files:**
- Create: `supabase/add_sanction_history.sql`
- Test: `supabase/test_sanction_history.sql` (style: `supabase/test_parent_availability_scheduling.sql`, Admin session, rolled back, prints `ALL PASSED`)

**Interfaces:**
- Produces: `public.my_sanction_history(p_student_id uuid, p_parent_id uuid default null) returns table (id uuid, sanction_type text, description text, effective_on date, ends_on date, affects_enrollment boolean, decided_at timestamptz)`, security definer, `grant execute ... to anon, authenticated`, ordered `effective_on desc, decided_at desc`. Allowed when: caller is staff (`current_user_role() in Admin, Discipline_Officer, Guidance_Counselor, Registrar`), or a parent linked via `parent_student_links` (`l.parent_id = coalesce(auth.uid(), p_parent_id)`), or the student themselves (`auth.uid() = p_student_id`, plus the anon student path used by `my_concern_reports`). Anything else raises `42501`.

- [ ] **Step 1: Write the failing test script** asserting: a linked parent (`p_parent_id`) gets the student's sanctions; an unlinked parent id gets `42501`; the returned columns are exactly the seven above (no `override_reason`, no `decided_by`, no `basis`); a student with no sanctions returns zero rows; `ends_on` may be null.
- [ ] **Step 2: Run SQL** — ask the user to run `supabase/test_sanction_history.sql`. Expected: fails (function does not exist).
- [ ] **Step 3: Implement the function in `supabase/add_sanction_history.sql`**, reading `public.sanctions`; no new table policies (students/parents stay blocked from the table).
- [ ] **Step 4: Run SQL** — ask the user to run the migration, then the test. Expected: `ALL PASSED`.
- [ ] **Step 5: Commit** `git add supabase/add_sanction_history.sql supabase/test_sanction_history.sql && git commit -m "feat: sanction history RPC for students and parents"`

### Task 2: Sanction history repository method

**Files:**
- Modify: `lib/data/sanctions_repository.dart` (add class and method after `forStudent`, line ~151)
- Test: `test/sanction_history_repository_test.dart` (use the fake-server helper pattern from `test/parent_availability_repository_test.dart`)

**Interfaces:**
- Consumes: `my_sanction_history` from Task 1; `SanctionType.parse`.
- Produces: `class SanctionHistoryEntry { final String id; final SanctionType type; final String description; final DateTime effectiveOn; final DateTime? endsOn; final bool affectsEnrollment; }` and `Future<List<SanctionHistoryEntry>> SanctionsRepository.myHistory(String studentId, {String? parentId})`. `parentId` is sent as `p_parent_id` only when non-null.

- [ ] **Step 1: Write the failing test** `myHistory sends p_student_id, includes p_parent_id only when given, and parses rows` with one row having `ends_on: null`; assert `entries.single.endsOn == null` and `type == SanctionType.suspension`.
- [ ] **Step 2: Run** `flutter test test/sanction_history_repository_test.dart` — Expected: FAIL (method undefined).
- [ ] **Step 3: Implement** the class and method; wrap `PostgrestException` in `SanctionsRepositoryException`.
- [ ] **Step 4: Run** the test — Expected: PASS.
- [ ] **Step 5: Commit** `git commit -am "feat: SanctionsRepository.myHistory"`

### Task 3: Student Portal sanction card

**Files:**
- Create: `packages/student_portal_module/lib/models/sanction_history_entry.dart`, `packages/student_portal_module/lib/widgets/sanction_history_card.dart`
- Modify: `packages/student_portal_module/lib/pages/student_portal_home_page.dart` (add `initialSanctions` the way `initialMeetings` is threaded), `lib/ui/student_portal_connected_page.dart` (load via `SanctionsRepository(...).myHistory(studentId)` on the same load/refresh cycle, map to the package model; failure keeps the card hidden and `debugPrint`s the error)
- Test: `packages/student_portal_module/test/sanction_history_card_test.dart`

**Interfaces:**
- Consumes: `SanctionHistoryEntry`/`myHistory` (Task 2).
- Produces: package model `SanctionHistoryEntry({required String id, required String typeLabel, required String description, required DateTime effectiveOn, DateTime? endsOn, required bool affectsEnrollment})`; `SanctionHistoryCard({required List<SanctionHistoryEntry> entries})` returning `SizedBox.shrink()` when empty.

- [ ] **Step 1: Write failing widget tests:** empty list renders nothing; two entries render type label, description, date range ("Open-ended" when `endsOn` is null) and an "Affects enrollment" tag only on the flagged one.
- [ ] **Step 2: Run** `cd packages/student_portal_module && flutter test test/sanction_history_card_test.dart` — Expected: FAIL.
- [ ] **Step 3: Implement** the model, card (follow `portal_surface_card.dart` + `section_header.dart`) and the home page wiring.
- [ ] **Step 4: Run** the new test and `flutter test` in the package — Expected: PASS.
- [ ] **Step 5: Commit** `git commit -am "feat: sanction history card in the student portal"`

### Task 4: Parent Portal sanction card

**Files:**
- Create: `packages/parent_portal_module/lib/models/sanction_history_entry.dart` (same shape as Task 3), `packages/parent_portal_module/lib/widgets/sanction_history_card.dart` (`ParentPortalColors`/`ParentPortalSpacing` styling)
- Modify: `packages/parent_portal_module/lib/pages/parent_portal_home_page.dart` (add `initialSanctions`, render the card near the discipline card in both compact and wide layouts), `lib/ui/parent_portal_connected_page.dart` (`_sanctions`, `_loadSanctions(studentId)` called from `_load()`, reset to null in `_selectChild`, pass `parentId: _parentId`, guard with `_isStale(studentId)`)
- Test: `packages/parent_portal_module/test/sanction_history_card_test.dart`, `test/parent_portal_connected_page_test.dart` (extend)

**Interfaces:**
- Consumes: `SanctionsRepository.myHistory(studentId, parentId:)` (Task 2).
- Produces: parent-package `SanctionHistoryEntry` and `SanctionHistoryCard({required List<SanctionHistoryEntry> entries})`.

- [ ] **Step 1: Write failing tests:** the widget cases from Task 3; and a connected-page test with a fake client asserting that switching children replaces the list (child B's sanctions never show while child A is selected).
- [ ] **Step 2: Run** the new tests — Expected: FAIL.
- [ ] **Step 3: Implement** the model, card, home page param and connected-page loading.
- [ ] **Step 4: Run** `flutter test` in the package and `flutter test test/parent_portal_connected_page_test.dart` — Expected: PASS.
- [ ] **Step 5: Commit** `git commit -am "feat: sanction history card in the parent portal"`

### Task 5: Staff sanction history (Discipline Officer and Guidance)

**Files:**
- Create: `packages/discipline_officer_module/lib/pages/dashboard/sanction_history_dialog.dart`, `packages/guidance_counselor_module/lib/pages/archive/sanction_history_dialog.dart` (look for the Student Archive tab's directory; place it beside it)
- Modify: `packages/discipline_officer_module/lib/pages/dashboard/violation_history_view.dart` (a "Sanction history" row action per student), the Guidance Student Archive student panel (a "Sanction history" button), `lib/ui/discipline_officer_connected_page.dart` and `lib/ui/guidance_counselor_connected_page.dart` (map `SanctionsRepository.forStudent` records to each package's view model)
- Test: one widget test per package

**Interfaces:**
- Consumes: `SanctionsRepository.forStudent(String studentId)` (existing) returning `SanctionRecord`.
- Produces: per package `showSanctionHistory(BuildContext context, {required String studentName, required List<SanctionHistoryItem> items})`; `SanctionHistoryItem` carries the full staff detail (type label, description, basis, effective and end dates, enrollment flag, override reason).

- [ ] **Step 1: Write failing widget tests:** dialog lists items newest first and shows the override reason; empty state says "No sanctions on record."
- [ ] **Step 2: Run** each package's new test — Expected: FAIL.
- [ ] **Step 3: Implement** the dialogs following `sanction_dialog.dart`'s `AppPopup` usage and wire both entry points.
- [ ] **Step 4: Run** `flutter test` in both packages — Expected: PASS.
- [ ] **Step 5: Commit** `git commit -am "feat: staff sanction history dialogs"`

---

## Increment 2: Manual incident report

### Task 6: `report_incident` RPC

**Files:**
- Create: `supabase/add_manual_incident_reports.sql`
- Test: `supabase/test_manual_incident_reports.sql`

**Interfaces:**
- Produces (schema): `alter table public.student_violations add column if not exists source text, add column if not exists concern_id uuid references public.concern_reports(id) on delete set null, add column if not exists location text;`
- Produces: `public.report_incident(p_student_id uuid, p_offense_id uuid, p_description text, p_occurred_at timestamptz, p_location text default null, p_notify_parent boolean default false, p_concern_id uuid default null) returns uuid`: Discipline Officer or Admin only (`42501` otherwise); inserts `student_violations` (`status 'Pending'`, `reported_by = auth.uid()`, `incident_notes = p_description`, `source = 'student_affairs'`, `concern_id`); `log_audit('Reported incident', id::text)`; inserts a parent message only when `p_notify_parent`.
- Produces: `public.notify_parent_of_incident(p_violation_id uuid) returns void` (same role check; inserts the parent message; raises if no linked parent). The parent message reuses the existing `parent_interventions` insert pattern from `supabase/add_endorsements.sql` (line ~285).

- [ ] **Step 1: Write the failing test:** with `p_notify_parent = false`, one `student_violations` row exists and zero new `parent_interventions` rows and zero parent `notifications` rows; with `true`, one parent message; a non-DO caller gets `42501`; a missing offense or blank description raises.
- [ ] **Step 2: Run SQL** — user runs the test. Expected: fails.
- [ ] **Step 3: Implement** the migration.
- [ ] **Step 4: Run SQL** — user runs migration then test. Expected: `ALL PASSED`.
- [ ] **Step 5: Commit** `git commit -am "feat: report_incident RPC for manual incidents"`

### Task 7: Manual incident panel

**Files:**
- Create: `lib/data/incident_reports_repository.dart`, `packages/discipline_officer_module/lib/pages/incidents/manual_incident_view.dart`
- Modify: `packages/discipline_officer_module/lib/pages/dashboard/discipline_officer_dashboard_page.dart` (new nav entry "Report incident" and `onReportIncident` callback), `lib/ui/discipline_officer_connected_page.dart` (wire the repository, student search source, offense list from existing `handbook_offenses` data)
- Test: `test/incident_reports_repository_test.dart`, `packages/discipline_officer_module/test/manual_incident_view_test.dart`

**Interfaces:**
- Produces: `class IncidentReportInput { String studentId; String offenseId; String description; DateTime occurredAt; String? location; bool notifyParent; String? concernId; }` and `Future<String> IncidentReportsRepository.report(IncidentReportInput input)` (RPC `report_incident`), `Future<void> notifyParent(String violationId)`.
- Produces: `ManualIncidentView({required Future<String> Function(IncidentReportInput) onSubmit, required List<IncidentStudentOption> students, required List<IncidentOffenseOption> offenses, IncidentReportInput? prefill})` (package-side view models; `prefill` is used by Task 9).

- [ ] **Step 1: Write failing tests:** repository sends exactly the `p_*` params (omits `p_concern_id` when null); view blocks submit with no student, no offense or empty description; "Notify parent" switch defaults off and is passed through when turned on.
- [ ] **Step 2: Run** the two tests — Expected: FAIL.
- [ ] **Step 3: Implement** repository, view and wiring.
- [ ] **Step 4: Run** both tests plus `flutter test` in the DO package — Expected: PASS.
- [ ] **Step 5: Commit** `git commit -am "feat: Student Affairs manual incident report panel"`

---

## Increment 3: Concerns

### Task 8: Concern-to-investigation and case file RPCs

**Files:**
- Create: `supabase/add_concern_investigations.sql`
- Test: `supabase/test_concern_investigations.sql`

**Interfaces:**
- Consumes: `report_incident` (Task 6), `escalate_to_guidance(p_violation_id uuid) returns uuid` (existing, `supabase/add_do_investigations.sql`).
- Produces (schema): `alter table public.concern_reports add column if not exists violation_id uuid references public.student_violations(id) on delete set null;`
- Produces: `public.send_concern_to_investigation(p_concern_id uuid, p_student_id uuid, p_offense_id uuid, p_description text, p_occurred_at timestamptz, p_location text default null, p_notify_parent boolean default false) returns uuid` (returns the investigation id): DO/Admin only; the concern must be open and not already linked; calls `report_incident` with `p_concern_id`, then `escalate_to_guidance`, sets `concern_reports.violation_id`, status `In_Progress`, `handled_by`/`handled_at`; audit-logged.
- Produces: `public.concern_case_file(p_concern_id uuid) returns jsonb` (DO/Admin only) with keys `endorsements` (array of `{id, status, decision_note, summary, meetings: [{id, scheduled_at, status, response_note, location}]}` for `escalation_reports.concern_id = p_concern_id`) and `investigation` (null or `{id, status, findings, recommendation, completed_at, sanction: {type, description} | null}`).
- Confirms: the status-picker update path (`concern_reports_staff_update`, `ConcernReportsRepository.update`) has no guard against endorsed or investigated concerns; the only guard is `trg_endorsement_referral_guard` rejecting endorsement of a closed concern.

- [ ] **Step 1: Write the failing test:** sending a concern creates one violation (`concern_id` set, `source 'student_affairs'`), one investigation, concern `In_Progress` with `violation_id`; sending twice raises; a closed concern raises; closing the concern (`update ... status = 'Closed'`) while the investigation is `Open` succeeds and leaves the investigation `Open`; endorsing the closed concern is still rejected; `concern_case_file` returns the endorsement's meeting with its `response_note`.
- [ ] **Step 2: Run SQL** — user runs the test. Expected: fails.
- [ ] **Step 3: Implement** the migration.
- [ ] **Step 4: Run SQL** — user runs migration then test. Expected: `ALL PASSED`.
- [ ] **Step 5: Commit** `git commit -am "feat: send concern to investigation and concern case file"`

### Task 9: Concerns tab UI

**Files:**
- Modify: `lib/data/concern_reports_repository.dart` (add methods), `packages/discipline_officer_module/lib/models/concern_report_model.dart` (add `violationId`, `underInvestigation`), `packages/discipline_officer_module/lib/pages/concerns/concerns_view.dart` (action cell and dialog), `lib/ui/discipline_officer_connected_page.dart` (callbacks; refresh concerns after sending)
- Create: `packages/discipline_officer_module/lib/models/concern_case_file.dart`
- Test: `test/concern_reports_repository_test.dart` (extend), `packages/discipline_officer_module/test/concerns_view_test.dart` (create or extend)

**Interfaces:**
- Consumes: `send_concern_to_investigation`, `concern_case_file` (Task 8); `ManualIncidentView.prefill` (Task 7).
- Produces: `ConcernReportsRepository.fetchCaseFile(String concernId) -> Future<ConcernCaseFile>`; `ConcernCaseFile {List<CaseEndorsement> endorsements; CaseInvestigation? investigation;}` (package-side); `ConcernsView` gains `onSendToInvestigation: Future<void> Function(ConcernReportModel)?` and `loadCaseFile: Future<ConcernCaseFile> Function(ConcernReportModel)?`.

- [ ] **Step 1: Write failing tests:** open concern with neither link shows both "Endorse to Guidance" and "Send to investigation" icons; endorsed concern shows "Endorsed" text **and** still opens the dialog whose status picker is enabled; dialog shows endorsement decision note, meeting status and response note, plus investigation findings and recommendation once complete; concern under investigation shows "Under investigation" and no send icon; a closed concern shows neither action icon but the dialog still opens.
- [ ] **Step 2: Run** the new tests — Expected: FAIL.
- [ ] **Step 3: Implement** the action cell (replace the lone `Text('Endorsed')` branch at `concerns_view.dart` ~line 245), the dialog "Case file" section (loaded on open with `loadCaseFile`; loading and error states), and the page wiring: "Send to investigation" opens `ManualIncidentView` pre-filled from the concern (details, urgency, today) so the DO picks the student and offense, then calls the repository method.
- [ ] **Step 4: Run** `flutter test` in the DO package and the repository test — Expected: PASS.
- [ ] **Step 5: Commit** `git commit -am "feat: concerns can go to investigation and show returned findings"`

---

## Increment 4: Investigation scheduling

### Task 10: Investigation availability rounds in SQL

**Files:**
- Create: `supabase/add_investigation_scheduling.sql`
- Test: `supabase/test_investigation_scheduling.sql`

**Interfaces:**
- Consumes: the current definitions in `supabase/add_parent_credential_access.sql` (`submit_parent_availability(uuid, timestamptz[], uuid)`), `supabase/add_parent_availability_scheduling.sql` (`decide_parent_availability`, `cancel_parent_availability`, `remind_stale_availability_rounds`, `request_parent_availability` for the notification and SMS pattern). Copy and extend those bodies; do not rewrite from memory.
- Produces (schema): `meeting_availability_rounds.escalation_report_id` becomes nullable; add `investigation_id uuid references public.guidance_investigations(id) on delete cascade`; add check `(escalation_report_id is null) <> (investigation_id is null)`; add unique `(investigation_id, round_no)`; confirm `guidance_meetings.investigation_id` is nullable-compatible and the meeting insert for an investigation sets it.
- Produces: `public.request_investigation_availability(p_investigation_id uuid) returns uuid`: DO/Admin only; investigation `Open`; no `Open`/`Offered` round; a linked parent exists; creates the round, parent notification and `availability_request` SMS as `request_parent_availability` does, and notifies the Discipline Officer only (never `Guidance_Counselor`).
- Changes: `submit_parent_availability` skips the endorsement checks for investigation rounds and notifies the DO only; `decide_parent_availability` for an investigation round is DO/Admin only, requires the investigation `Open`, and creates a `Proposed` meeting with `investigation_id` and invitee `parent`; `cancel_parent_availability` and `remind_stale_availability_rounds` work when `escalation_report_id` is null (left join, no endorsement status check); `respond_to_meeting` is unchanged (investigation meetings already notify the DO only).

- [ ] **Step 1: Write the failing test:** request creates an `Open` round with `investigation_id` set and `escalation_report_id` null; the check rejects a round with both or neither; a guidance counselor cannot request or decide (`42501`); the parent offers times (impersonated, `p_parent_id` path) and the DO approves one, producing a `Proposed` meeting with `investigation_id`; no `Guidance_Counselor` notification rows are created in the whole flow; cancel works; the reminder job reminds a stale investigation round once.
- [ ] **Step 2: Run SQL** — user runs the test. Expected: fails.
- [ ] **Step 3: Implement** the migration.
- [ ] **Step 4: Run SQL** — user runs migration, the new test, then `test_parent_availability_scheduling.sql` and `test_endorsement_meetings.sql` for regressions. Expected: all `ALL PASSED`.
- [ ] **Step 5: Commit** `git commit -am "feat: investigation meetings use the availability flow, DO-approved"`

### Task 11: Investigation scheduling UI

**Files:**
- Modify: `packages/discipline_officer_module/lib/pages/investigations/investigations_view.dart` (replace or augment the direct-schedule action with request availability / offered times / approve / decline / cancel, mirroring `packages/discipline_officer_module/lib/pages/dashboard/endorsements_view.dart`), `lib/data/guidance_investigation_repository.dart` (or `escalation_repository.dart`; add the methods below), `lib/ui/discipline_officer_connected_page.dart`
- Test: `packages/discipline_officer_module/test/investigations_view_test.dart` (create or extend), `test/parent_availability_repository_test.dart` (extend)

**Interfaces:**
- Consumes: Task 10 RPCs; `ParentAvailabilityRound`, `AvailabilityRoundInfo` (`packages/discipline_officer_module/lib/models/availability_round_info.dart`).
- Produces: `Future<String> requestInvestigationAvailability(String investigationId)` and `Future<List<ParentAvailabilityRound>> fetchInvestigationRounds(List<String> investigationIds)` on the repository holding the matching endorsement methods; decide and cancel reuse the existing `decide`/`cancelParentAvailability` calls.

- [ ] **Step 1: Write failing tests:** an open investigation shows "Request parent availability"; with an `Offered` round it lists the times with Approve and Decline; with an `Open` round it shows Cancel request; the repository sends `p_investigation_id` to `request_investigation_availability`.
- [ ] **Step 2: Run** the new tests — Expected: FAIL.
- [ ] **Step 3: Implement** the view changes and wiring, reusing the endorsements view's round widgets where they are extractable.
- [ ] **Step 4: Run** `flutter test` in the DO package and the repository test — Expected: PASS.
- [ ] **Step 5: Commit** `git commit -am "feat: Discipline Officer requests parent availability for investigations"`

---

## Increment 5: Completed meetings in the intervention log

### Task 12: Auto-log completed guidance meetings

**Files:**
- Create: `supabase/add_meeting_completion_log.sql`
- Test: `supabase/test_meeting_completion_log.sql`

**Interfaces:**
- Consumes: `set_meeting_outcome(p_meeting_id uuid, p_status text)` as defined in `supabase/add_endorsement_meetings.sql` (line ~358) and `public.counseling_archive_logs`.
- Produces (schema): `alter table public.counseling_archive_logs add column if not exists meeting_id uuid unique references public.guidance_meetings(id) on delete set null;`
- Changes: `set_meeting_outcome` (same signature, redefined from the current body): when `p_status = 'Completed'` and the meeting is guidance-owned (`referral_id` or `escalation_report_id` not null), insert one `counseling_archive_logs` row inside the function (security definer, so it works for the DO and Admin): `log_type` `parent_conference` if `invitee in ('parent','both')` else `counseling`; `occurred_on` the meeting date; `title` "Meeting completed: <endorsement|referral> meeting"; `notes` listing invited party, date and time, location, the invitee's `response_note`, and the endorsement `decision_note` when present; `created_by = auth.uid()` with the creator's name; `on conflict (meeting_id) do nothing`. Missed/Cancelled and investigation meetings insert nothing.

- [ ] **Step 1: Write the failing test:** completing an endorsement meeting with invitee `both` yields one `parent_conference` row for the student with the response note in `notes`; completing it again changes nothing and still one row; invitee `student` yields `counseling`; `Missed` and an investigation meeting yield no row; the call succeeds under a Discipline Officer session.
- [ ] **Step 2: Run SQL** — user runs the test. Expected: fails.
- [ ] **Step 3: Implement** the migration.
- [ ] **Step 4: Run SQL** — user runs migration then test. Expected: `ALL PASSED`.
- [ ] **Step 5: Commit** `git commit -am "feat: completed guidance meetings are logged to the counselor archive"`

---

## Final verification

- [ ] Run `flutter analyze` and `flutter test` at the repo root and in `packages/discipline_officer_module`, `packages/student_portal_module`, `packages/parent_portal_module`, `packages/guidance_counselor_module`. Expected: no new analyzer issues; all tests pass.
- [ ] Ask the user to run, in order: `add_sanction_history.sql`, `add_manual_incident_reports.sql`, `add_concern_investigations.sql`, `add_investigation_scheduling.sql`, `add_meeting_completion_log.sql`, each followed by its test file.
- [ ] Manual check in the app: sanction cards in both portals; a manual incident with and without "Notify parent"; a concern sent to investigation and closed from the picker; an endorsed concern showing returned findings; an investigation availability request approved by the DO; a completed endorsement meeting appearing in the counselor's Student Archive.
