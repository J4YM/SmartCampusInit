# Parent-Availability Scheduling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** After Guidance approves an endorsement, the DO requests the parent's availability, the parent offers times in the Parent Portal, and Guidance approves one slot to make the meeting official. Also: DO marks each investigation Proven / Not Proven and can sanction proven students, and the DO keeps visibility of the endorsement meeting.

**Architecture:** Two new tables (`meeting_availability_rounds`, `meeting_availability_slots`) hold the request/offer/decline cycle. Approving a slot creates a normal `guidance_meetings` row (status `Proposed`, `escalation_report_id` set), so the existing respond/outcome/DO-notification code keeps working and the `guidance_meetings` status check is untouched. The old DO-propose / Guidance-confirm RPCs stay as the fallback (excluded parents, manual step-in, in-flight meetings). All logic is SQL RPCs called from Dart repositories.

**Tech Stack:** Flutter/Dart monorepo (`lib/`, `packages/*`), Supabase Postgres (RPCs, RLS, pg_cron, `queue_sms`), loose idempotent `supabase/*.sql` migrations run by hand, SQL assertion scripts `supabase/test_*.sql`, `flutter test`.

**Spec:** `docs/superpowers/specs/2026-11-18-parent-availability-scheduling-design.md`

## Global Constraints

- SMS text max 300 characters; times formatted `to_char(x at time zone 'Asia/Manila', 'Mon DD, YYYY HH12:MI AM')`.
- Parent must never see a meeting as confirmed before Guidance approves.
- A date+time declined by Guidance is never accepted again for the same endorsement (`escalation_report_id`).
- Excluded parents (`escalation_reports.exclude_parent`) are never asked for availability; they use the existing propose/confirm flow, unchanged.
- Parent offers 1 to 10 slots, each date + start time, each in the future.
- Reminder: one reminder after 48 hours with no parent response, SMS + portal. DO/Guidance can cancel the round at any time and fall back to the old flow.
- Meetings already `Awaiting_Guidance` / `Returned` finish under the old flow; no conversion.
- Migrations idempotent (`create ... if not exists`, `create or replace`, `drop policy if exists`); RPCs `security definer`, `set search_path = public`, `revoke all ... from public, anon`, `grant execute ... to authenticated`.
- Roles: DO acts as `Discipline_Officer` or `Admin`; Guidance as `Guidance_Counselor` or `Admin`; parents via `parent_student_links (parent_id, student_id)`.
- Investigations are one per violation and a violation has one student, so "each student Proven / Not Proven" is one verdict per investigation.

## Review Focus

1. Parent submits duplicate slots, a past time, or a time already declined for this endorsement: rejected with a clear message, nothing partially saved. (Task 1)
2. Two linked parents answer the same round at once: first wins, second gets "already answered"; no double meeting. (Task 1)
3. Endorsement whose student has no linked parent: DO request fails with a clear message pointing to manual scheduling. (Task 1)
4. Guidance approves a slot id that belongs to another round, or approves an already-decided round: rejected. (Task 2)
5. Sanction attempted for a Not Proven student, or verdict changed after a sanction exists: rejected. (Task 3)

## File Structure

- Create `supabase/add_parent_availability_scheduling.sql`: tables, RLS, SMS helpers, RPCs (request, submit, decide, cancel, remind), cron, `propose_endorsement_meeting` guard.
- Create `supabase/test_parent_availability_scheduling.sql`: assertions (Tasks 1, 2).
- Create `supabase/add_investigation_outcome.sql` and `supabase/test_investigation_outcome.sql`: Proven / Not Proven (Task 3).
- Create `lib/data/models/parent_availability_round.dart` (model) and extend `lib/data/escalation_repository.dart`, `lib/data/referrals_repository.dart`, `lib/data/guidance_investigation_repository.dart`, `lib/data/investigation_mapping.dart`.
- Create `packages/parent_portal_module/lib/widgets/availability_request_card.dart`; modify `lib/ui/parent_portal_connected_page.dart`.
- Modify `packages/guidance_counselor_module/lib/pages/referrals/referrals_view.dart`, `packages/discipline_officer_module/lib/pages/dashboard/endorsements_view.dart`, `packages/discipline_officer_module/lib/pages/investigations/investigations_view.dart`.

