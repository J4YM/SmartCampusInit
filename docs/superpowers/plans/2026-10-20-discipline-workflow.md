# Discipline Workflow Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reporters file incident facts (date/time, photos); the DO classifies, then auto-records a minor, escalates to guidance (two-way meeting), or sanctions; every case ends in a sanction record that can block re-enrollment; 72-hour expiry flags and alerts instead of archiving.

**Architecture:** New hand-run SQL scripts in `supabase/` add columns, tables, and SECURITY DEFINER RPCs (all state transitions live in the DB and write `audit_logs`). Dart repositories in `lib/data/` wrap the RPCs; package UIs (`professor_module`, `discipline_officer_module`, `guidance_counselor_module`, `student_portal_module`, `parent_portal_module`, `registrar_module`) call them through the `lib/ui/*_connected_page.dart` hosts.

**Tech Stack:** Flutter/Dart, Supabase (Postgres, RLS, Storage, Realtime, pg_cron), existing `notifications` / `queue_sms` / `email_outbox` infrastructure.

**Spec:** `docs/superpowers/specs/2026-10-20-discipline-workflow-design.md`

## Global Constraints

- SQL is hand-run, idempotent (`if not exists`, `create or replace`), with a header stating run order (repo convention; no migration tool).
- Existing rows, the offline kiosk outbox, and `submit_admission_slip` (kiosk compatibility) must keep working.
- `student_violations.status` values: `Pending`, `Under_Investigation` (= With Guidance), `Investigation_Complete` (new), `Resolved`.
- Meeting statuses: `Proposed`, `Confirmed`, `Declined`, `Reschedule_Requested`, `Completed`, `Missed`, `Cancelled`.
- `sanctions.sanction_type`: warning, community_service, suspension, non_readmission, dismissal, other. `students.enrollment_standing`: `Good`, `Non_Readmission`, `Dismissed`.
- 72-hour clock excludes Saturday and Sunday; no holiday table. Warning alert at 12 hours remaining.
- Early sanction during guidance requires a non-empty reason (stored in `sanctions.override_reason`, audit-logged, counselor notified).
- Student kiosk self-report keeps its (Minor-only) offense picker.
- Follow existing UI components (`AppPopup`, dashboard styles) and write Dart tests beside existing ones in `test/` and each package's `test/`.

## Review Focus

- Incident time in the future or after the filed-at time: rejected, with a clear message.
- Report filed with zero photos, or a non-image / oversized upload: zero photos allowed; bad file rejected without losing the form text.
- Legacy violations with `offense_id` set and no `incident_at`: still display and still resolve.
- Case expiring over a weekend: the clock must not advance Sat/Sun; Friday 17:00 report is not expired Monday 08:00.
- DO tries to sanction a With-Guidance case: blocked without a reason; the same click with a reason succeeds.
- Student declines or never answers a meeting: counselor can reschedule or mark Missed, and the case is not stuck.
- Sanction with `affects_enrollment`: registrar's manual add/enroll/new-term flow refuses or visibly flags that student.
- Double-click / two officers acting on the same case: second action fails cleanly (one sanction per violation).

---

### Task 1: Incident report schema, evidence, classification RPCs

**Files:**
- Create: `supabase/add_incident_report_classification.sql`
- Test: `supabase/test_incident_report_classification.sql`

**Interfaces:**
- Produces (SQL): `student_violations.incident_at timestamptz`, `classified_by uuid`, `classified_at timestamptz`, `offense_id` nullable, enum value `Investigation_Complete`; table `violation_evidence(id, violation_id, storage_path, uploaded_by, created_at)`; private bucket `violation-evidence`;
  `submit_incident_report(p_student_id uuid, p_incident_at timestamptz, p_description text, p_evidence_paths text[], p_reported_by uuid, p_professor_id uuid) returns uuid` (violation id);
  `classify_violation(p_violation_id uuid, p_offense_ids uuid[]) returns void`.

