# Discipline Office Owns Investigations Implementation Plan (piece 2 of 4)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The Discipline Officer (DO) starts, runs and completes investigations and schedules their meetings; the Guidance Associate no longer sees investigations or investigation meetings.

**Architecture:** Keep the existing tables and RPC names (`guidance_investigations`, `guidance_meetings`, `escalate_to_guidance`, `schedule_guidance_meeting`, `set_meeting_outcome`, `complete_investigation`, `respond_to_meeting`) and change who may call them and who is notified. Move `InvestigationsView` and its models from the Guidance module into the DO module (the DO module cannot import Guidance) as a new DO "Investigations" tab. Remove the Investigations tab from Guidance. Meetings the Guidance Associate creates while approving an endorsement (`escalation_report_id` set) stay visible to Guidance.

**Tech Stack:** Flutter monorepo (local packages), Supabase Postgres RLS + SECURITY DEFINER functions, `test/support/recording_server.dart`, widget tests.

**Spec:** `docs/superpowers/specs/2026-10-22-do-owns-investigations-and-endorsements-design.md` (goal 1, anti-goals, "Calls made by the author"). Pieces 1 (done), 3 (Good Moral) and 4 (ML access) are separate plans.

## Global Constraints

- Real staff accounts are `authenticated`; static demo logins are `anon` and cannot call signed-in-only functions. Verify with `demo.*@baliuag.sti.edu.ph`.
- Netlify web build is Flutter 3.24.5: use `Color.withOpacity`, never `withValues`.
- Database role names are unchanged; only labels and permissions change. RPC and table names are NOT renamed (YAGNI).
- SQL is an idempotent file in `supabase/` run by the user in the Supabase SQL editor; stage explicit paths (never `git add -A supabase`); the SQL cannot be executed by the implementer, so its test script is written first and reviewed by reading.
- Existing investigations and meetings keep their rows; any DO account can see and act on all of them (no per-officer ownership).
- The student and parent confirm-or-decline acknowledgement is unchanged.
- Sanctioning before findings are filed still needs a written reason (existing rule); that reason is the DO's own note and is **never** sent to Guidance.
- Root `flutter test` is the reliable suite; run package tests by path from the repo root.

## Review Focus

- A DO who is not the officer who started an investigation can still schedule, mark outcomes and complete it.
- Guidance can no longer read `guidance_investigations`, nor investigation meetings, nor receive any notification about an investigation, a meeting reply or an early sanction (including its override reason).
- A Guidance-approved endorsement's parent meeting (no investigation) still shows for Guidance and the parent.
- Existing open investigations (already `Under_Investigation` cases) appear in the DO tab with their meetings after the migration.
- The DO nav bar with six tabs must not overflow at a 1100px-wide window.
- Scheduling a meeting in the past, or on a completed investigation, is still refused.

## File Structure

- Create `supabase/add_do_investigations.sql`, `supabase/test_do_investigations.sql`.
- Modify `packages/discipline_officer_module/lib/models/discipline_case_model.dart` (`CaseStage.withGuidance` -> `underInvestigation`) and every user of it.
- Create `packages/discipline_officer_module/lib/pages/investigations/investigations_view.dart` (moved, re-chromed with `DisciplineOfficerColors`); delete the Guidance copy.
- Create `lib/data/investigation_mapping.dart` (the `GuidanceInvestigation` -> `InvestigationModel` mapper, moved out of the Guidance connected page).
- Modify `lib/ui/discipline_officer_connected_page.dart`, `lib/ui/guidance_counselor_connected_page.dart`, both dashboards, `packages/dashboard_layout/lib/src/guidance_meetings_card.dart`.
- Move `test/guidance_investigations_view_test.dart` -> `packages/discipline_officer_module/test/investigations_view_test.dart`.

---

### Task 1: Database migration

**Files:**
- Create: `supabase/add_do_investigations.sql`, `supabase/test_do_investigations.sql`