---

### Task 1: Availability schema, request and submit RPCs

**Files:**
- Create: `supabase/add_parent_availability_scheduling.sql`
- Test: `supabase/test_parent_availability_scheduling.sql` (follow the header/rollback conventions of `supabase/test_endorsement_meetings.sql`; needs a student with a linked parent)

**Interfaces:**
- Produces tables: `meeting_availability_rounds(id uuid pk, escalation_report_id uuid not null, student_id uuid not null, round_no int, status text check in ('Open','Offered','Approved','Declined','Cancelled'), requested_by uuid, requested_at timestamptz, reminded_at timestamptz, offered_at timestamptz, decided_at timestamptz, decision_note text, meeting_id uuid null)`; `meeting_availability_slots(id uuid pk, round_id uuid, slot_at timestamptz, status text check in ('Offered','Approved','Declined','Not_Chosen'))`.
- Produces SMS helpers: `availability_request_sms(p_name text, p_school text) returns text`, `availability_retry_sms(p_name text, p_school text) returns text`, `meeting_scheduled_sms(p_when text, p_where text, p_name text, p_school text) returns text` (all <= 300 chars, tell the parent to open the Parent Portal).
- Produces RPCs: `request_parent_availability(p_report_id uuid) returns uuid` (DO/Admin; round id); `submit_parent_availability(p_round_id uuid, p_slots timestamptz[]) returns void` (linked parent).

- [ ] **Step 1: Write failing assertions** in the test script: (a) `request_parent_availability` on an Approved, non-excluded endorsement returns a round with status `Open`, round_no 1, and creates a Parent notification and an `sms_outbox` row; (b) it raises for an excluded-parent endorsement, for a Pending_GC endorsement, when an Open/Offered round already exists, and for a student with no linked parent (Review Focus 3); (c) `submit_parent_availability` with 2 future slots sets round `Offered`, creates 2 `Offered` slots, and notifies DO and Guidance roles; (d) it raises for 0 slots, 11 slots, a past slot, duplicate slots (Review Focus 1), and when the round is not `Open` (Review Focus 2); (e) a `Declined` slot from an earlier round of the same endorsement is rejected as a re-offer (insert such a slot directly for the test).
- [ ] **Step 2: Run it before the migration** in the Supabase SQL Editor (Admin session, dev project). Expected: fails (functions missing).
- [ ] **Step 3: Implement the tables and RLS** in the migration: RLS enabled; select policies for Admin / Discipline_Officer / Guidance_Counselor, and for parents linked to the round's student; no insert/update/delete policies (RPC only).
- [ ] **Step 4: Implement the three SMS helpers.** Mirror `meeting_invitation_sms` in `supabase/reword_meeting_invitations.sql:22-54` (truncation to 300, school name from `sms_settings`).
- [ ] **Step 5: Implement `request_parent_availability`.** Lock the endorsement row; require `status = 'Approved'`, `exclude_parent = false`, no round in `Open`/`Offered`, at least one `parent_student_links` row; round_no = previous max + 1; insert Parent notifications (title `Meeting availability requested`), call `queue_sms('guidance_meeting', student_id, round_id, availability_request_sms(...))` inside a `begin ... exception when others then raise warning` block like `confirm_endorsement_meeting`; notify role `Guidance_Counselor` that a request is out; `log_audit`.
- [ ] **Step 6: Implement `submit_parent_availability`.** Caller must be linked to the round's student; lock the round `for update`, require `Open`; validate 1-10 distinct slots, all `> now()`, none equal to a `Declined` slot on any round of the same `escalation_report_id`; insert slots, set round `Offered` and `offered_at`; notify `Discipline_Officer` and `Guidance_Counselor` roles ("Parent offered N time(s)"); notify the other linked parents that it was answered.
- [ ] **Step 7: Re-run the migration then the test.** Expected: prints `ALL PASSED` (use the same final `raise notice 'ALL PASSED'` style as the existing tests).
- [ ] **Step 8: Commit** `git add supabase/add_parent_availability_scheduling.sql supabase/test_parent_availability_scheduling.sql && git commit -m "feat: parent availability rounds, request and submit RPCs"`

---

### Task 2: Decide, cancel, remind, and old-flow guard

