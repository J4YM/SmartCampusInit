# Endorsement Meetings, Invitation Wording, No Auto Tap-Out, "Other" Intervention Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** (1) The DO arranges the meeting for an endorsement Guidance accepted; Guidance confirms (or changes / returns it) before anyone is invited, and can see its status. (2) Every meeting invitation reads "You are invited to a meeting on …". (3) Stop auto-tapping students out at 6:30 PM; show "Did not tap out" instead and keep the SMS. (4) Endorsements get an "Other" intervention kind and an "exclude the parent" option.

**Architecture:** SQL first (new migration files, same conventions as `add_referral_meetings.sql`: idempotent, run in the Supabase SQL Editor, a `test_*.sql` next to each), then the Flutter screens that call them. Endorsement meetings reuse `guidance_meetings` (`escalation_report_id` already links them) with two new statuses; the invitation text lives in one SQL helper so every scheduler uses it.

**Tech Stack:** Flutter/Dart, Supabase (Postgres RLS, SECURITY DEFINER RPCs, `notifications`, `queue_sms`, pg_cron).

**Spec:** the requester's answers recorded under "Decisions" (no separate spec file).

## Decisions (from the requester)

- The DO schedules the meeting for an endorsement he made, **after Guidance has accepted it**, for the `student`, the `parent` or `both`, whether or not Guidance is the one handling it. The only meetings Guidance creates itself are for Self Referrals.
- That meeting is a **proposal**. Guidance **confirms** it (and may change the time/place) or **returns** it to the DO with a recommendation. Only after Guidance confirms are the student / parent notified. The invitee then confirms or declines in their portal, as today.
- A DO meeting that is not for an endorsement (investigations) is unchanged: no Guidance confirmation.
- Guidance, after accepting an endorsement, must be able to see the status of that student's meeting (in its Referrals tab).
- Meeting text (SMS and in-app, all meeting kinds) starts with "You are invited to a meeting on …"; the parent's version also says which student.
- Remove the 6:30 PM job that inserts an automatic tap-out. Keep the SMS that tells the parent the student did not tap out today. The day shows **Did not tap out** everywhere taps are shown (Registrar activity log, Professor view, Student and Parent portals). Old automatic tap-outs are relabelled the same way.
- Endorse dialog gets **Other** (with a description). Other never messages the parent. A checkbox **Exclude the parent** keeps the parent out of the endorsement's messages and meeting invitations (the DO can then invite only the student).

## Assumptions to confirm at review

1. Old automatic tap-outs are converted into "did not tap out" records and the fabricated `out` taps are deleted (so history reads "Did not tap out", not a time).
2. "Exclude the parent" is offered for the **Counseling** and **Other** kinds (default on for Other, off for Counseling); it is not offered for kinds that exist to message the parent.
3. A returned meeting (Guidance declined with a note) is cancelled, and the DO arranges a new one.

## Global Constraints

- SQL files idempotent, header states run order; meeting times in `Asia/Manila`, `'Mon DD, YYYY HH12:MI AM'`; a meeting must be in the future.
- SMS plain ASCII, ≤ 300 characters; wrapped in `begin … exception when others then raise warning` so a failure never blocks the meeting.
- The parent is never notified of a student-only or parent-excluded meeting.
- Guidance never schedules a meeting except for a Self Referral (it confirms / changes / returns endorsement meetings).

## Review Focus

- A parent-excluded endorsement: DO cannot propose `parent`/`both`; no parent notification or SMS anywhere.
- Guidance confirms with a changed time: invitees see the **new** time; the DO is told it changed.
- A returned or already-confirmed meeting cannot be confirmed twice or confirmed after the time has passed.
- The 6:30 job run twice, or for a student who tapped out late, sends at most one "did not tap out" SMS per student per school day.
- Students with no tap that day get no "did not tap out" record or SMS.
- Old auto tap-outs: after migration no `auto_generated` rows remain and a late real tap still records normally.

---

## File Structure

