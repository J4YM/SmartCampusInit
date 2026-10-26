# Concern Reports, Guidance Referrals and Meetings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split the student's old "Referral" into a Concern Report (to Student Affairs / the Discipline Officer) and a Self Referral (to Guidance); turn an approved DO Endorsement into a Guidance Referral; let the Guidance Associate schedule meetings from a Referral; lock identity fields on the Good Moral form; reformat the weekly absence SMS.

**Architecture:** Add `concern_reports` (the old DO-bound referral path, same ids migrated). Reshape `student_referrals` into Guidance-only rows with a `source` of `self` or `endorsement`. Meetings reuse `guidance_meetings` with a new `referral_id` link and one new RPC modelled on `schedule_guidance_meeting`. UI changes follow the existing package split: `student_portal_module`, `discipline_officer_module`, `guidance_counselor_module`, shared widgets in `dashboard_layout`.

**Tech Stack:** Flutter/Dart, Supabase (Postgres RLS, SECURITY DEFINER RPCs, `notifications` table, `queue_sms`).

**Spec:** the conversation decisions recorded under "Decisions" below (no separate spec file).

## Decisions (from the requester)

- "Student Affairs" is the existing `Discipline_Officer` role. Concern Reports go to it; the DO Dashboard calls them **Concern(s)**.
- **Self Referral** goes to Guidance only (no DO, no Student Affairs). Covers mental health and other troubles. No "refer another student by number" anywhere.
- **Concern Report** is the old DO-bound referral, new name and process. No "about another student by number" input either.
- A DO Endorsement approved in Endorsement Approvals becomes a **Referral** in a new Guidance Referrals tab. Referrals list = Self Referrals + accepted Endorsements.
- From a Referral the Guidance Associate schedules a meeting with `student`, `parent` or `both`, same as investigation scheduling. Student invited → portal notification. Parent invited → portal notification **and SMS**. Student-only → the parent gets nothing (private cases).
- Good Moral form: name, student number and section are autofilled and **locked**; address and contact number stay editable; applies to Student and Parent portals, including resubmission. Name corrections are made by the DO (registrar owns names).
- Existing DO-bound referrals are kept and shown as Concerns.
- The weekly absence message is the SMS built by `build_weekly_absence_message`; reformat it.

## Assumptions to confirm at review

1. A student sees only their own Self Referrals (not endorsement-sourced Referrals); they learn of an endorsement only through a meeting invitation.
2. Self Referral concern choices: `emotional`, `family`, `academic`, `other`. Concern Report choices: `attendance`, `behavior`, `bullying`, `safety`, `academic`, `other`. Both reuse the existing DB `concern` values.
3. The DO fixes a locked-name mismatch from the existing Good Moral comparison view with a "Use registrar record" action (Task 7).

## Global Constraints

- SQL files in `supabase/` are idempotent, run in the Supabase SQL Editor, with a header comment stating run order (match `add_endorsements.sql`).
- Meeting times are shown in `Asia/Manila`, format `'Mon DD, YYYY HH12:MI AM'`; a meeting must be in the future.
- SMS text is plain ASCII (GSM-7), capped at 300 characters.
- Meeting notifications use `notifications (target_role, user_id, title, message)`; SMS goes through `public.queue_sms('guidance_meeting', student_id, meeting_id, text)` wrapped in `begin ... exception when others then raise warning`.
- Guidance must never read Concern Reports; the DO and Student Affairs must never read `student_referrals`.

## Review Focus

- Student-only meeting: no parent notification row and no `sms_outbox` row is created.
- Re-approving or re-running the migration does not duplicate Referrals (one Referral per endorsement) or Concerns (migrated by id).
- A student with no linked parent or no guardian number invited as `parent`/`both`: meeting still saves; SMS row is `skipped`, no exception.
- Legacy classmate-referral rows survive as Concerns with the reporter as the student and the classmate shown as "About".
- Student with no `sections` row or no phone: the Good Moral form still opens, and an identity field with no value on record stays editable (Task 6).
- Weekly SMS for a student with many subjects or a very long name stays at or under 300 characters.

---

## File Structure