**Files:**
- Modify: `supabase/add_parent_availability_scheduling.sql`
- Modify: `supabase/test_parent_availability_scheduling.sql`

**Interfaces:**
- Consumes: Task 1 tables and helpers.
- Produces: `decide_parent_availability(p_round_id uuid, p_slot_id uuid default null, p_location text default null, p_note text default null) returns void` (Guidance/Admin; `p_slot_id` null means decline); `cancel_parent_availability(p_round_id uuid) returns void` (DO/Guidance/Admin); `remind_stale_availability_rounds() returns int` (count reminded).

- [ ] **Step 1: Add failing assertions**: (a) approving a slot makes the round `Approved`, that slot `Approved`, other slots `Not_Chosen`, creates one `guidance_meetings` row (`status = 'Proposed'`, `escalation_report_id` set, `invitee = 'parent'`, `scheduled_at` = slot, `location` default `'Guidance Office'` unless provided) stored in `meeting_id`, notifies Parent + DO, queues the `meeting_scheduled_sms` row; (b) declining (`p_slot_id` null) marks all slots `Declined`, round `Declined`, and opens a new `Open` round with `round_no + 1`, with a retry SMS queued and DO notified; (c) after a decline the declined time is rejected by `submit_parent_availability` (links Task 1 rule); (d) a slot from another round, a round not `Offered`, and a past slot are rejected (Review Focus 4); (e) `cancel_parent_availability` sets `Cancelled` for an `Open` or `Offered` round and then `propose_endorsement_meeting` works; while a round is `Open`/`Offered`, `propose_endorsement_meeting` raises "cancel the availability request first"; (f) `remind_stale_availability_rounds` reminds an `Open` round whose `requested_at` is 49 hours old exactly once (second call returns 0) and ignores a 1-hour-old round.
- [ ] **Step 2: Run to confirm failure.**
- [ ] **Step 3: Implement `decide_parent_availability`.** Lock round `for update`, require `Offered` and Guidance/Admin. Approve path: slot must belong to the round and not be in the past (raise otherwise); cancel the endorsement's other live meetings the same way `confirm_endorsement_meeting` does (`supabase/add_endorsement_meetings.sql:137`); insert the meeting; notifications for Parent (title `Meeting scheduled`), Student if the endorsement's invitee rules would include them (follow `confirm_endorsement_meeting`), and DO (title `Meeting scheduled by Guidance`). Decline path: as in the test; new round gets `requested_by` of the previous round and `requested_at = now()`.
- [ ] **Step 4: Implement `cancel_parent_availability`** (only `Open`/`Offered`; notify the other of DO/Guidance; no SMS).
- [ ] **Step 5: Implement `remind_stale_availability_rounds`**: for `Open` rounds with `reminded_at is null` and `requested_at < now() - interval '48 hours'`, send a portal notification + `availability_request_sms`, notify DO, set `reminded_at`. Schedule it hourly with pg_cron using the same idempotent unschedule/schedule pattern as other cron setup in `supabase/add_sms_alerts_schema.sql`.
- [ ] **Step 6: Re-issue `propose_endorsement_meeting`** (current body at `supabase/add_endorsement_meetings.sql:62`) with the guard from (e); everything else unchanged.
- [ ] **Step 7: Run migration then test.** Expected: `ALL PASSED`; also re-run `supabase/test_endorsement_meetings.sql`, expected: `ALL PASSED` (old flow unaffected).
- [ ] **Step 8: Commit** `git commit -am "feat: decide, cancel and remind for parent availability"` (add new files if any).

---

### Task 3: Proven / Not Proven and sanction guard

**Files:**
- Create: `supabase/add_investigation_outcome.sql`, `supabase/test_investigation_outcome.sql` (header conventions as `supabase/test_do_investigations.sql`)

**Interfaces:**
- Produces: column `guidance_investigations.outcome text check (outcome in ('Proven','Not_Proven'))` (null only for `Open` investigations); `complete_investigation(p_investigation_id uuid, p_findings text, p_outcome text, p_recommendation text default null) returns void` (replaces the old 3-argument version: drop it); `set_investigation_outcome(p_investigation_id uuid, p_outcome text) returns void` (DO/Admin).
- Consumes: existing `complete_investigation` body in `supabase/add_do_investigations.sql:305`, `record_sanction` in `supabase/add_sanctions_schema.sql:142`.

