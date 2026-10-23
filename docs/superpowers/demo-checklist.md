# Discipline Workflow — Demo Checklist

For the capstone re-defense. Work top to bottom; tick as you go. Do the setup
the day before, not on stage.

## 0. Setup (once, on the demo Supabase project)

Run in the SQL Editor, in this order. Each is safe to re-run.

1. `supabase/add_incident_report_classification.sql`
2. `supabase/change_auto_escalation_to_suggestion.sql` — right after #1
3. `supabase/add_sanctions_schema.sql`
4. `supabase/add_guidance_investigations.sql`
5. `supabase/add_unclassified_slip_reports.sql`
6. `supabase/change_violation_expiry_to_flag.sql`
7. `supabase/add_enrollment_standing_guard.sql`
8. `supabase/demo_discipline_workflow.sql` — seeds three unclassified reports
9. `supabase/add_escalation_meeting_and_sanction_log.sql` — lets an approval invite
   the parent to a meeting (its sanction-log part is removed again by #10)
10. `supabase/add_endorsements.sql` — endorsements, referrals to the Discipline
    Officer, no sanctions for Guidance (needs #9 and `add_student_referrals.sql`)
11. `supabase/add_do_investigations.sql` — investigations, meetings and early
    sanctions belong to the Discipline Officer (needs #4, #3 and #10)
12. `supabase/add_good_moral_form_data.sql` — Good Moral slip fields, flag, send
    back and resubmit (needs `add_good_moral_status_and_insert_policies.sql`)

> **Re-running older scripts undoes #10.** `add_escalation_meeting_and_sanction_log.sql`
> restores the old approval function, the sanction-log trigger and its backfill;
> `add_sanctions_schema.sql`, `add_guidance_investigations.sql`,
> `add_violation_actions_log.sql` and `add_student_referrals.sql` give Guidance
> its old access back. If you re-run any of them, run `add_endorsements.sql`
> and then `add_do_investigations.sql` again afterwards.

Optional checks (each rolls back): `test_incident_report_classification.sql`,
`test_sanctions_schema.sql`, `test_guidance_investigations.sql`,
`test_violation_expiry_weekdays.sql`, `test_enrollment_standing_guard.sql`,
`test_endorsements.sql` (run it once before #10 to see it fail, once after). `test_do_investigations.sql` does the same for #11.
They need at least one student, one handbook offense of each kind, and one
class section. The workflow functions now refuse callers without a role, so the
SQL Editor's default `postgres` user is refused by `classify_violation`,
`record_sanction` and friends: run those tests while impersonating an Admin
(Supabase dashboard: choose a user to run as, or set
`request.jwt.claims` to that Admin's profile id). They were written but have
not been run yet, so expect to adjust one if it trips on your data.

## Real accounts (email + password)

The built-in logins (`do.demo`, `guidance.demo`, ...) are anonymous to the
database and are refused by the new workflow. Real accounts are separate users
in Supabase Auth, one per staff role, signed in with an **email address**:

`demo.admin`, `demo.registrar`, `demo.discipline`, `demo.guidance`,
`demo.teacher`, `demo.security`, `demo.ittech`, `demo.scheduling`, each at
`@baliuag.sti.edu.ph`. Their passwords are in
`supabase/local/real_account_credentials.txt` (git-ignored, never committed).

Set up once, in the Supabase SQL Editor:
1. `supabase/local/create_real_accounts.sql` (generated from
   `create_real_accounts.template.sql` with the passwords filled in).
2. `supabase/add_staff_policies_for_signed_in_users.sql`, so signed-in staff can
   read and write the tables the old anonymous logins could.

Then sign in on the login screen with the email and password. These accounts
are real, so role checks and RLS apply to them.

**Changing a password**
- Yourself: open your profile (top-right menu) and choose **Update password**.
  You must enter the current password; the new one needs 12+ characters with
  upper and lower case, a number and a symbol.
- An Admin resetting someone else's: edit that account's password in your local
  copy of `create_real_accounts.sql` and run it again, or run
  `update auth.users set encrypted_password = crypt('New#Strong2026Pass', gen_salt('bf')) where email = 'demo.discipline@baliuag.sti.edu.ph';`
  (these addresses are not real mailboxes, so emailed "forgot password" links
  never arrive).
- The built-in demo logins have a fixed password and cannot be changed.

**Use real accounts for the demo.** The Discipline Officer, Guidance
Counselor, Registrar, Professor and Parent/Student must be real signed-in users
with a profile and role. The built-in static demo logins (the ones that run on
the anonymous key) can no longer classify, escalate, sanction or schedule: those
actions are now refused without a role, and the Investigations tab and
disciplinary record read only for signed-in users.

## 1. Incident report (Professor)

- [ ] Open **Violation Reports → File an Incident Report**.
- [ ] Point out: there is **no violation picker**. The form asks who, **when it
      happened** (date and time), what happened, and **photos**.
- [ ] Pick a time in the future — the form refuses it.
- [ ] File a report with a photo attached.

## 2. Discipline Officer: classify and the minor bypass

- [ ] The new report appears marked **Needs classification**; the photo shows in
      the preview.
- [ ] **Classify** it as a Minor offense → **Auto-record**. One click: the
      violation is on the student's record with a handbook sanction. No
      investigation needed.
- [ ] Say it out loud: *minor offenses are handled by the DO; anything repeated,
      sensitive, or major goes to Guidance.* A repeat or sensitive report shows a
      **Suggested escalation** badge.

## 3. Investigation, meetings and the two-way acknowledgement

The Discipline Office runs the whole investigation; Guidance is not involved.

- [ ] Take the altercation report: **Classify** as a Major offense →
      **Start investigation**. Status shows **Under investigation**.
- [ ] Try **Sanction before findings** — it demands a written reason. Cancel.
- [ ] **Discipline Officer → Investigations**. The case is there with the photo.
      **Schedule meeting** (student & parent).
- [ ] Sign in as the **Parent** (or Student): the **Meetings** card shows the
      invitation. First tap **Can't attend** with a note.
- [ ] Back as the DO: the meeting shows **Declined** with the reply (refreshes
      within ~15 s). **Reschedule meeting**.
- [ ] Parent: **Confirm**. The DO sees **Confirmed**.
- [ ] DO: mark the meeting **Completed**, then **Complete investigation** with
      findings.
- [ ] Sign in as the **Guidance Associate**: there is no Investigations tab, and
      no notification about any of this.

## 4. Sanction that bars re-enrollment

- [ ] DO: the case now reads **Investigation complete**; **Sanction** is open.
- [ ] Choose **Non-readmission**. The form shows the red warning and requires the
      tick-box. The handbook penalty is pre-filled; edit it to show a **custom**
      sanction ("Recorded as a custom sanction").
- [ ] Record it. Case closes; the student is marked **Not for readmission**.
- [ ] Sign in as the **Registrar → Student Records**, open that student: red
      **Not for readmission** banner, **Disciplinary record** lists the sanction,
      and **Confirm Enrollment** is gone. (Trying to enroll them in a subject is
      refused with a clear message.)

## 5. 72-hour expiry

- [ ] DO queue: the third seeded report carries a red **Expired** marker, sorted
      to the top, and is **not archived**.
- [ ] An **URGENT** notification raised a red banner (it stays until dismissed).
      The banner only fires for an alert that arrives **while the DO dashboard is
      open**; one already waiting when the DO signs in rings nothing. So have the
      DO dashboard open first, then run `select public.expire_stale_violations();`
      (or re-run the seed) and the banner appears within a few seconds. The
      Expired marker itself shows either way.
- [ ] Mention: the clock skips Saturday and Sunday — a Friday 5 PM report is not
      expired on Monday morning.

## 6. Cleanup

- [ ] Run the commented cleanup block at the bottom of
      `demo_discipline_workflow.sql`.
- [ ] Lift the demo restriction (works in the SQL Editor as the project owner,
      or as a signed-in Admin):
      `select public.lift_enrollment_standing('<student id>', 'demo cleanup');`

## 7. Endorsements (Discipline Officer to Guidance Associate)

Sign in with the real accounts (see above), not the built-in demo logins.

- [ ] **Discipline Officer → Endorsements.** Every student is listed, including
      one with no violations. Search by name or number.
- [ ] **Endorse** a student with no violations for **Counseling**, with a
      reason. It appears under *Endorsements* as *Awaiting Guidance*.
- [ ] **Guidance Associate → Endorsement Approvals.** Open it: the reason is
      there, and *Violation history* says *No violations on record*. There is
      no message or meeting field. **Approve**.
- [ ] Guidance: **Intervention Logs** → add a log by hand for that student.
      Sanctions the officer recorded never appear in these logs.
- [ ] DO: endorse a student who has violations for **Parent intervention**.
      Guidance sees the offense, date and status of each violation, and no
      sanction. Approve with a message and optionally schedule the parent meeting.
- [ ] **Student portal**: file a self-referral. As the DO, open **Referrals**:
      it is there (the Guidance Associate has no Referrals tab). **Endorse** it:
      the reason is pre-filled and the referral becomes *In progress*.

## 8. Good Moral slip: autofill, comparison, send back

Run `supabase/add_good_moral_form_data.sql` first (setup list, after #11;
`test_good_moral_form_data.sql` checks it).

- [ ] **Student portal → My Documents → Request Good Moral.** The slip opens
      filled in from the student's record (name, student number, section,
      contact number, year started, school status *Enrolled*). Change the
      section to a wrong one, write an address, pick a reason, certify, submit.
- [ ] **Discipline Officer → Good Moral → Requests.** Open the request: the
      **Submitted slip** card lists each answer; the wrong section is red with
      **Differs from record** and what the school has. Address, middle name and
      last attended read **Not on record**.
- [ ] **Flag** it with a note: the request stays Pending and shows the note.
- [ ] **Send back to student** with a note. The student gets a notification and
      sees **Returned** with the note and **Edit & resubmit**.
- [ ] Student: fix the section, resubmit. The DO sees it Pending again with
      *Resubmitted 1 time*. **Generate & Print** works throughout, even while
      flagged.
- [ ] Parent portal: a parent-filed request has the same slip and the same
      send-back flow (no autofill).

## Known limits to be upfront about

- The Security / Teacher **kiosk** report files the time and description but has
  no photo upload (touch kiosk, offline queue). Photos are on the Professor
  dashboard form.
- **Push** means an on-screen alert and sound while the DO dashboard is open;
  there is no mobile push service in the project.
- Lifting a restriction is an Admin database call for now; there is no Admin
  screen button yet.
- Meeting replies reach the Counselor on the dashboard's 15-second refresh.