| File | Responsibility |
|---|---|
| `supabase/add_endorsement_other_kind.sql` (+ `test_endorsement_other_kind.sql`) | `kind = 'other'`, `other_description`, `exclude_parent`; approval path treats Other like counseling |
| `supabase/add_endorsement_meetings.sql` (+ `test_endorsement_meetings.sql`) | `Awaiting_Guidance` / `Returned` statuses, `propose_endorsement_meeting`, `confirm_endorsement_meeting`, `return_endorsement_meeting`, approval no longer schedules, reply routing |
| `supabase/reword_meeting_invitations.sql` (+ `test_meeting_invitations.sql`) | `meeting_invitation_text()` helper; `schedule_guidance_meeting`, `schedule_referral_meeting` use it |
| `supabase/replace_auto_tap_out.sql` (+ `test_missed_tap_outs.sql`) | `missed_tap_outs`, new nightly job + SMS, old auto taps converted, cron swapped |
| `packages/discipline_officer_module/lib/models/escalation_report_model.dart`, `pages/dashboard/endorsements_view.dart` | `EndorsementKind.other`, description, exclude-parent, DO meetings on approved endorsements |
| `lib/data/escalation_repository.dart` | payload fields, `proposeMeeting`, meetings embed, `decide` without meeting args |
| `packages/guidance_counselor_module/lib/pages/escalation/escalation_approvals_view.dart` | approve dialog loses the meeting picker; shows Other description |
| `packages/guidance_counselor_module/lib/pages/referrals/*`, `lib/data/referrals_repository.dart` | endorsement meetings on the Referrals tab with Confirm / Change / Return |
| `lib/data/attendance_activity_repository.dart`, `lib/data/professor_repository.dart`, `packages/professor_module/.../professor_dashboard_page.dart`, student/parent `day_detail_sheet.dart` + repositories | "Did not tap out" |

---

### Task 1: "Other" intervention and exclude-parent (database)

**Files:** Create `supabase/add_endorsement_other_kind.sql`, `supabase/test_endorsement_other_kind.sql`.

**Interfaces:**
- Produces: `escalation_reports.kind` allows `'other'`; `other_description text`; `exclude_parent boolean not null default false`. `escalation_reports_channels_check` becomes `channels <@ array['sms','email'] and (kind in ('counseling','other') or cardinality(channels) > 0)`. `decide_escalation_report(p_id, p_approve, p_note, p_message, p_actor_name)` (5 args; the 7-arg version is dropped here, the meeting is arranged in Task 2) treats `other` exactly like `counseling` (no parent message). `trg_referral_from_endorsement` puts `other_description` into the referral `details`.

- [ ] **Step 1: Write `test_endorsement_other_kind.sql`:** (a) an `other` endorsement with `channels = '{}'`, description "Peer mediation" is accepted; (b) approving it creates no `parent_interventions` row; (c) `kind = 'bogus'` is refused; (d) the referral created on approval has details containing "Peer mediation".
- [ ] **Step 2: Run it; expect FAIL** (check constraint).
- [ ] **Step 3: Write the migration:** widen the kind and channels checks, add the two columns, drop the 7-arg `decide_escalation_report` and recreate the 5-arg one from `add_endorsements.sql` §5 with the counseling branch `if r.kind in ('counseling','other')` and the meeting block removed; replace `trg_referral_from_endorsement` to append the description.
- [ ] **Step 4: Run migration then test; expect `ALL PASSED`.**
- [ ] **Step 5: Commit** `feat(endorsements): Other intervention kind and exclude-parent flag`.

### Task 2: DO proposes, Guidance confirms (database)

**Files:** Create `supabase/add_endorsement_meetings.sql`, `supabase/test_endorsement_meetings.sql`.