- [ ] **Step 1: Write failing assertions**: completing without an outcome or with a value other than `Proven`/`Not_Proven` raises; completing stores the outcome; `record_sanction` on a violation whose investigation is `Complete` with `Not_Proven` raises (Review Focus 5); `record_sanction` still works for `Proven`, and for a violation whose investigation is still `Open` (existing early-sanction behavior); `set_investigation_outcome` flips the verdict only when no sanction exists for the violation, else raises; existing completed rows are backfilled so nothing is null (backfill `Proven` where the violation already has a sanction, otherwise leave null and treat null on `Complete` as allowed for legacy rows).
- [ ] **Step 2: Run to confirm failure.**
- [ ] **Step 3: Implement the migration**: add the column; drop the old `complete_investigation(uuid,text,text)`, create the new one keeping all existing behavior (violation to `Investigation_Complete`, DO-only, findings required, locking order) plus outcome; add `set_investigation_outcome`; re-issue `record_sanction` with the Not Proven guard only (rest unchanged).
- [ ] **Step 4: Run migration then test.** Expected: `ALL PASSED`; re-run `supabase/test_do_investigations.sql` after updating its `complete_investigation` calls to pass an outcome. Expected: `ALL PASSED`.
- [ ] **Step 5: Commit** `git commit -am "feat: investigation proven/not proven outcome and sanction guard"`

---

### Task 4: Dart data layer

**Files:**
- Create: `lib/data/models/parent_availability_round.dart` (model `ParentAvailabilityRound`: `id`, `escalationReportId`, `studentId`, `roundNo`, `status`, `requestedAt`, `offeredAt`, `meetingId`, `slots` as `List<AvailabilitySlot>` with `id`, `slotAt`, `status`; `fromJson`)
- Modify: `lib/data/escalation_repository.dart` (near `proposeEndorsementMeeting`, line ~148), `lib/data/referrals_repository.dart` (near `confirmEndorsementMeeting`, line ~80), `lib/data/guidance_investigation_repository.dart`, `lib/data/investigation_mapping.dart`
- Test: `test/parent_availability_repository_test.dart`; extend `test/referrals_repository_test.dart`, `test/guidance_investigation_repository_test.dart`, `test/investigation_mapping_test.dart` (follow how these existing tests fake the Supabase client)

**Interfaces:**
- Consumes: RPC names/params from Tasks 1-3.
- Produces: `EscalationRepository.requestParentAvailability(String reportId) -> Future<String>`, `.cancelParentAvailability(String roundId) -> Future<void>`, `.fetchAvailabilityRounds(List<String> reportIds) -> Future<List<ParentAvailabilityRound>>`; `ReferralsRepository.fetchOfferedRounds() -> Future<List<ParentAvailabilityRound>>`, `.decideParentAvailability({required String roundId, String? slotId, String? location, String? note}) -> Future<void>`; parent-side `submitParentAvailability(String roundId, List<DateTime> slots) -> Future<void>` and `fetchMyOpenRounds() -> Future<List<ParentAvailabilityRound>>` on the repository the parent page already uses for meetings (see `_loadMeetings`, `lib/ui/parent_portal_connected_page.dart:339`); `GuidanceInvestigationRepository.completeInvestigation(..., required String outcome)` and `.setOutcome(String investigationId, String outcome)`; the mapped investigation model gains `String? outcome`.

