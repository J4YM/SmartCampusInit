# Parent-availability scheduling for Guidance interventions, plus DO sanction and meeting-link fixes

Date: 2026-11-18

## Intent and why

Today, after Guidance approves an endorsement, the Discipline Officer (DO)
proposes a meeting time on their own and Guidance confirms it. The parent only
hears about it once Guidance confirms (via SMS), and has no say in the time.

New intent: the **parent's availability drives the schedule**. The DO becomes a
middle man who requests availability and follows the outcome; the parent offers
times; Guidance approves one. All communication and approvals happen in the
Parent Portal (SMS only prompts the parent to open it).

Two gaps are fixed alongside:

1. When an investigation finds a concern proven, the DO has no way to sanction
   the specific student involved.
2. After Guidance approves a meeting for an endorsement, the DO loses all
   connection to that meeting.

## Goals

- DO requests parent availability as the first scheduling step after Guidance
  approves an endorsement (unless the parent is excluded: `exclude_parent`).
- Parent offers at least one date/time, and may add several more, in the
  Parent Portal.
- DO and Guidance Counselor are both notified when the parent submits.
- Guidance approves one of the offered slots; only then is the meeting
  officially scheduled and the parent told it is confirmed.
- If Guidance declines (not available), the offered slot(s) are excluded and
  the parent is asked to pick other times; each re-request sends an SMS. The
  cycle repeats until a slot is approved.
- SMS wording changes: one message asking for availability (and for each
  re-ask), one confirming the final schedule.
- DO can mark each student in an investigation Proven or Not Proven, and can
  record a sanction for proven students.
- DO keeps visibility of the endorsement meeting after approval.

## Non-goals

- No new notification channel (no push, no email changes).
- No change to the Guidance approve/reject of the endorsement itself.
- No change to meetings that do not originate from an endorsement.
- DO does not approve or veto times; they only request and observe.

## Anti-goals

- Parent must never see a meeting as confirmed before Guidance approves it.
- A time the parent offered and Guidance declined must never be offered again
  in the same endorsement's scheduling cycle.
- Excluded parents must never be asked for availability.

## Constraints

- Stack: Flutter monorepo (`lib/`, `packages/*`), Supabase (Postgres RPCs,
  RLS, Edge Functions). Business logic lives in SQL RPCs; migrations are loose
  idempotent `supabase/*.sql` files run by hand. Follow that convention.
- Reuse existing pieces: `guidance_meetings` (status machine, `invitee`,
  `escalation_report_id`, `exclude_parent`), `queue_sms` / `sms_outbox`,
  `notifications`, `record_sanction`, `sanctions`, `complete_investigation`,
  `meeting_invitation_sms` (reworded). SMS text capped at 300 chars.
- Parent RLS currently hides `Awaiting_Guidance` and `Returned` meetings;
  new states must be visible to the parent where the parent has to act.
- Relevant code: `add_endorsement_meetings.sql` (propose/confirm/return/
  respond RPCs), `reword_meeting_invitations.sql`,
  `add_do_investigations.sql` (`complete_investigation`),
  `add_sanctions_schema.sql`, DO `endorsements_view.dart`, Guidance
  `referrals_view.dart`, parent `parent_portal_connected_page.dart` and
  `GuidanceMeetingsCard`.

## Decided by the user

- DO is the middle man; the first step is asking the parent for available
  times, and it notifies both DO and Guidance Counselor.
- Guidance approval is what officially schedules the meeting.
- On Guidance decline, repeat the process, exclude the previously offered
  date/time, ask the parent again, and send an SMS.
- Everything (communication and approvals) happens in the Parent Portal.
- Parent offers at least one date/time and can add several more options.
- DO marks each student Proven or Not Proven after investigation, then can
  sanction the proven student(s).

## Flow summary

1. Guidance approves endorsement (existing).
2. DO sees it and sends "request availability" (new status, e.g.
   `Awaiting_Parent`); parent notified in portal + SMS asking them to open it.
3. Parent submits 1..N date/time options -> status `Awaiting_Guidance`;
   DO and Guidance notified.
4. Guidance approves one option -> `Confirmed`/officially scheduled; parent
   and DO notified; SMS confirms the schedule.
   Guidance declines -> declined option(s) recorded as excluded, status back to
   `Awaiting_Parent`, parent notified + SMS asking for new times.

## Decided in the review round

- No response from parent: yes to both a reminder and a way to step in. The
  parent is reminded in the portal and by SMS, and the DO or Guidance can fall
  back to the old propose/confirm flow so a meeting is never stuck.
  (My call on the details: one reminder after 48 hours, and the fallback is
  available to the DO at any time while the request is open. Builder may
  adjust the numbers.)
- Excluded parent: the existing flow stays as is (DO proposes a time, Guidance
  confirms). The old propose/confirm/return RPCs and UI are kept.
- Meetings already `Awaiting_Guidance` or `Returned` when this ships finish
  under the old flow, with no conversion.

## Calls made by me (not yet confirmed by the user)

- Parents: every parent linked to the student can see the request and offer
  times; the first submission for a round counts, and the others are notified
  it was answered. Verify against the existing parent-link schema.
- Slots are a date plus a start time. The exclusion check blocks an exact
  date+time match within the same endorsement. Past times are rejected in the
  parent form and the RPC.
- Proven / Not Proven is stored per student on the investigation. A verdict is
  required for every involved student before the investigation can complete.
  Sanctions can only be recorded for Proven students. The DO may change a
  verdict until a sanction is recorded. Not Proven students get no sanction and
  no parent notification beyond what exists today.
- SMS goes to the same parent phone numbers the old flow used. A parent with no
  phone still gets the portal notification.
- DO recording a meeting outcome is allowed only for endorsement meetings.

## Left to the builder

- Data model for offered slots and exclusions (new table vs. columns), status
  names, and how they map onto the existing `guidance_meetings` statuses.
- Whether Guidance can decline individual slots or only the whole round.
  (Builder's call; default: Guidance picks one slot or declines the round.)
- Exact SMS and portal wording within the 300-character cap.
- Layout of the parent availability form, the DO request/status view, and the
  per-student Proven/Not Proven control in the existing investigation UI.
- Sanction UI for proven students: reuse the existing `sanction_dialog.dart`
  and `record_sanction`.
- DO meeting visibility after approval: show the meeting and its status in the
  DO endorsements view; allow the DO to see (and, by default, record the
  outcome of) the meeting, reusing `set_meeting_outcome`. (Assumption, my call.)
- Migration of in-flight meetings already `Awaiting_Guidance`/`Returned` under
  the old flow.
- Tests per the repo's existing conventions.