**Interfaces:**
- Consumes: Task 1 (`exclude_parent`), `guidance_meetings.escalation_report_id` (existing).
- Produces:
  - `guidance_meetings.status` check adds `'Awaiting_Guidance'` and `'Returned'`; column `guidance_note text`.
  - `propose_endorsement_meeting(p_escalation_id uuid, p_scheduled_at timestamptz, p_location text, p_invitee text) returns uuid` — `Admin`/`Discipline_Officer`; endorsement must be `Approved`; future time; if `exclude_parent` then `p_invitee` must be `'student'`; cancels the endorsement's open meetings; inserts status `Awaiting_Guidance`; notifies `Guidance_Counselor` ("Meeting awaiting your confirmation"); **no invitee is notified**.
  - `confirm_endorsement_meeting(p_meeting_id uuid, p_scheduled_at timestamptz default null, p_location text default null) returns void` — `Admin`/`Guidance_Counselor`; only from `Awaiting_Guidance`; a given time must be in the future; applies the changes, sets `Proposed`, then notifies the invitees (student: portal notification; parent/both: portal notification + SMS, using `meeting_invitation_text`, Task 3) and tells the DO (stating if the time/place changed).
  - `return_endorsement_meeting(p_meeting_id uuid, p_note text) returns void` — Guidance; note required; status `Returned`; notifies the DO with the recommendation.
  - `respond_to_meeting` notifies the DO **and** Guidance when `escalation_report_id` is set; `set_meeting_outcome` also allows Guidance for endorsement meetings; `Awaiting_Guidance` counts as open in both.
  - `decide_escalation_report` no longer schedules (done in Task 1).
  - Guidance (and the DO) read meetings that have `escalation_report_id`.

- [ ] **Step 1: Write `test_endorsement_meetings.sql`:** (a) propose by DO → one `Awaiting_Guidance` row, a Guidance notification, **zero** student/parent notifications and zero SMS; (b) confirm → student notified; parent + exactly one SMS only for `parent`/`both`; none for `student`; (c) confirm with a new time → stored time changes and the DO notification says so; (d) return with a note → status `Returned`, DO notified, cannot then be confirmed; (e) an endorsement with `exclude_parent = true` refuses `parent`/`both`; (f) a past time and a non-`Approved` endorsement are refused; (g) a Guidance role calling `propose_endorsement_meeting` is refused.
- [ ] **Step 2: Run; expect FAIL.**
- [ ] **Step 3: Implement** the three RPCs and the two replaced functions, modelled on `schedule_referral_meeting` (`add_referral_meetings.sql`) and `respond_to_meeting` / `set_meeting_outcome` there.
- [ ] **Step 4: Run migration then test; expect `ALL PASSED`.**
- [ ] **Step 5: Commit** `feat(meetings): DO proposes endorsement meetings, Guidance confirms`.

### Task 3: "You are invited to a meeting on …" (database)

**Files:** Create `supabase/reword_meeting_invitations.sql`, `supabase/test_meeting_invitations.sql`.

**Interfaces:**
- Produces: `meeting_invitation_text(p_when text, p_where text, p_student_name text default null, p_confirm_in text) returns text`:
  - student: `You are invited to a meeting on {when}{ at {where}}. Please confirm in your dashboard.`
  - parent (student name given): `You are invited to a meeting on {when}{ at {where}} regarding {name}. Please confirm in the Parent Portal.`
  - SMS = the same sentence followed by ` - {school_name}`; ASCII, ≤ 300 chars.
  - `schedule_guidance_meeting` (investigations) and `schedule_referral_meeting` replaced to use it for notifications **and** SMS; `confirm_endorsement_meeting` (Task 2) calls it too.

- [ ] **Step 1: Write the test:** the helper returns the exact student and parent strings above for a known date/location; with no location there is no " at "; the SMS version starts with "You are invited to a meeting on" and is ≤ 300 chars with a long location; scheduling a referral meeting for `parent` queues an SMS whose text starts "You are invited to a meeting on".
- [ ] **Step 2: Run; expect FAIL.** **Step 3: Implement** the helper and replace the two schedulers (copy the current bodies from `add_do_investigations.sql:108-197` and `add_referral_meetings.sql`, swapping only the message text). **Step 4: Run migration then test; expect pass.**
- [ ] **Step 5: Commit** `feat(meetings): invitations open with "You are invited to a meeting"`.

### Task 4: No automatic tap-out; "did not tap out" (database)

**Files:** Create `supabase/replace_auto_tap_out.sql`, `supabase/test_missed_tap_outs.sql`.