| File | Responsibility |
|---|---|
| `supabase/add_concern_reports.sql` (new) | `concern_reports`, legacy migration, RPCs, DO notify, repoint endorsement link |
| `supabase/add_guidance_referrals.sql` (new) | Reshape `student_referrals`, Guidance-only RLS, endorsement→Referral trigger, self-only submit RPC |
| `supabase/add_referral_meetings.sql` (new) | `guidance_meetings.referral_id`, `schedule_referral_meeting`, reply routing |
| `supabase/reformat_weekly_absence_sms.sql` (new) | New `build_weekly_absence_message` body |
| `supabase/test_concern_reports.sql`, `test_guidance_referrals.sql`, `test_referral_meetings.sql` (new) | Rollback-style checks, same pattern as `test_endorsements.sql` |
| `lib/data/concern_reports_repository.dart` (new, from `referrals_repository.dart`) | DO reads/updates concerns |
| `lib/data/referrals_repository.dart` (rewrite) | Guidance reads/updates referrals, schedules meetings |
| `lib/data/student_portal_repository.dart` | Self-only `submitReferral`, new `submitConcernReport`, `fetchMyConcernReports`; fuller `fetchGoodMoralPrefill` |
| `packages/student_portal_module/lib/pages/referral_request_page.dart` | Self-only sheet |
| `packages/student_portal_module/lib/pages/concern_report_page.dart` (new) | Concern Report sheet |
| `packages/student_portal_module/lib/models/concern_report_status.dart` (new) | Student's concern list model |
| `packages/discipline_officer_module/lib/pages/referrals/` → `concerns/concerns_view.dart` | Renamed Concerns tab |
| `packages/discipline_officer_module/lib/models/student_referral_model.dart` → `concern_report_model.dart` | Renamed model |
| `packages/dashboard_layout/lib/src/schedule_meeting_dialog.dart` (new) | `ScheduleMeetingDialog`, `MeetingFormResult`, `validateMeetingTime` moved out of the DO module |
| `packages/guidance_counselor_module/lib/pages/referrals/referrals_view.dart` (new) | Guidance Referrals tab |
| `packages/dashboard_layout/lib/src/good_moral_form.dart`, `packages/student_portal_module/lib/pages/good_moral_request_page.dart`, `packages/parent_portal_module/lib/pages/good_moral_request_page.dart` | Locked identity fields |

---

### Task 1: Concern Reports (database)

**Files:**
- Create: `supabase/add_concern_reports.sql`, `supabase/test_concern_reports.sql`

**Interfaces:**
- Produces:
  - Table `public.concern_reports(id uuid pk, student_id uuid, about_student_id uuid null, concern text, details text, urgency text, status text, handler_note text, handled_by uuid, handled_at timestamptz, created_at timestamptz)`; `status` in `Pending|In_Progress|Closed`, `urgency` in `Normal|Urgent`.
  - `submit_concern_report(p_reporter_id uuid, p_concern text, p_details text, p_urgent boolean default false) returns uuid`
  - `my_concern_reports(p_reporter_id uuid) returns table(id uuid, concern text, urgency text, status text, handler_note text, created_at timestamptz)`
  - `escalation_reports.concern_id uuid` replaces `referral_id` (same uuid values).
- RLS: select/update for `Admin` and `Discipline_Officer` only; anon policies mirror `student_referrals` demo policies.

- [ ] **Step 1: Write `test_concern_reports.sql`** with these checks, each returning one `ok`/`FAIL` row: (a) submitting with blank details raises "Please describe your concern."; (b) text containing a term from `find_sensitive_terms` raises urgency to `Urgent`; (c) a Guidance Counselor role selects zero rows from `concern_reports`; (d) a legacy classmate row (`is_self = false`) in `student_referrals` becomes a `concern_reports` row with `student_id = referred_by` and `about_student_id` = old subject, same `id`.
- [ ] **Step 2: Run it before the migration**; expect failures (missing table).
- [ ] **Step 3: Write `add_concern_reports.sql`**: create table, indexes, RLS, RPCs, and a notify trigger copying `trg_notify_student_referral` from `add_endorsements.sql` §6 but with title `New concern report` / `Urgent concern report` and message `<name> filed a concern report. Review it under Concerns.`
- [ ] **Step 4: Legacy migration in the same file:** `insert into concern_reports ... select ... from student_referrals on conflict (id) do nothing` for **all** current rows, then repoint the link: drop FK on `escalation_reports.referral_id`, rename column to `concern_id`, add FK to `concern_reports(id)`, recreate `escalation_reports_referral_uidx` as `escalation_reports_concern_uidx`, and recreate `trg_endorsement_referral_guard` / `trg_endorsement_referral_progress` to read/update `concern_reports` (progress sets `status = 'In_Progress'`). Do not delete the old `student_referrals` rows here (Task 2 does, after splitting).
- [ ] **Step 5: Run the SQL, then the test; expect all `ok`.**
- [ ] **Step 6: Commit** `feat(concerns): concern_reports table, RPCs and legacy migration`.

