# Discipline Office owns violations and investigations; Guidance works from endorsements

Date: 2026-10-22. Follows `2026-10-20-discipline-workflow-design.md`, which this partly reverses.

## Intent

The panel's direction: the Guidance Associate steps in for mental support or
counseling only when the Discipline Officer (DO) endorses a student. Everything
about violations stays with the Discipline Office. Today the DO escalates a
violation to Guidance, and Guidance runs the investigation and schedules the
meetings. That moves to the DO. Guidance is left with endorsements, counseling
sessions and its own confidential intervention logs.

## Goals

1. **DO owns every violation and investigation.** The DO files an investigation
   (no escalation to Guidance), processes it, schedules meetings with the
   student, the parent or both, records meeting outcomes, completes it with
   findings, and then sanctions. The student/parent confirm-or-decline
   acknowledgement in their own dashboards stays as built.
2. **Endorsements replace Escalation.** "Escalation Approvals" becomes
   "Endorsement Approvals" (DO side: "Endorsement"). An endorsement is the DO
   asking Guidance for counseling and/or parent intervention. It is not tied to
   a violation: any student can be endorsed, so the DO's student picker lists
   all students, not only those with violations.
3. **What Guidance sees in an endorsement:** the DO's written reason, and the
   student's violation history *if any*. Guidance never sees sanctions, the
   DO's override reasons, or investigation findings.
4. **Guidance's work after approval:** hold the counseling session and manually
   record what was done in that student's Intervention Logs. Parent
   intervention keeps today's behaviour (counselor-approved message to the
   parent by SMS and/or email, optional parent meeting picker added on
   2026-10-21).
5. **Guidance never gets DO sanctions in its logs.** Remove the "Sanction" log
   type and the trigger added by `add_escalation_meeting_and_sanction_log.sql`
   (including its backfill rows). Intervention Logs contain only what the
   counselor records by hand.
6. **Referrals and self-referrals from students go to the DO**, not Guidance.
   (Builder's call, see below: the DO can start an endorsement from a referral.)
7. **Rename** the Guidance dashboard title to "Guidance Associate Dashboard"
   (and the role label where it is the dashboard title; the database role
   `Guidance_Counselor` is unchanged).
8. **ML module and single/batch student analysis:** the Guidance Associate keeps
   them. Student Affairs (DO dashboard) gets access to the same screens and
   data to use them. Same code, not a copy.
9. **Good Moral request.**
   - Student portal: the request slip pre-fills from the student's record
     (name, student number, section, address, contact, year started where the
     record has them) and every field stays editable.
   - The submitted slip is stored as separate values (not only the packed
     `remarks` text) so it can be compared.
   - DO dashboard: the DO opens a request and sees the form exactly as the
     student filled it next to the school's record, with differing fields
     highlighted.
   - If the data does not match the record, the DO can **flag** the request or
     **send it back** to the student with a note; the student edits and
     resubmits. The DO cannot edit the student's answers; corrections to the
     certificate itself happen in the exported .docx outside the system.

## Non-goals

- No change to the database role names or to the registrar, professor, security,
  parent or kiosk flows.
- No browsable list of violations for Guidance; it only sees the history of a
  student the DO endorsed.
- No change to how sanctions, non-readmission and the minor-violation bypass
  work.
- APK builds are out of scope.

## Anti-goals (a failure even if it technically works)

- Guidance can read sanctions, investigation findings or the DO's override
  reasons through any screen, query or realtime channel.
- Anyone other than Guidance (and Admin audit) can read Intervention Logs.
- A student is endorsed silently: Guidance must see an endorsement as a
  pending approval, and the DO must see its status.

## Constraints

- Flutter + Supabase monorepo; Postgres RLS and SECURITY DEFINER functions are
  the enforcement, the UI only hides things.
- Real staff accounts are `authenticated`; the static demo logins are `anon`
  and cannot call the signed-in-only functions. Verify with the real
  `demo.*@baliuag.sti.edu.ph` accounts.
- Netlify web build pins Flutter 3.24.5: use `withOpacity`, not `withValues`.
- Existing rows must survive: investigations and meetings already in the
  database keep their data and become DO-owned. Existing escalation reports
  become endorsements.
- Migrations are idempotent SQL files in `supabase/`, run by the user in the
  Supabase SQL editor; add a note to `docs/superpowers/demo-checklist.md`.
- TDD with the existing patterns (`test/support/recording_server.dart`, widget
  tests). Root `flutter test` is the reliable suite.

## Delivery order (four independent pieces, each shipped and tested before the next)

1. Endorsements, referral routing to the DO, Guidance privacy changes (drop
   sanction logs), title rename.
2. Investigations and meeting scheduling move to the DO.
3. Good Moral auto-fill, side-by-side comparison, flag / send back.
4. ML and student analysis available to Student Affairs.

## Decided by the user

- Endorsement shows reason **and** violation history, never sanctions.
- Guidance keeps ML/analysis; Student Affairs just uses it.
- DO may flag or send back a Good Moral request that does not match.
- Guidance's post-approval role is the counseling session plus manual logging.

## ML and analysis versus violation privacy (approved 2026-10-22)

The user approved the design with the author's recommendation: **aggregate
only**. Guidance's ML and single/batch analysis show risk scores and counts for
all students but no individual violation details; individual violation history
opens only for endorsed students, through the column-limited read path. The
analysis therefore needs its own read path (SECURITY DEFINER function or view)
that returns aggregates, and Guidance loses direct `student_violations` read
access beyond endorsed students. Student Affairs, as the DO role, reads the
same analysis through its own RLS.

## Calls made by the author (not yet confirmed by the user)

- **"Violation history" in an endorsement** = offense, category, date and
  status only. Served through a column-limited SECURITY DEFINER function for
  endorsed students; never sanction, override reason, findings or notes.
- **Existing escalation reports** become endorsements: same table, violation
  link becomes optional, statuses stay `Pending_GC` / `Approved` / `Rejected`,
  and approval still sends the parent message (and optional meeting) as today.
- **Existing investigations and meetings** keep their rows. Any DO account can
  see and act on all of them; there is no per-officer ownership.
- **Open referrals** (and any new ones) are visible to the DO. Guidance no
  longer sees student referrals; a student who wants counseling reaches
  Guidance through the DO's endorsement.
- **Sanction log rows** (`log_type = 'sanction'`) are deleted, not hidden: the
  `sanctions` table is the record, and the rows were created automatically.
  Admin keeps read access to the remaining intervention logs.
- **"Student Affairs" is the existing Discipline Officer role**, so it gets
  ML and analysis through its own RLS, not a new role.
- **Good Moral resubmission** keeps the earlier submission as history; a
  flagged request still allows exporting the .docx.

## Left to the builder

- Table/column design for endorsements (rename `escalation_reports` or add a
  new table plus migration) and how the Guidance "violation history" read is
  limited to endorsed students.
- The exact RLS shape that removes Guidance's access to `student_violations`
  detail beyond endorsed students, `sanctions` and investigations.
- Where the DO "Investigations" tab and meeting dialog live in the DO module
  (reuse the existing Guidance investigations view and `ScheduleMeetingDialog`).
- The Good Moral status values for flagged / returned requests and the notice
  the student receives.
- Whether the DO can start an endorsement from a referral (assumed yes).
