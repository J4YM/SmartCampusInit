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

Optional checks (each rolls back): `test_incident_report_classification.sql`,
`test_sanctions_schema.sql`, `test_guidance_investigations.sql`,
`test_violation_expiry_weekdays.sql`, `test_enrollment_standing_guard.sql`.
They need at least one student, one handbook offense of each kind, and one
class section. The workflow functions now refuse callers without a role, so the
SQL Editor's default `postgres` user is refused by `classify_violation`,
`record_sanction` and friends: run those tests while impersonating an Admin
(Supabase dashboard: choose a user to run as, or set
`request.jwt.claims` to that Admin's profile id). They were written but have
not been run yet, so expect to adjust one if it trips on your data.

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

## 3. Escalation, Guidance and the two-way meeting

- [ ] Take the altercation report: **Classify** as a Major offense →
      **Escalate to Guidance**. Status shows **With Guidance**.
- [ ] Try **Sanction (override)** — it demands a written reason. Cancel.
- [ ] Sign in as the **Guidance Counselor → Investigations**. The case is there
      with the photo. **Schedule meeting** (student & parent).
- [ ] Sign in as the **Parent** (or Student): the **Guidance Meetings** card shows
      the invitation. First tap **Can't attend** with a note.
- [ ] Back as the Counselor: the meeting shows **Declined** with the reply
      (refreshes within ~15 s). **Reschedule meeting**.
- [ ] Parent: **Confirm**. Counselor sees **Confirmed**.
- [ ] Counselor: mark the meeting **Completed**, then **Complete investigation**
      with findings.

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

## Known limits to be upfront about

- The Security / Teacher **kiosk** report files the time and description but has
  no photo upload (touch kiosk, offline queue). Photos are on the Professor
  dashboard form.
- **Push** means an on-screen alert and sound while the DO dashboard is open;
  there is no mobile push service in the project.
- Lifting a restriction is an Admin database call for now; there is no Admin
  screen button yet.
- Meeting replies reach the Counselor on the dashboard's 15-second refresh.