### Task 2: Guidance-only Referrals (database)

**Files:**
- Create: `supabase/add_guidance_referrals.sql`, `supabase/test_guidance_referrals.sql`

**Interfaces:**
- Consumes: Task 1 tables.
- Produces:
  - `student_referrals` gains `source text not null default 'self' check (source in ('self','endorsement'))` and `endorsement_id uuid unique references escalation_reports(id) on delete cascade`; `referred_by` becomes nullable.
  - `submit_student_referral(p_referrer_id uuid, p_concern text, p_details text, p_urgent boolean default false) returns uuid`: self only; the old 5-argument overload is dropped.
  - Policies: `Admin` + `Guidance_Counselor` select/update on `student_referrals`; the DO has none.
  - Trigger `trg_referral_from_endorsement` on `escalation_reports` AFTER UPDATE when `status` changes to `'Approved'`: inserts one `student_referrals` row (`source='endorsement'`, `endorsement_id = new.id`, `concern='other'`, `details = title || ': ' || summary`, `referred_by = created_by`), notifies `Guidance_Counselor` with title `New referral from Student Affairs`.
  - `my_student_referrals` returns only `source = 'self'` rows.

- [ ] **Step 1: Write `test_guidance_referrals.sql`:** (a) after the migration, no `student_referrals` row has `is_self = false` and each matching `concern_reports` row exists; (b) approving a seeded `escalation_reports` row creates exactly one referral with `source='endorsement'`; updating the same row again creates none; (c) a Discipline Officer role selects zero from `student_referrals`; (d) `my_student_referrals` omits the endorsement referral.
- [ ] **Step 2: Run it; expect FAIL.**
- [ ] **Step 3: Write `add_guidance_referrals.sql`:** after Task 1's copy, `delete from student_referrals where is_self = false`; add columns; rewrite RPC, policies, trigger, `my_student_referrals`; replace `trg_notify_student_referral` so it notifies `Guidance_Counselor` (message `<name> asked for help. Review it under Referrals.`) and fires only for `source = 'self'`.
- [ ] **Step 4: Run SQL then test; expect all `ok`.**
- [ ] **Step 5: Commit** `feat(referrals): Guidance-only self referrals; approved endorsements become referrals`.

### Task 3: Referral meetings (database)

**Files:**
- Create: `supabase/add_referral_meetings.sql`, `supabase/test_referral_meetings.sql`

**Interfaces:**
- Consumes: Task 2 `student_referrals`.
- Produces:
  - `guidance_meetings.referral_id uuid references student_referrals(id) on delete cascade`; `guidance_meetings_has_parent_check` widened to "investigation_id, escalation_report_id or referral_id is not null".
  - `schedule_referral_meeting(p_referral_id uuid, p_scheduled_at timestamptz, p_location text, p_invitee text) returns uuid` — `Admin`/`Guidance_Counselor` only; invitee in `student|parent|both`; cancels the referral's still-open meetings; sets the referral `In_Progress` and `handled_by`.
  - `guidance_meetings_staff_select`: Guidance also reads rows where `referral_id is not null`.
  - `respond_to_meeting`: notifies `Guidance_Counselor` when `referral_id` or `escalation_report_id` is set, else the DO.

- [ ] **Step 1: Write the test** with a seeded referral, student and linked parent: (a) `student` → one `notifications` row for the student, zero for the parent, zero `sms_outbox` rows with `related_id = meeting id`; (b) `parent` → parent notification + one sms row, none for the student; (c) `both` → both + one sms; (d) past time raises "must be scheduled in the future"; (e) scheduling twice leaves one open meeting; (f) a DO role gets "Only the Guidance Associate can schedule".
- [ ] **Step 2: Run; expect FAIL.**
- [ ] **Step 3: Implement** `schedule_referral_meeting` by copying `schedule_guidance_meeting` (`add_do_investigations.sql:108-197`), changing role check, target table and messages: student `'Guidance meeting scheduled'`, parent text keeps `Please confirm in the Parent Portal.`; SMS only inside the `p_invitee in ('parent','both')` branch.
- [ ] **Step 4: Run SQL then test; expect all `ok`.**
- [ ] **Step 5: Commit** `feat(referrals): schedule student/parent meetings from a referral`.