**Interfaces:**
- Produces (SQL):
  - `escalate_to_guidance`, `schedule_guidance_meeting`, `set_meeting_outcome`, `complete_investigation`: callable by `Admin` and `Discipline_Officer`; `Guidance_Counselor` is refused (errcode `42501`).
  - `respond_to_meeting` notifies `'Discipline_Officer'::app_role` (was Guidance) when it is an investigation meeting; for an endorsement meeting (`escalation_report_id` not null) it still notifies Guidance.
  - Notifications: `escalate_to_guidance` notifies nobody; `complete_investigation` notifies nobody; `schedule_guidance_meeting` texts say "meeting" not "Guidance meeting"; `record_sanction` no longer notifies Guidance on an early sanction.
  - Policies `guidance_investigations_staff_select` = Admin + DO only; `guidance_meetings_staff_select` = Admin + DO, plus Guidance when `escalation_report_id is not null`.

- [ ] **Step 1: Write `supabase/test_do_investigations.sql`** (Admin-session, rolled back, "ALL PASSED" notice, same style as `test_guidance_investigations.sql`). Assertions: (a) policy text of `guidance_investigations_staff_select` contains no `Guidance_Counselor`; (b) policy text of `guidance_meetings_staff_select` contains `escalation_report_id is not null` and `Guidance_Counselor` only inside that clause; (c) the function bodies of `schedule_guidance_meeting`, `set_meeting_outcome`, `complete_investigation` (via `pg_get_functiondef`) do not contain `'Guidance_Counselor'::app_role` in their role check; (d) `pg_get_functiondef('public.record_sanction(...)'::regprocedure)` does not insert a `'Guidance_Counselor'::app_role` notification; (e) classify -> `escalate_to_guidance` -> `schedule_guidance_meeting` (future) -> `set_meeting_outcome('Completed')` -> `complete_investigation` all succeed as the Admin session and leave the case `Investigation_Complete`; (f) scheduling in the past and on a `Complete` investigation raise; (g) no `notifications` row with `target_role = 'Guidance_Counselor'` was created by (e) (count before and after).
- [ ] **Step 2: Run it** against the pre-migration database. Expected: FAIL at (a).
- [ ] **Step 3: Write `supabase/add_do_investigations.sql`**, idempotent. `create or replace` the five functions with the same bodies as `add_guidance_investigations.sql` / `add_sanctions_schema.sql` (`record_sanction`) / `add_endorsements.sql` where only the role gates, the notification inserts and the meeting texts differ as listed under Interfaces; re-issue the policies; keep `revoke ... from public, anon` / `grant ... to authenticated` unchanged. Take `record_sanction`'s current body from the LATEST migration that defines it (grep `supabase/` first) so later changes are not lost.
- [ ] **Step 4: Re-run the test script.** Expected: "ALL PASSED", and the migration runs twice without error.
- [ ] **Step 5: Commit** `supabase/add_do_investigations.sql supabase/test_do_investigations.sql` (explicit paths).

### Task 2: "Under investigation" replaces "With Guidance" in the DO workflow

**Files:**
- Modify: `packages/discipline_officer_module/lib/models/discipline_case_model.dart`, `.../pages/dashboard/violations_view.dart`, `.../pages/dashboard/violation_history_view.dart`, `.../pages/dashboard/discipline_officer_dashboard_page.dart`, `.../widgets/case_progress_badge.dart`, plus the tests that name `withGuidance` (`grep -rn withGuidance packages lib test`)

**Interfaces:**
- Produces: `CaseStage.underInvestigation` (replaces `withGuidance`, same meaning: `status == 'Under_Investigation'`); `DisciplineCaseModel.canOverrideSanction` unchanged name; UI strings: action button `Start investigation` (was "Escalate to Guidance"), confirm dialog title `Start an investigation?` with body "...case "<violation>" becomes an investigation. Schedule meetings and file findings under Investigations, then sanction it.", button `Start`, success snackbar `Investigation started.`, stage label `Under investigation`, override button `Sanction before findings`.