**Interfaces:**
- Produces:
  - `missed_tap_outs(student_id uuid, school_day date, created_at timestamptz, primary key (student_id, school_day))`, readable by staff, the student, and linked parents (RLS like `guidance_meetings_student_select` / `_parent_select`).
  - `record_missed_tap_outs(p_run_at timestamptz default now()) returns int`: for each student whose latest tap of the school day is still `in`, inserts a `missed_tap_outs` row (conflict do nothing) and, only for newly inserted rows, queues the SMS `"{school}: {name} did not tap out today."` via `queue_sms('no_tap_out', …)` and one staff notification ("Students not tapped out", reworded to "did not tap out"). **Inserts no tap event.**
  - Cron: `auto-tap-out-open-students` unscheduled; `missed-tap-outs` scheduled at the same time (`30 10 * * *`).
  - `auto_tap_out_open_students` dropped. Existing `rfid_tap_events` rows with `auto_generated = true` become `missed_tap_outs` rows (their school day) and are deleted; the SMS trigger's `auto_generated` branch stays but never fires.

- [ ] **Step 1: Write the test:** a student with only an `in` tap → run twice → one `missed_tap_outs` row, one `sms_outbox` row, **no** new `out` event; a student who tapped out → nothing; a student with no taps → nothing; an old `auto_generated` out becomes a `missed_tap_outs` row and is gone from `rfid_tap_events`; a normal tap-in after migration still records.
- [ ] **Step 2: Run; expect FAIL.** **Step 3: Implement** by adapting `auto_tap_out_open_students` (`add_sms_alerts_schema.sql:393-455`): same school-day arithmetic and latest-tap query, insert into the new table instead of `rfid_tap_events`; unschedule/schedule with `cron.unschedule` guarded by `exists (select 1 from cron.job …)`. **Step 4: Run migration then test; expect pass.**
- [ ] **Step 5: Commit** `feat(attendance): record "did not tap out" instead of tapping students out`.

### Task 5: Endorse dialog — Other and exclude-parent (Flutter)

**Files:** Modify `packages/discipline_officer_module/lib/models/escalation_report_model.dart` (`EndorsementKind`, `EscalationDraft`, `EscalationReportModel`), `packages/discipline_officer_module/lib/pages/dashboard/endorsements_view.dart` (`showEndorseDialog` and its dialog), `lib/data/escalation_repository.dart` (`_select`, `issue`, `_toModel`), `packages/guidance_counselor_module/lib/pages/escalation/escalation_approvals_view.dart` (detail popup). Tests: `packages/discipline_officer_module/test/endorsements_view_test.dart`, `test/endorsement_repository_test.dart`, `packages/guidance_counselor_module/test/escalation_and_archive_tabs_test.dart`.

**Interfaces:**
- Produces: `EndorsementKind.other('other', 'Other')` with `notifiesParent == false`; `EscalationDraft.otherDescription String?` and `excludeParent bool`; `EscalationReportModel.otherDescription String?`, `excludeParent bool`; `issue()` sends `other_description` and `exclude_parent`.

- [ ] **Step 1: Tests:** the kind dropdown lists Other; choosing it shows a required "Describe the intervention" field (error when empty) and an "Exclude the parent" checkbox that is checked by default; Counseling shows the checkbox unchecked; Counseling-and-parent kinds hide it; the draft carries both values; repository `issue` posts `kind: 'other'`, `other_description`, `exclude_parent`; Guidance's detail popup shows the description and "Parent excluded". Run; expect FAIL.
- [ ] **Step 2: Implement** the enum value, draft fields, dialog controls and repository mapping. **Step 3: Run the three test files; expect PASS.** **Step 4: Commit** `feat(endorsements): Other intervention and exclude-parent in the Endorse dialog`.

### Task 6: Guidance no longer schedules on approval (Flutter)

**Files:** Modify `escalation_approvals_view.dart` (`_ApproveDialog`, `_ApproveResult`, `onDecide`), `guidance_counselor_dashboard_page.dart` (`onDecideEscalation`), `lib/ui/guidance_counselor_connected_page.dart` (`_decideEscalation`), `lib/data/escalation_repository.dart` (`decide`). Tests: `escalation_and_archive_tabs_test.dart`, `test/endorsement_repository_test.dart`.