- [ ] **Step 1: Write `test_incident_report_classification.sql`** asserting: future `p_incident_at` raises; valid call returns an id with `offense_id is null`, status `Pending`; `classify_violation` sets `offense_id`, `classified_by`, `classified_at`; legacy rows backfilled `incident_at = created_at`.
- [ ] **Step 2: Run it in the Supabase SQL editor** against a dev project; expected FAIL (objects missing).
- [ ] **Step 3: Write the migration** per the Interfaces: add columns, backfill, drop NOT NULL on `offense_id`, add enum value (outside a transaction block), create table + bucket (image mime types, 5 MB cap) with RLS (reporter inserts own evidence; DO/Admin/Guidance read via signed URL), create both RPCs SECURITY DEFINER writing `audit_logs`. Multiple offense ids create one violation row per offense, matching existing multi-offense behavior.
- [ ] **Step 4: Re-run the test script**; expected all assertions pass.
- [ ] **Step 5: Commit** `feat(db): incident reports with incident time, evidence, DO classification`.

### Task 2: Sanctions, enrollment standing, minor auto-record, guarded sanction RPC

**Files:**
- Create: `supabase/add_sanctions_schema.sql`
- Test: `supabase/test_sanctions_schema.sql`

**Interfaces:**
- Consumes: Task 1 columns/enum.
- Produces: table `sanctions` (spec fields; unique on `violation_id`); `students.enrollment_standing text not null default 'Good'`;
  `record_sanction(p_violation_id uuid, p_basis text, p_handbook_offense_id uuid, p_sanction_type text, p_description text, p_effective_on date, p_ends_on date, p_affects_enrollment boolean, p_override_reason text) returns uuid`;
  `auto_record_minor(p_violation_id uuid) returns uuid`.

- [ ] **Step 1: Write the test script**: `record_sanction` on a Pending classified case succeeds and sets status `Resolved`; second call raises (unique); `non_readmission` + `p_affects_enrollment` sets `students.enrollment_standing`; on an `Under_Investigation` case it raises without `p_override_reason` and succeeds with one; `auto_record_minor` raises for non-Minor and for an unclassified case, otherwise inserts a handbook sanction from `penalty_info` and resolves.
- [ ] **Step 2: Run; expect FAIL.**
- [ ] **Step 3: Implement** table, column, RPCs (DO/Admin role check, audit log, notify counselor on override, set `students.good_moral_status`/standing consistently). `dismissal` → `Dismissed`.
- [ ] **Step 4: Re-run; expect PASS.**
- [ ] **Step 5: Commit** `feat(db): sanction records, enrollment standing, minor auto-record`.

### Task 3: Guidance investigations and two-way meetings

**Files:**
- Create: `supabase/add_guidance_investigations.sql`
- Test: `supabase/test_guidance_investigations.sql`

**Interfaces:**
- Consumes: Tasks 1–2.
- Produces: tables `guidance_investigations`, `guidance_meetings` (spec fields), RLS (student/parent can select and update response fields only on rows where they are the invitee, via `parent_student_links`);
  `escalate_to_guidance(p_violation_id uuid) returns uuid` (sets status `Under_Investigation`, notifies Guidance role);
  `schedule_guidance_meeting(p_investigation_id uuid, p_scheduled_at timestamptz, p_location text, p_invitee text) returns uuid` (status `Proposed`; `notifications` row + `queue_sms` to guardian);
  `respond_to_meeting(p_meeting_id uuid, p_accept boolean, p_note text) returns void` (`Confirmed`/`Declined`);
  `set_meeting_outcome(p_meeting_id uuid, p_status text) returns void` (`Completed`/`Missed`/`Cancelled`);
  `complete_investigation(p_investigation_id uuid, p_findings text, p_recommendation text) returns void` (violation → `Investigation_Complete`, notify DO).

- [ ] **Step 1: Write the test script** covering: escalate creates one open investigation; only the invited student/linked parent can respond; a past `p_scheduled_at` raises; decline leaves the case open and allows scheduling a new meeting; `complete_investigation` requires findings and flips status.
- [ ] **Step 2: Run; expect FAIL.** **Step 3: Implement.** **Step 4: Re-run; expect PASS.**
- [ ] **Step 5: Commit** `feat(db): guidance investigations and acknowledged meetings`.