- [ ] **Step 1: Update the existing tests first** to the new names and strings (`withGuidance` -> `underInvestigation`; the escalate-confirm flow asserts "Start an investigation?" and the `Key('escalate-confirm')` still taps it; the history summary label reads "Under investigation").
- [ ] **Step 2: Run** the DO package tests. Expected: FAIL (compile error on `underInvestigation`).
- [ ] **Step 3: Rename and reword** as listed; `violation_history_view.dart`'s `withGuidance` count field becomes `underInvestigation`.
- [ ] **Step 4: Run** `flutter test packages/discipline_officer_module/test test/` Expected: PASS.
- [ ] **Step 5: Commit.**

### Task 3: Move the Investigations view into the DO module and add the tab

**Files:**
- Create: `packages/discipline_officer_module/lib/pages/investigations/investigations_view.dart` (moved with `git mv`, then edited)
- Move: `test/guidance_investigations_view_test.dart` -> `packages/discipline_officer_module/test/investigations_view_test.dart`
- Modify: `packages/discipline_officer_module/lib/discipline_officer_module.dart` (export), `.../pages/dashboard/discipline_officer_dashboard_page.dart`

**Interfaces:**
- Consumes: Task 2's wording.
- Produces: `InvestigationsView({investigations, onSchedule, onSetMeetingOutcome, onComplete, onLoadEvidence})` with the same callback types as today; `InvestigationModel`, `InvestigationMeetingModel`, `MeetingFormResult`, `ScheduleMeetingDialog`, `CompleteInvestigationDialog`, `validateMeetingTime` exported from the DO module; `DashboardTab.investigations` (label `Investigations`, icon `Icons.manage_search_rounded`) after `referrals`; dashboard params `investigations`, `onScheduleMeeting`, `onSetMeetingOutcome`, `onCompleteInvestigation`, `onLoadInvestigationEvidence`.

- [ ] **Step 1: Move the test file, fix its import to the DO module, and adjust assertions to the new copy** ("You can now sanction the case." instead of "The Discipline Officer can now sanction"; the schedule dialog subtitle). Add tests: the dashboard shows an `Investigations` tab listing a given investigation; at a 1100px-wide window the nav bar of six tabs renders with no overflow exception (`tester.takeException()` is null).
- [ ] **Step 2: Run them.** Expected: FAIL (types not found / no tab).
- [ ] **Step 3: Implement.** Replace `GuidanceTableCard`, `GuidanceSearchField`, `GuidanceRowIconButton`, `GuidanceTabColors` with `TitledTableCard`, `DashboardSearchField`, `DashboardRowIconButton` and `DisciplineOfficerColors` exactly as `referrals_view.dart` in the same module does; reword "counselor" copy to "officer". Wire the tab like `referrals` (Builder for a theme-correct context). If six tabs overflow at 1100px, tighten the nav gap from 45 to 24 for all tabs or make the bar horizontally scrollable (decide by what the test shows; record it).
- [ ] **Step 4: Run** `flutter test packages/discipline_officer_module/test`. Expected: PASS.
- [ ] **Step 5: Commit.**

### Task 4: DO connected page wiring