**Interfaces:** `EscalationRepository.decide(reportId, {required bool approve, String? note, String? message, String? actorName})` — no `meetingAt` / `meetingLocation`; the RPC call sends only `p_id, p_approve, p_note, p_message, p_actor_name`. `onDecide` / `onDecideEscalation` lose the two meeting parameters.

- [ ] **Step 1: Update tests:** approving shows no date/time/where fields; `decide` posts no `p_meeting_*`. Run; expect FAIL. **Step 2: Remove** the meeting picker and parameters. **Step 3: Run guidance package and root endorsement tests; expect PASS.** **Step 4: Commit** `feat(guidance): approving an endorsement no longer schedules a meeting`.

### Task 7: DO arranges the meeting for an approved endorsement (Flutter)

**Files:** Modify `escalation_report_model.dart` (add `meetings: List<EndorsementMeetingModel>`), `endorsements_view.dart` (action + status), `discipline_officer_dashboard_page.dart` / `lib/ui/discipline_officer_connected_page.dart` (callbacks), `lib/data/escalation_repository.dart` (`_select` embeds `guidance_meetings ( id, scheduled_at, location, invitee, status, guidance_note )`; `proposeMeeting`). Tests: `packages/discipline_officer_module/test/endorsements_view_test.dart`, `test/endorsement_repository_test.dart`.

**Interfaces:**
- Produces: `class EndorsementMeetingModel { id, scheduledAt, location, invitee, status, guidanceNote }` with `statusLabel` (`Awaiting_Guidance` → "Waiting for Guidance", `Returned` → "Returned by Guidance", `Proposed` → "Awaiting reply", others as stored); `EscalationRepository.proposeMeeting({required String endorsementId, required DateTime scheduledAt, required String invitee, String? location})` → RPC `propose_endorsement_meeting`; `EndorsementsView.onScheduleMeeting: Future<void> Function(EscalationReportModel, MeetingFormResult)?`.
- Consumes: `ScheduleMeetingDialog` / `MeetingFormResult` from `dashboard_layout`; Task 2 RPC. For an `excludeParent` endorsement the dialog offers only "Student" (add `allowParent` to `ScheduleMeetingDialog`, default true).

- [ ] **Step 1: Tests:** an `Approved` endorsement row shows "Schedule meeting" and the dialog's `meeting-save` calls `onScheduleMeeting` with the form; a `Pending_GC` or `Rejected` one has no action; an endorsement with `excludeParent` offers no Parent / Student & parent options; the row shows the latest meeting's `statusLabel` and, for a returned one, Guidance's note; repository `proposeMeeting` posts `p_escalation_id, p_scheduled_at (UTC), p_location, p_invitee`. Run; expect FAIL.
- [ ] **Step 2: Implement.** **Step 3: Run DO package + root tests; expect PASS.** **Step 4: Commit** `feat(do): arrange the meeting for an approved endorsement`.

### Task 8: Guidance sees and confirms endorsement meetings (Flutter)

**Files:** Modify `packages/guidance_counselor_module/lib/pages/referrals/referrals_models.dart` (`GuidanceReferralModel.endorsementMeetings` reuse `ReferralMeetingModel`, add status `Awaiting_Guidance` label "Awaiting your confirmation", `guidanceNote`), `referrals_view.dart`, `guidance_counselor_dashboard_page.dart`, `lib/ui/guidance_counselor_connected_page.dart`, `lib/data/referrals_repository.dart`. Tests: `packages/guidance_counselor_module/test/referrals_view_test.dart`, `test/referrals_repository_test.dart`.