### Task 4: Weekday 72-hour expiry, flag instead of archive, alerts

**Files:**
- Create: `supabase/change_violation_expiry_to_flag.sql`
- Test: `supabase/test_violation_expiry_weekdays.sql`

**Interfaces:**
- Consumes: existing `expire_stale_violations()` and cron job `expire-stale-violations` in `supabase/add_violation_72h_expiry.sql`.
- Produces: `weekday_hours_between(p_from timestamptz, p_to timestamptz) returns numeric` (immutable; excludes Sat/Sun in Asia/Manila); replaced `expire_stale_violations()` that sets `expired_at` only (never `archived_at`) for Pending cases over 72 weekday hours since `coalesce(restored_at, created_at)`, and inserts a DO-role `notifications` row once per case ("expired"); `warn_expiring_violations()` that inserts one "due in 12 hours" notification per case (track with `expiry_warned_at timestamptz` column); cron entry for both, hourly.

- [ ] **Step 1: Write tests**: `weekday_hours_between('Fri 17:00','Mon 08:00')` = 15; a case created Friday 17:00 is not expired Monday 08:00 but is expired Wednesday 17:00; expiring twice produces one notification.
- [ ] **Step 2–4: fail, implement, pass.** Do not delete previously archived rows.
- [ ] **Step 5: Commit** `feat(db): weekday 72h expiry flags cases and alerts the DO`.

### Task 5: Auto-triggers become "Suggested escalation"

**Files:**
- Create: `supabase/change_auto_escalation_to_suggestion.sql`
- Modify (SQL only): none in place; new script replaces `trg_auto_parent_intervention`, keeps `apply_sanction_progression`, `escalate_sensitive_violation`.

**Interfaces:**
- Produces: `student_violations.suggested_escalation boolean default false`; `trg_auto_parent_intervention` no longer inserts `escalation_reports`/`parent_interventions` or sends SMS; the three triggers set `suggested_escalation = true`. Triggers must tolerate `offense_id is null` (skip until classified, re-run on `classify_violation`).

- [ ] **Step 1: Extend** `test_incident_report_classification.sql` with: 4th minor and a sensitive keyword set `suggested_escalation`; no `parent_interventions` row is created; unclassified insert does not error.
- [ ] **Step 2: Run; fail. Step 3: implement. Step 4: pass.**
- [ ] **Step 5: Commit** `feat(db): auto-escalation triggers flag instead of acting`.

### Task 6: Dart models and repositories

**Files:**
- Create: `lib/data/guidance_investigation_repository.dart`, `lib/data/sanctions_repository.dart`, `lib/data/violation_evidence_repository.dart`
- Modify: `lib/data/professor_repository.dart` (`submitReport`), `lib/data/discipline_repository.dart`, `packages/discipline_officer_module/lib/models/discipline_case_model.dart`, `lib/kiosk/supabase_kiosk_remote.dart`
- Test: `test/sanctions_repository_test.dart`, `test/guidance_investigation_repository_test.dart`, `test/discipline_case_model_lifecycle_test.dart`

**Interfaces:**
- Consumes: Tasks 1–5 RPCs.
- Produces:
  `ProfessorRepository.submitIncidentReport({required String studentId, required DateTime incidentAt, required String description, required List<EvidenceFile> evidence, String? professorId}) -> Future<String>` (uploads to `violation-evidence`, then RPC);
  `DisciplineRepository.classify(String violationId, List<String> offenseIds)`, `.autoRecordMinor(String violationId)`, `.escalateToGuidance(String violationId)`;
  `SanctionsRepository.record(SanctionInput input) -> Future<String>`, `.forStudent(String studentId) -> Future<List<SanctionRecord>>`;
  `GuidanceInvestigationRepository.schedule(...)`, `.respond(String meetingId, {required bool accept, String? note})`, `.setOutcome(...)`, `.complete(...)`, `.fetchAssigned()`, `.fetchMeetingsForStudent(String studentId)`;
  `DisciplineCaseModel`: add `incidentAt`, `description`, `evidencePaths`, `classified` (bool), `stage` (enum `CaseStage {reported, classified, withGuidance, investigationComplete, sanctioned}`), `suggestedEscalation`, `isExpired`; `canSanction` (false for `withGuidance`).

