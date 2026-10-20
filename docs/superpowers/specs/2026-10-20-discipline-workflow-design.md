# Discipline Workflow Redesign — Design

Status: DRAFT, awaiting approval. Date: 2026-10-20.

## Intent

The capstone panel asked for a re-demonstration. Their findings: the incident
report is classified by the reporter, has no incident date/time or photo
evidence, and the Discipline Officer (DO) has no investigation step, no
guidance-counselor meeting loop with the parent/student, and no recorded
sanction on the student's file. The 72-hour expiry also silently archives
cases. This design makes the DO the one who classifies and sanctions, adds the
guidance investigation with a two-way meeting acknowledgement, and makes every
case end in a sanction record that can affect the student's enrollment.

## Goals

1. Reporters (professor, security) file *what happened, when, with photos* —
   they do not pick a violation.
2. DO validates, classifies, then chooses one of three paths:
   minor auto-record, escalate to guidance, or sanction directly.
3. Guidance counselor schedules a meeting; the student/parent confirms or
   declines from their own dashboard; the counselor files findings; the case
   returns to the DO.
4. Every case ends with a `sanctions` record on the student, handbook-based or
   custom, optionally affecting enrollment (non-readmission / dismissal).
5. 72-hour expiry flags and urgently notifies the DO instead of archiving, and
   skips Saturday and Sunday.

## Non-goals

- The smaller panel items (kiosk date/time and error banner, activity log,
  attendance logs, academic-year dates, per-student summary, ML retrain
  investigation, registrar section field) are separate later work.
- Real mobile push (FCM). No push infrastructure exists; see "Calls I made".
- Rewriting handbook content. `handbook_offenses` is reused as-is.

## Anti-goals (failure even if it "works")

- A sanction that is only free text; enrollment must actually be blocked.
- Escalating to guidance while the DO can still silently sanction (see rule).
- Expired cases disappearing from the DO's attention.
- Breaking existing violation history, the offline kiosk outbox, or existing
  reports already in the database.

## Current state (verified in repo)

- `student_violations` status enum: Pending → Under_Investigation → Resolved;
  Under_Investigation is never set by any code. `resolveViolation`
  (`lib/data/discipline_repository.dart:797`) is the only "validate".
- Reports go through RPC `submit_admission_slip` with `p_offense_ids`
  (professor form `violation_reports_view.dart`, security
  `lib/kiosk/security_report_screen.dart`, student kiosk). `created_at` is the
  only time. `evidence_url` exists in the schema, unused.
- `escalation_reports` (Pending_GC; GC approves/rejects; approval inserts
  `parent_interventions` + SMS/email) exists. No meeting scheduling, no
  student/parent acknowledgement beyond `read_at`.
- No sanction table; `penalty_imposed` is free text.
- 72h: `expire_stale_violations()` via hourly pg_cron sets `archived_at` and
  `expired_at`; plain 72 clock-hours. Notifications are in-app (`notifications`
  table + realtime + sound), SMS (PhilSMS) and email (Resend).
- Triggers keyed on `offense_id`: `apply_sanction_progression`,
  `escalate_sensitive_violation`, `trg_auto_parent_intervention`.

## Case lifecycle

| Stage | status | Who | Notes |
|---|---|---|---|
| Reported | `Pending` | professor/security | no offense chosen; incident_at, description, photos |
| Classified | `Pending` | DO | DO picks offense(s) from handbook; may edit incident details |
| With Guidance | `Under_Investigation` | counselor | investigation + meeting(s) |
| Investigation complete | `Investigation_Complete` (new) | counselor | findings filed; unlocks DO sanction |
| Sanctioned / Closed | `Resolved` | DO | exactly one `sanctions` row |

Paths from Classified:
- **Minor → auto-record:** DO validates a Minor offense; the system closes the
  case as `Resolved` and creates a handbook-based sanction from
  `handbook_offenses.penalty_info`. One click.
- **Escalate to guidance:** creates a `guidance_investigations` row and
  notifies the counselor.
- **Sanction directly:** DO opens the sanction form without guidance.

### Rule while With Guidance

The DO's Sanction action is locked until the investigation is complete (or the
meeting is marked Completed/Missed with findings). The DO can *override* only
by entering a written reason; the reason is stored on the sanction
(`override_reason`), written to the audit log, and the counselor is notified.

## Data model (new / changed)

All as hand-run SQL scripts in `supabase/`, matching the repo's convention
(header states run order). RLS: reporters insert; DO/Admin manage; counselor
manages investigations/meetings; students/parents read and respond only to
their own rows.