**Files:**
- Create: `lib/data/investigation_mapping.dart`
- Modify: `lib/ui/discipline_officer_connected_page.dart`, `lib/data/guidance_investigation_repository.dart` (doc comments only: `fetchAssigned` returns every investigation the caller's role may read)
- Test: `test/investigation_mapping_test.dart`

**Interfaces:**
- Produces: `InvestigationModel toInvestigationModel(GuidanceInvestigation i)` (moved verbatim from `GuidanceCounselorConnectedPage._toInvestigationModel`).
- Consumes: Task 3's dashboard params; `GuidanceInvestigationRepository.schedule/setOutcome/complete/fetchAssigned`, `ViolationEvidenceRepository.signedUrls`.

- [ ] **Step 1: Write failing tests** in `test/investigation_mapping_test.dart`: a `GuidanceInvestigation` with two meetings maps every field (offense label, category, notes, incident time, evidence paths, findings, recommendation, meeting invitee/status/location/response note); `fetchAssigned` against the recording server maps the embedded meetings (reuse the row shape from `test/guidance_investigation_repository_test.dart`).
- [ ] **Step 2: Run it.** Expected: FAIL (file missing).
- [ ] **Step 3: Implement** the mapper file; in the DO connected page add `_investigationRepo`, `_investigations` state, load in `_load` (inside a try so a missing table does not break the dashboard), `_scheduleMeeting`, `_setMeetingOutcome`, `_completeInvestigation`, `_loadInvestigationEvidence` (same bodies as the Guidance page had), reload investigations after `_escalateCase` and after each of those, and pass the five callbacks to the dashboard; each action also logs through `_auditLogger`.
- [ ] **Step 4: Run** the new test and the root suite. Expected: PASS.
- [ ] **Step 5: Commit.**

### Task 5: Remove Investigations from Guidance

**Files:**
- Modify: `packages/guidance_counselor_module/lib/pages/dashboard/guidance_counselor_dashboard_page.dart`, `lib/ui/guidance_counselor_connected_page.dart`
- Delete: `packages/guidance_counselor_module/lib/pages/investigations/`
- Test: `packages/guidance_counselor_module/test/guidance_tabs_test.dart`

- [ ] **Step 1: Extend `guidance_tabs_test.dart`:** `GuidanceCounselorTab.values` contains no `investigations`.
- [ ] **Step 2: Run it.** Expected: FAIL.
- [ ] **Step 3: Remove** the tab value, label/icon cases, constructor params and fields (`investigations`, `onScheduleMeeting`, `onSetMeetingOutcome`, `onCompleteInvestigation`, `onLoadInvestigationEvidence`), the build case, and in the connected page the investigation state, repo, mapper use, load block, handlers and params. `GuidanceInvestigationRepository` stays (student and parent portals use it).
- [ ] **Step 4: Run** `flutter test packages/guidance_counselor_module/test` and the root suite. Expected: PASS.
- [ ] **Step 5: Commit.**

### Task 6: Neutral meeting wording, checklist, full verification

**Files:**
- Modify: `packages/dashboard_layout/lib/src/guidance_meetings_card.dart` (title `Meetings`), the student and parent portal tests that name the old title, `docs/superpowers/demo-checklist.md` (section 3 and setup list)

- [ ] **Step 1: Update the portal/card tests** to expect `Meetings` and run them. Expected: FAIL.
- [ ] **Step 2: Change** the card title; rewrite checklist section 3 so the DO classifies, **starts the investigation**, schedules the meeting, the parent declines then confirms, the DO marks it completed and files findings, then sanctions; add `add_do_investigations.sql` to the setup order (after `add_endorsements.sql`) and extend the "older scripts undo it" note to `add_guidance_investigations.sql` and `add_sanctions_schema.sql`.
- [ ] **Step 3: Run** `flutter test` (root), both package suites by path, and `flutter analyze lib packages/discipline_officer_module/lib packages/guidance_counselor_module/lib packages/dashboard_layout/lib`. Expected: all pass, no analyzer errors.
- [ ] **Step 4: Commit.**

---

## Self-review notes

- Spec coverage: goal 1 (DO files, processes, schedules, completes) is Tasks 1-5; the deferred piece-1 item (override reason reaching Guidance) is Task 1; neutral meeting wording for students and parents is Task 6. Goals 2-9 are pieces 1, 3 and 4.
- Deliberately not here: renaming RPCs/tables, per-officer ownership, Guidance ever marking an endorsement meeting's outcome (it has no UI for it today), the ML/analysis read path (piece 4).