**Interfaces:**
- Produces: `ReferralsRepository.fetchAll()` also embeds `escalation_reports!student_referrals_endorsement_id_fkey ( guidance_meetings ( … ) )` and merges those meetings into `meetings`; `confirmMeeting(String meetingId, {DateTime? scheduledAt, String? location})` → `confirm_endorsement_meeting`; `returnMeeting(String meetingId, String note)` → `return_endorsement_meeting`. `GuidanceReferralsView` gains `onConfirmMeeting: Future<void> Function(ReferralMeetingModel, {DateTime? scheduledAt, String? location})?` and `onReturnMeeting: Future<void> Function(ReferralMeetingModel, String note)?`; the referral popup shows each endorsement meeting with its status, and for `Awaiting_Guidance` the buttons **Confirm** (opens a date/time/where form prefilled with the DO's proposal), and **Return to Student Affairs** (note required). Row "Meeting" column shows the next meeting including awaiting ones.

- [ ] **Step 1: Tests:** an endorsement referral whose meeting is `Awaiting_Guidance` shows "Awaiting your confirmation" in the row; Confirm without edits calls `onConfirmMeeting(meeting)` with null changes; editing the time passes the new `scheduledAt`; Return needs a note and passes it; a self referral still shows only its own Schedule meeting action; repository maps the embedded endorsement meetings and posts the two RPCs. Run; expect FAIL.
- [ ] **Step 2: Implement** (reuse `ScheduleMeetingDialog` with a new `title` / `confirmLabel` / `initial` so Confirm shows the DO's time). **Step 3: Run guidance + root tests; expect PASS.** **Step 4: Commit** `feat(guidance): confirm, change or return an endorsement meeting`.

### Task 9: "Did not tap out" everywhere taps are shown (Flutter)

**Files:** `lib/data/attendance_activity_repository.dart`, `lib/data/professor_repository.dart` and `packages/professor_module/lib/pages/dashboard/professor_dashboard_page.dart` (~3417), `packages/student_portal_module/lib/widgets/day_detail_sheet.dart`, `packages/parent_portal_module/lib/widgets/…day_detail_sheet.dart`, `lib/data/student_portal_repository.dart`, `lib/data/parent_portal_repository.dart`, attendance models in both portal packages. Tests: `test/attendance_activity_repository_test.dart`, `test/attendance_activity_view_test.dart`, the professor dashboard test, portal `day_detail_sheet` tests.

**Interfaces:**
- Produces: `ActivityKind.didNotTapOut('Did not tap out')`; the activity log reads `missed_tap_outs` rows as entries (at = end of that school day); `ProfessorRepository.fetchMissedTapOuts(Iterable<String> studentIds, DateTime day) → Set<String>`; portal `AttendanceEntry.didNotTapOut bool` (from `missed_tap_outs` of that date) shown as a "Did not tap out" line in the day detail.
- A student who tapped in today with no tap-out yet shows nothing special until the 6:30 PM job records the miss.

- [ ] **Step 1: Tests:** the activity repository maps a `missed_tap_outs` row to `ActivityKind.didNotTapOut` with that label; the professor row text is "Did not tap out" for a student in the missed set and "Tapped out 4:35 PM" otherwise; the portal day detail shows "Did not tap out" when the flag is set and nothing otherwise. Run; expect FAIL.
- [ ] **Step 2: Implement** each reader. **Step 3: Run the root, professor, student and parent package suites; expect PASS.** **Step 4: Commit** `feat(attendance): show "Did not tap out" for missed tap-outs`.

---

## Self-Review

- **Spec coverage:** DO schedules after acceptance → T2, T7; Guidance change/recommend/confirm then notify → T2, T8; decline back to DO → T2, T7, T8; non-Guidance DO meetings unchanged → T2 (only `escalation_report_id` meetings gated); invitee confirm/decline → unchanged; Guidance visibility gap → T8; "You are invited…" for all meeting text → T3; remove auto tap-out + keep SMS + relabel + show everywhere → T4, T9; Other + exclude parent → T1, T5, T7.
- **Types:** `exclude_parent` / `excludeParent` introduced in T1/T5, used by T2 (RPC check) and T7 (dialog); `Awaiting_Guidance` introduced in T2, used by T7 and T8; `meeting_invitation_text` defined in T3 and called by T2's `confirm_endorsement_meeting` (T3 must run first, or T2 defines a stub that T3 replaces — run order: T3 SQL, then T2 SQL).
- **SQL run order:** `add_endorsement_other_kind` → `reword_meeting_invitations` → `add_endorsement_meetings` → `replace_auto_tap_out`.