### Task 4: Student portal — Self Referral and Concern Report

**Files:**
- Modify: `lib/data/student_portal_repository.dart:252-290`, `lib/ui/student_portal_connected_page.dart` (referral state ~48, 214, 319-343, 374-375), `packages/student_portal_module/lib/pages/referral_request_page.dart`, `packages/student_portal_module/lib/pages/student_portal_home_page.dart` (~73-101, 390-410, 770-870), `packages/student_portal_module/lib/student_portal_module.dart`, `packages/student_portal_module/lib/models/referral_request_status.dart`
- Create: `packages/student_portal_module/lib/pages/concern_report_page.dart`, `packages/student_portal_module/lib/models/concern_report_status.dart`
- Test: `packages/student_portal_module/test/support_referral_form_test.dart` (update), `packages/student_portal_module/test/concern_report_form_test.dart` (new)

**Interfaces:**
- Produces:
  - `StudentPortalRepository.submitReferral({required String studentId, required ReferralConcern concern, required String details, bool urgent = false})` (no `aboutStudentNumber`).
  - `submitConcernReport({required String studentId, required ConcernType concern, required String details, bool urgent = false})`; `Future<List<ConcernReportStatus>> fetchMyConcernReports(String studentId)`.
  - `enum ConcernType { attendance, behavior, bullying, safety, academic, other }` with `label` and `fromDb`; `class ConcernReportStatus { id, concern, urgency, status, handlerNote, createdAt }`.
  - `ReferralConcern` offers only `emotional, family, academic, other` in the sheet; `isSelf` field removed from `ReferralRequestStatus`.
  - Home page props `onSubmitConcernReport`, `initialConcernReports`.