- [ ] **Step 1: Write failing tests** asserting each method calls the expected RPC with exact parameter names (`p_report_id`, `p_round_id`, `p_slots` as UTC ISO strings, `p_slot_id`, `p_location`, `p_note`, `p_outcome`) and that `ParentAvailabilityRound.fromJson` parses a round with nested slots.
- [ ] **Step 2: Run** `flutter test test/parent_availability_repository_test.dart test/referrals_repository_test.dart test/guidance_investigation_repository_test.dart test/investigation_mapping_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement** the model and methods as listed.
- [ ] **Step 4: Re-run the same command.** Expected: PASS.
- [ ] **Step 5: Commit** `git add lib test && git commit -m "feat: data layer for parent availability and investigation outcome"`

---

### Task 5: Parent portal availability card

**Files:**
- Create: `packages/parent_portal_module/lib/widgets/availability_request_card.dart`
- Modify: `packages/parent_portal_module/lib/pages/parent_portal_home_page.dart` (place above `GuidanceMeetingsCard`, ~line 713), `lib/ui/parent_portal_connected_page.dart` (load rounds like `_loadMeetings`; add `_submitAvailability` like `_respondToMeeting` at 362; pass `initialAvailabilityRequests` and `onSubmitAvailability` at ~527)
- Test: `packages/parent_portal_module/test/availability_request_card_test.dart`; extend `test/parent_portal_connected_page_test.dart`

**Interfaces:**
- Consumes: `ParentAvailabilityRound` and parent repository methods (Task 4).
- Produces: `AvailabilityRequestCard({required List<ParentAvailabilityRound> rounds, required Future<void> Function(String roundId, List<DateTime> slots) onSubmit})`.

- [ ] **Step 1: Write failing widget tests**: card is hidden when there are no `Open` rounds; shows one date/time row initially, "Add another time" adds a row up to 10; Submit is disabled until the first row has date and time; tapping Submit calls `onSubmit(roundId, slots)` with the chosen DateTimes; past times show an inline error and do not call `onSubmit`; a round whose `roundNo > 1` shows the text "Guidance could not make the previous times. Please pick other dates." (Interactions use `showDatePicker`/`showTimePicker`; reuse the picker styling in `packages/dashboard_layout/lib/src/schedule_meeting_dialog.dart`.)
- [ ] **Step 2: Run** `cd packages/parent_portal_module && flutter test test/availability_request_card_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement the card** (a `StatefulWidget` holding the list of picked `DateTime?` rows) and wire it into the home page and connected page; after a successful submit, reload rounds so the card disappears.
- [ ] **Step 4: Run** the new test, then `flutter test test/parent_portal_connected_page_test.dart` from the repo root. Expected: PASS.
- [ ] **Step 5: Commit** `git add -A packages/parent_portal_module lib/ui test && git commit -m "feat: parent portal availability card"`

---

### Task 6: Guidance approves or declines offered times

**Files:**
- Modify: `packages/guidance_counselor_module/lib/pages/referrals/referrals_view.dart` (new section above the existing confirm list; reuse the confirm card styling around `_confirm` ~186)
- Test: extend `packages/guidance_counselor_module/test/referrals_view_test.dart`

**Interfaces:**
- Consumes: `ReferralsRepository.fetchOfferedRounds`, `.decideParentAvailability` (Task 4). Wire through the same callback style the view already uses for confirm/return.
- Produces: a section titled "Parent availability" listing each `Offered` round with student name, endorsement title and one selectable tile per slot, plus buttons "Approve selected time" (optional location field) and "None of these work" (optional note).

- [ ] **Step 1: Write failing widget tests**: with one offered round of 2 slots the section shows both times; "Approve selected time" is disabled until a slot is chosen and then calls the callback with `roundId`, `slotId`, `location`; "None of these work" calls it with `slotId: null` and the note; with no offered rounds the section is absent; existing referrals tests still pass.
- [ ] **Step 2: Run** `cd packages/guidance_counselor_module && flutter test test/referrals_view_test.dart`. Expected: FAIL on the new tests.
- [ ] **Step 3: Implement the section and callbacks**; also thread new constructor parameters through the page that builds `ReferralsView` in the app.
- [ ] **Step 4: Re-run.** Expected: PASS.
- [ ] **Step 5: Commit** `git add -A packages/guidance_counselor_module lib && git commit -m "feat: guidance approves parent-offered times"`

---

### Task 7: DO request, status and linked meeting in Endorsements

**Files:**
- Modify: `packages/discipline_officer_module/lib/pages/dashboard/endorsements_view.dart` (`_ReportTile` ~632, which currently opens `ScheduleMeetingDialog` at ~644), `packages/discipline_officer_module/lib/models/escalation_report_model.dart` (carry the round and linked meeting)
- Test: extend `packages/discipline_officer_module/test/endorsements_view_test.dart`