- [ ] **Step 1: Write failing tests**: `CaseStage` derivation for every status/field combination (including legacy rows with null `incidentAt`); `canSanction` false only for `withGuidance`; repositories call the correct RPC names/params (fake client, as in `test/discipline_repository_professor_decision_test.dart`).
- [ ] **Step 2: Run** `flutter test test/discipline_case_model_lifecycle_test.dart test/sanctions_repository_test.dart test/guidance_investigation_repository_test.dart`; expect FAIL.
- [ ] **Step 3: Implement** per Interfaces; `submitIncidentReport` rejects a future `incidentAt` client-side with the same message the RPC uses. Keep `submitReport` for the kiosk/offline path.
- [ ] **Step 4: Re-run those tests plus** `flutter test test/discipline_professor_decision_badge_test.dart test/discipline_repository_professor_decision_test.dart`; expect PASS.
- [ ] **Step 5: Commit** `feat: repositories and models for the new discipline lifecycle`.

### Task 7: Professor and security report forms

**Files:**
- Modify: `packages/professor_module/lib/pages/dashboard/violation_reports_view.dart`, `lib/ui/professor_connected_page.dart:303`, `lib/kiosk/security_report_screen.dart`
- Test: `packages/professor_module/test/violation_report_form_test.dart`

**Interfaces:**
- Consumes: `ProfessorRepository.submitIncidentReport`.
- Produces: `ReportSubmission` replaces `offenseIds`/`escalateNow` with `incidentAt`, `description`, `evidence`.

- [ ] **Step 1: Write widget tests**: no offense picker or escalate toggle rendered; Submit disabled until student, incident date+time, and description are set; picking a future time shows an inline error; picked photos are listed with remove buttons; a rejected upload keeps typed text.
- [ ] **Step 2: Run; expect FAIL. Step 3: Implement** (date + time pickers defaulting to now, `image_picker`/`file_picker` already used elsewhere in the repo if present, else add `image_picker`). **Step 4: Run; expect PASS.**
- [ ] **Step 5: Commit** `feat: professor/security reports capture incident time and photo evidence`.

### Task 8: DO dashboard — classify, three paths, sanction form, timeline

**Files:**
- Modify: `packages/discipline_officer_module/lib/pages/dashboard/violations_view.dart`, `discipline_officer_dashboard_page.dart`, `lib/ui/discipline_officer_connected_page.dart`
- Create: `packages/discipline_officer_module/lib/pages/dashboard/sanction_dialog.dart`, `classify_dialog.dart`, `case_timeline.dart`
- Test: `packages/discipline_officer_module/test/case_actions_test.dart`

**Interfaces:**
- Consumes: Task 6 repositories and `DisciplineCaseModel.stage/canSanction`.
- Produces: `SanctionDialog({required DisciplineCaseModel case, required Future<void> Function(SanctionInput) onSave})` with a handbook-suggested prefill, a custom option, an enrollment-effect toggle behind a confirm step, and a required reason field when `!case.canSanction`.

- [ ] **Step 1: Write widget tests**: unclassified case shows only Classify; classified Minor shows Auto-record / Escalate / Sanction; non-Minor hides Auto-record; With Guidance disables Sanction and the override path requires a reason; enrollment toggle requires confirm; evidence thumbnails and `suggestedEscalation` badge render.
- [ ] **Step 2: Run; FAIL. Step 3: Implement** (replace the Validate button with the stage-driven action row; timeline reads investigation/meeting/sanction rows). **Step 4: PASS.**
- [ ] **Step 5: Commit** `feat: DO classify, escalate, auto-record and sanction flow`.

### Task 9: Guidance counselor Investigations tab

**Files:**
- Create: `packages/guidance_counselor_module/lib/pages/investigations/investigations_view.dart`, `schedule_meeting_dialog.dart`
- Modify: `packages/guidance_counselor_module/lib/pages/dashboard/guidance_counselor_dashboard_page.dart` (tab enum at ~249), `lib/ui/guidance_counselor_connected_page.dart`
- Test: `packages/guidance_counselor_module/test/investigations_view_test.dart`