- `student_violations`: add `incident_at timestamptz` (required on new
  reports, back-filled to `created_at`); make `offense_id` nullable (null until
  classified); add `classified_by`, `classified_at`; add enum value
  `Investigation_Complete`. `incident_notes` is the description (confirm the
  column exists live; no tracked ALTER creates it).
- `violation_evidence(id, violation_id, storage_path, uploaded_by, created_at)`
  and a private storage bucket `violation-evidence` (images only, size cap);
  signed URLs for viewing.
- `guidance_investigations(id, violation_id, assigned_to, status
  [Open|Complete], findings, recommendation, created_at, completed_at)`.
- `guidance_meetings(id, investigation_id, student_id, scheduled_at, location,
  invitee [student|parent|both], status [Proposed|Confirmed|Declined|
  Reschedule_Requested|Completed|Missed|Cancelled], response_by,
  responded_at, response_note)`.
- `sanctions(id, violation_id, student_id, decided_by, decided_at, basis
  [handbook|custom], handbook_offense_id null, sanction_type, description,
  effective_on, ends_on null, affects_enrollment, override_reason null)`.
  `sanction_type` includes warning, community service, suspension,
  non-readmission, dismissal, other (custom text in description).
- `students.enrollment_standing` [Good|Non_Readmission|Dismissed] set from a
  sanction with `affects_enrollment`. Registrar enrollment / re-enrollment and
  the new-term flow must refuse or visibly flag non-Good students; Good Moral
  requests must reflect it.
- RPCs (SECURITY DEFINER, audit-logged): `submit_incident_report`,
  `classify_violation`, `escalate_to_guidance`, `schedule_guidance_meeting`,
  `respond_to_meeting`, `complete_investigation`, `record_sanction`.
  `submit_admission_slip` stays for kiosk/offline compatibility.

## Screens

- Professor + security report form: student, incident date and time pickers
  (default now, cannot be in the future), description, photo upload (multiple).
  Offense picker removed.
- DO dashboard: queue shows "Needs classification"; case panel gains Classify,
  then Auto-record (Minor) / Escalate / Sanction. Sanction form with handbook
  suggestion pre-filled and a custom option, enrollment-effect toggle with a
  confirm step. Case timeline shows every step with who/when.
- Guidance counselor: new "Investigations" tab — assigned cases, schedule
  meeting, record outcome and findings.
- Student and parent dashboards: meeting card with Confirm / Can't attend
  (+ note). Counselor sees responses live. SMS + in-app notification on
  scheduling (via existing `queue_sms` / `notifications`).
- Student record: sanctions history and enrollment standing.

## 72-hour expiry

- Replace archive-on-expiry: the cron job sets `expired_at` only; the case
  stays in the active queue with a red "Expired" marker and sorts first.
- The clock excludes Saturday and Sunday (72 *weekday* hours). No holiday
  table in this version.
- Notifications: "due in 12 hours" warning and "expired" alert, targeted at the
  Discipline Officer role, urgent styling.
- The never-called Dart `expireStaleViolations()` is removed or wired
  consistently; cron is the single driver.
- "Archive/Restore" remain as manual DO actions.

## Constraints

- Flutter + Supabase, existing package layout; no new backend services.
- Existing data, tests and the offline kiosk outbox keep working.
- Handbook is the default source for sanctions, never the only one.

## Calls I made (please check)

1. Use `Under_Investigation` for "With Guidance" and add one enum value
   `Investigation_Complete`.
2. Minor auto-record also writes a handbook-based sanction row, so every case
   ends with one.
3. Early DO sanction during guidance = allowed with a mandatory logged reason.
4. Weekend rule means skipping Sat/Sun; no holidays.
5. "Push" = urgent in-app notification (realtime + sound) for the DO, plus
   optional SMS if an SMS number is configured for the DO; true mobile push is
   out of scope.
6. Existing auto-triggers (4th minor, sensitive words, major offense) stop
   creating escalation reports/parent SMS by themselves; they flag the case in
   the DO queue as "Suggested escalation". Old `escalation_reports` data stays
   readable.
7. The student kiosk self-report (Minor only) keeps its offense picker, since
   the panel's comment was about professor/security reports. Reports from it
   arrive already classified.
8. New migrations are hand-run scripts, no migration tool introduced.

## Left to the builder

Table/column names beyond those above, RLS policy details, UI layout details
following existing `AppPopup` and dashboard styles, test structure.

## Verification

Unit tests for repositories/models; SQL scripts exercised in a test SQL file
per existing `test_*.sql` convention; an end-to-end demo script covering:
professor report → DO classify → escalate → counselor schedule → parent
confirm → findings → DO non-readmission sanction → registrar blocks
re-enrollment; plus a minor auto-record and an expired weekend case.