**Interfaces:**
- Consumes: `EscalationRepository.requestParentAvailability`, `.cancelParentAvailability`, `.fetchAvailabilityRounds` (Task 4); existing meeting list for an endorsement and `set_meeting_outcome` wiring.
- Produces: for an `Approved` endorsement with `excludeParent == false`: primary action "Request parent availability" (replaces "Schedule meeting"); while a round is `Open`: chip "Waiting for parent" and "Schedule manually instead" (cancels the round, then opens the existing `ScheduleMeetingDialog`); `Offered`: chip "Waiting for Guidance"; `Declined` re-ask shows "Round N: parent asked again". For `excludeParent == true` the old "Schedule meeting" button is unchanged. Once a meeting exists for the endorsement, the tile shows its date, location and status and the existing outcome actions (Completed / Missed / Cancelled).

- [ ] **Step 1: Write failing widget tests** for each state above: non-excluded Approved shows "Request parent availability" and tapping calls the request callback; excluded shows the old button; `Open` round shows the chip and the manual fallback, which calls cancel then opens the dialog; `Offered` shows the Guidance chip; a linked meeting with status `Proposed` shows date, location and status text and the outcome actions appear only for statuses allowed by `set_meeting_outcome` (`Proposed`, `Confirmed`, `Declined`, `Reschedule_Requested`).
- [ ] **Step 2: Run** `cd packages/discipline_officer_module && flutter test test/endorsements_view_test.dart`. Expected: FAIL on new tests.
- [ ] **Step 3: Implement** the tile changes, model fields and callbacks; thread new parameters through the app page that hosts the view.
- [ ] **Step 4: Re-run.** Expected: PASS.
- [ ] **Step 5: Commit** `git add -A packages/discipline_officer_module lib && git commit -m "feat: DO requests availability and tracks endorsement meetings"`

---

### Task 8: DO marks Proven / Not Proven and sanctions

**Files:**
- Modify: `packages/discipline_officer_module/lib/pages/investigations/investigations_view.dart`
- Test: extend `packages/discipline_officer_module/test/investigations_view_test.dart`

**Interfaces:**
- Consumes: `completeInvestigation(..., outcome)` and `setOutcome` (Task 4); existing `packages/discipline_officer_module/lib/pages/dashboard/sanction_dialog.dart` and its sanction callback as already used by `violations_view.dart`.
- Produces: the complete-investigation dialog gets a required two-option control "Proven" / "Not proven" (no default selected; Complete disabled until chosen); a completed investigation row shows an outcome badge; when `Proven` and not yet sanctioned it shows "Record sanction" opening `sanction_dialog`; when `Not_Proven` no sanction action is shown; the verdict can be changed (calls `setOutcome`) until a sanction exists.

- [ ] **Step 1: Write failing widget tests**: Complete is disabled with findings but no verdict; choosing "Proven" and completing passes `outcome: 'Proven'`; a completed `Proven` investigation shows the badge and "Record sanction"; a `Not_Proven` one shows the badge and no sanction button; a sanctioned `Proven` one hides the change-verdict action.
- [ ] **Step 2: Run** `cd packages/discipline_officer_module && flutter test test/investigations_view_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement** the dialog control, badge and actions.
- [ ] **Step 4: Re-run, then the full suites** `flutter test` at the repo root and in `packages/discipline_officer_module`, `packages/guidance_counselor_module`, `packages/parent_portal_module`. Expected: all PASS.
- [ ] **Step 5: Commit** `git add -A packages/discipline_officer_module && git commit -m "feat: DO marks investigations proven or not proven and records sanctions"`

---

## Self-Review Notes

- Spec coverage: request-first flow (T1), parent 1..N slots and portal-only communication (T1, T5), DO and Guidance notified (T1), Guidance approval makes it official (T2, T6), decline loop with exclusion and SMS (T2), SMS wording (T1 helpers), reminder and step-in (T2, T7), excluded-parent old flow and in-flight meetings untouched (T2 guard only blocks while a round is open), Proven / Not Proven and sanction (T3, T8), DO link to approved meeting (T2 notification, T7 display).
- Deployment note: run the two migrations in the SQL Editor in order (`add_parent_availability_scheduling.sql`, `add_investigation_outcome.sql`) before shipping the app build, since the app calls the new RPCs.