**Interfaces:**
- Consumes: `GuidanceInvestigationRepository`.

- [ ] **Step 1: Widget tests**: list shows assigned cases with evidence; schedule dialog rejects past times; meeting row shows the invitee's response live; Declined/Missed offers Reschedule; Complete requires findings.
- [ ] **Step 2–4: fail, implement, pass.** **Step 5: Commit** `feat: guidance investigations tab with meeting scheduling`.

### Task 10: Student and parent meeting acknowledgement

**Files:**
- Modify: `packages/student_portal_module` and `packages/parent_portal_module/lib/pages/interventions_page.dart` (add a meeting card); their connected hosts under `lib/ui/`
- Test: `packages/parent_portal_module/test/meeting_card_test.dart`, `packages/student_portal_module/test/meeting_card_test.dart`

- [ ] **Step 1: Widget tests**: Proposed meeting shows date/place with Confirm and Can't attend (+ note); tapping calls `respond`; after responding the card shows the status and Confirm is gone; past meetings are read-only.
- [ ] **Step 2–4: fail, implement, pass.** **Step 5: Commit** `feat: students and parents acknowledge guidance meetings`.

### Task 11: Enrollment standing enforcement and student record

**Files:**
- Modify: `lib/data/registrar_repository.dart`, `lib/data/students_repository.dart` (`StudentRecord.enrollmentStanding`), `packages/registrar_module/lib/pages/dashboard/student_records_view.dart`, the new-term flow in `lib/data/academic_term_repository.dart`
- Create: `supabase/add_enrollment_standing_guard.sql` (reject enrollments/section assignment for non-Good students unless Admin override RPC)
- Test: `test/enrollment_standing_test.dart`

- [ ] **Step 1: Tests**: enrolling a `Non_Readmission` student throws a readable error; student record shows a red standing banner and sanction history; the new-term function leaves such students inactive.
- [ ] **Step 2–4: fail, implement, pass.** **Step 5: Commit** `feat: sanctions block re-enrollment and show on the student record`.

### Task 12: Expired marker and urgent DO notifications

**Files:**
- Modify: `lib/data/discipline_repository.dart` (remove unused `expireStaleViolations`, queries keep expired cases in active list), `violations_view.dart`, `lib/app/notification_alert.dart`
- Test: `test/discipline_expiry_ordering_test.dart`

- [ ] **Step 1: Tests**: expired cases remain in `fetchActiveViolations`, sort first, and `isExpired` renders the red marker; an expiry notification triggers the alert sound path (urgent styling).
- [ ] **Step 2–4: fail, implement, pass.** **Step 5: Commit** `feat: expired violations are marked and alerted, not archived`.

### Task 13: End-to-end demo verification

**Files:**
- Create: `supabase/demo_discipline_workflow.sql`, `docs/superpowers/demo-checklist.md`

- [ ] **Step 1: Write the demo seed** (one student, one professor, parent link) and a checklist covering: professor report with photo → DO classify → escalate → counselor schedules → parent confirms → findings → DO non-readmission sanction → registrar refuses re-enrollment; a minor auto-record; a Friday-created case across a weekend; a declined meeting then reschedule.
- [ ] **Step 2: Run `flutter analyze` and `flutter test`**; expected: no new analyzer errors, all tests pass.
- [ ] **Step 3: Walk the checklist in the running app**, ticking each line; note failures and fix before finishing.
- [ ] **Step 4: Commit** `docs: discipline workflow demo script`.

---

## Self-Review Notes

- Spec coverage: report fields/photos (1,6,7); DO three paths and rule (2,8); guidance + acknowledgement (3,9,10); sanction records and enrollment effect (2,11); 72h flag/weekend/alerts (4,12); trigger change (5); verification (13).
- Types: `CaseStage`, `canSanction`, `SanctionInput`, RPC parameter names are identical in Tasks 1–3 and 6–8.
- Open risk: `incident_notes` column has no tracked ALTER; Task 1 must confirm it exists live and add `if not exists` for it.