- [ ] **Step 1: Update `support_referral_form_test.dart`:** the sheet has no student-number field (`find.text("Enter your classmate's student number")` finds nothing), submit reports `{concern, details, urgent}` only, and only the four self concerns are listed.
- [ ] **Step 2: Write `concern_report_form_test.dart`:** the sheet requires details (error "Please describe your concern"), lists the six `ConcernType` labels, and calls `onSubmit` with the chosen type and `urgent`.
- [ ] **Step 3: Run** `flutter test test/support_referral_form_test.dart test/concern_report_form_test.dart` in `packages/student_portal_module`; expect FAIL.
- [ ] **Step 4: Implement** the repository methods (RPCs `submit_student_referral` without `p_about_student_number`, `submit_concern_report`, `my_concern_reports`) and both sheets (follow `showReferralRequestSheet`'s structure). Retitle the card "Referral" (Self Referral → Guidance, text says only Guidance sees it) and add a second card "Concern Report" (→ Student Affairs) with its own status list. Toasts: `Referral sent to the Guidance Office.` / `Concern report sent to Student Affairs.`
- [ ] **Step 5: Run the tests; expect PASS.** Run `flutter test` in the package; expect no regression (fix `dark_mode_card_text_test.dart` expectations that mention "For a classmate").
- [ ] **Step 6: Commit** `feat(student-portal): self-only referral and new concern report`.

### Task 5: DO Dashboard — Concerns

**Files:**
- Create (rename with `git mv`): `lib/data/concern_reports_repository.dart`, `packages/discipline_officer_module/lib/models/concern_report_model.dart`, `packages/discipline_officer_module/lib/pages/concerns/concerns_view.dart`
- Modify: `lib/ui/discipline_officer_connected_page.dart` (referral state/repo at lines ~20, 98, 174-193, 260-298, 454-464, 825-826), `packages/discipline_officer_module/lib/discipline_officer_module.dart`, `packages/discipline_officer_module/lib/pages/dashboard/discipline_officer_dashboard_page.dart`, `packages/discipline_officer_module/lib/pages/dashboard/endorsements_view.dart`, `test/referrals_repository_test.dart` → `test/concern_reports_repository_test.dart`, `packages/discipline_officer_module/test/referrals_view_test.dart` → `concerns_view_test.dart`
- Test: the two renamed test files

**Interfaces:**
- Produces: `class ConcernReportModel { id, studentName, studentNumber, aboutStudentName (String?), concern, details, urgency, status, handlerNote, createdAt }`; `ConcernReportsRepository.fetchAll()` and `.update(String id, {required String status, String? note, String? actorId})`, reading `concern_reports`.
- Consumes: Task 1 table. Endorsing from a concern sets `concern_id` (was `referral_id`) in `EscalationRepository.issue` and `EscalationDraft`.

- [ ] **Step 1: Rename tests and update them** to the new class and table names; add an assertion that a concern with `about_student_id` shows "About: <name>". Run them; expect FAIL.
- [ ] **Step 2: `git mv` the files, rename symbols, sidebar/tab label `Referrals` → `Concerns`**, copy ("referral" → "concern" wherever the DO reads it). `EscalationRepository._select` and `issue` use `concern_id`.
- [ ] **Step 3: Run** `flutter test` in `packages/discipline_officer_module` and in the repo root for the two data tests; expect PASS.
- [ ] **Step 4: Commit** `feat(do): referrals tab becomes Concerns on concern_reports`.

### Task 6: Good Moral identity fields locked

**Files:**
- Modify: `packages/student_portal_module/lib/pages/good_moral_request_page.dart:95-149` and the field builders, `packages/parent_portal_module/lib/pages/good_moral_request_page.dart` (same), `lib/data/student_portal_repository.dart:213-233`, `lib/data/parent_portal_repository.dart` (its prefill method), `lib/ui/student_portal_connected_page.dart:202-211`
- Test: `packages/student_portal_module/test/good_moral_request_page_test.dart`, `packages/parent_portal_module/test/good_moral_resubmit_test.dart`, `packages/student_portal_module/test/good_moral_resubmit_test.dart`

**Interfaces:**
- Produces: `GoodMoralRequestPage` text fields `_lastName`, `_firstName`, `_middleName`, `_studentNumber`, `_section` use `readOnly: true` whenever the prefilled value is non-empty (blank stays editable); address and contact number always editable. The same applies when `initial` comes from a returned request.
- `fetchGoodMoralPrefill` also selects `middle_name` and the address column when `profiles`/`students` have them (check the live column names; skip fields that do not exist) and no longer swallows errors silently: failure shows a one-line notice "Could not load your details — please fill them in".

- [ ] **Step 1: Write tests:** with a full prefill, last name, first name, student number and section are `readOnly` and typing does not change them while address and contact number can be edited; with an empty section, the section field is editable; same on resubmit with `returned.formData`. Run; expect FAIL.
- [ ] **Step 2: Implement** the read-only rule in both pages; pass lock-state through a small helper `bool _locked(String? initialValue)`.
- [ ] **Step 3: Fix the prefill:** `maybeSingle()` returning null or an RLS error is currently invisible; surface it and, if `profiles` is unreadable by the student, add the missing select policy in `supabase/add_good_moral_form_data.sql` (idempotent) — confirm by logging in as a demo student.
- [ ] **Step 4: Run both packages' tests; expect PASS.**
- [ ] **Step 5: Commit** `feat(good-moral): lock registrar-owned fields and surface prefill failures`.

### Task 7: DO corrects a mismatched name

**Files:**
- Modify: `packages/discipline_officer_module/lib/pages/dashboard/good_moral_view.dart`, `lib/data/discipline_repository.dart`, `supabase/add_good_moral_form_data.sql` (new RPC `correct_good_moral_form(p_request_id uuid)` that rewrites `form_data` identity fields from `students`/`profiles`; `Admin`/`Discipline_Officer` only)
- Test: `packages/discipline_officer_module/test/good_moral_comparison_test.dart`

**Interfaces:**
- Produces: `DisciplineRepository.useRegistrarRecord(String requestId)`; button label `Use registrar record` shown only when the existing comparison reports a mismatch.

- [ ] **Step 1: Test:** a mismatching slip shows the button; tapping calls the callback once; a matching slip shows no button. Run; expect FAIL.
- [ ] **Step 2: Implement** the RPC, repository method and button.
- [ ] **Step 3: Run the test; expect PASS.** Commit `feat(good-moral): DO can replace slip identity with the registrar record`.

### Task 8: Guidance Referrals tab with meeting scheduling

**Files:**
- Create: `packages/dashboard_layout/lib/src/schedule_meeting_dialog.dart` (moved from `investigations_view.dart:816-end`: `MeetingFormResult`, `ScheduleMeetingDialog`, plus `validateMeetingTime` from line 94), `packages/guidance_counselor_module/lib/pages/referrals/referrals_view.dart`, `packages/guidance_counselor_module/test/referrals_view_test.dart`
- Modify: `packages/dashboard_layout/lib/dashboard_layout.dart` (export), `packages/discipline_officer_module/lib/pages/investigations/investigations_view.dart` (import from `dashboard_layout`), `packages/guidance_counselor_module/lib/pages/dashboard/guidance_counselor_dashboard_page.dart:249-256,271` (add `GuidanceCounselorTab.referrals`, label `Referrals`, content builder + callbacks), `lib/ui/guidance_counselor_connected_page.dart`, `lib/data/referrals_repository.dart` (rewrite for Guidance)
- Test: `packages/discipline_officer_module/test/investigations_view_test.dart` (still passes after the move)

**Interfaces:**
- Produces:
  - `class GuidanceReferralModel { id, studentId, studentName, studentNumber, source ('self'|'endorsement'), concern, details, urgency, status, note, createdAt, meetings: List<ReferralMeetingModel> }` and `ReferralMeetingModel { id, scheduledAt, location, invitee, status }`.
  - `ReferralsRepository.fetchAll()`, `.update(id, {status, note, actorId})`, `.scheduleMeeting({referralId, scheduledAt, location, invitee})` → RPC `schedule_referral_meeting`, `.setMeetingOutcome(meetingId, status)` → existing `set_meeting_outcome` (extend its role check in `add_referral_meetings.sql` to include `Guidance_Counselor` for meetings with `referral_id`).
  - `GuidanceReferralsView({required List<GuidanceReferralModel> referrals, onUpdate, onScheduleMeeting, onSetMeetingOutcome})`.

- [ ] **Step 1: Move the dialog** to `dashboard_layout`, update the DO import and run `flutter test` in `packages/discipline_officer_module`; expect PASS (pure move).
- [ ] **Step 2: Write `referrals_view_test.dart`:** both sources render, with a badge `Self referral` or `Endorsement`; `Schedule meeting` opens the dialog and calls `onScheduleMeeting(referral, MeetingFormResult)`; a referral that already has an upcoming meeting shows it with its status; update changes status and note. Run; expect FAIL.
- [ ] **Step 3: Implement** the view following `investigations_view.dart` (table, dialog, outcome buttons), the tab, and the repository.
- [ ] **Step 4: Run guidance and root tests; expect PASS.** Commit `feat(guidance): Referrals tab with meeting scheduling`.

### Task 9: Weekly absence SMS format

**Files:**
- Create: `supabase/reformat_weekly_absence_sms.sql`
- Modify: `supabase/test_attendance_and_weekly_sms.sql` (expected strings)

**Interfaces:**
- Produces: same signature `build_weekly_absence_message(p_school text, p_name text, p_label text, p_items text[]) returns text`. New body, ASCII only, `E'\n'` line breaks, items listed one per line until the 300-char cap, then `...and N more`:

```
STI Baliuag - Weekly Absence Notice
Student: <name>
Week: <label>
Absences:
- <Subject> (<n> day/days)
Please contact the Student Affairs Office if this is incorrect.
```

  The queue function keeps building `items` as `subject || ' x' || n`; the builder reformats `Subject xN` into `Subject (N day|days)`. Footer line is dropped before items are, never after.

- [ ] **Step 1: Update the test** with the exact expected string for 2 items and for 40 items (ends with `...and N more`, `length <= 300`), plus a 60-character name. Run; expect FAIL.
- [ ] **Step 2: Write the SQL** reusing the existing reserve/cap logic from `add_weekly_absence_sms.sql:22-67`.
- [ ] **Step 3: Run the test; expect all pass** and run `test_weekly_absence_sms_live.sql` steps 1-3 (queue only, no real send) to confirm the queued text.
- [ ] **Step 4: Commit** `feat(sms): clearer layout for the weekly absence message`.

---

## Self-Review

- **Spec coverage:** Self-only referral → Tasks 2, 4. Concern Report + DO "Concern" → Tasks 1, 4, 5. Endorsement → Referral → Task 2. Guidance meetings with student/parent/both, student-only private, SMS only with parent → Tasks 3, 8. Classmate-by-number removed → Tasks 2, 4. Good Moral lock/autofill both portals, DO corrects → Tasks 6, 7. Absence report → Task 9. Legacy data kept → Task 1. Guidance-only privacy → Tasks 2, 3.
- **Types:** `concern_id` replaces `referral_id` in Tasks 1 and 5 only; `ReferralRequestStatus.isSelf` removed in Task 4 and not used by Task 8 (separate model).
- **Open points flagged above** under "Assumptions to confirm".
