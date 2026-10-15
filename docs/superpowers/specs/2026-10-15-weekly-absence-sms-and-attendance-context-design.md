# Weekly Absence SMS + Professor Attendance Context — Design

Date: 2026-10-15
Status: Draft for review

## Goals

1. Send each student's guardian **one weekly SMS** listing the subjects the student was marked **Absent** in that week.
2. While a professor takes attendance for a selected day, show each student's attendance outcome in their **earlier classes that same day**, per professor, temporarily.
3. Refine how the tap-in information looks and is arranged in the attendance rows.

## Finding that drives the design

`attendance_records` is keyed by `(student_id, section_id, session_date)` and has no subject/class column, so per-subject status cannot be derived today. Attendance must become per class (`class_sections.id`, which already carries `subject_id`, `professor_id`, `start_time`, `end_time`).

## 1. Data — `supabase/add_attendance_per_class_section.sql`

- Add `attendance_records.class_section_id uuid references public.class_sections(id) on delete cascade` (nullable for legacy rows).
- Backfill where a record's section has exactly one `class_sections` row; ambiguous legacy rows stay `null` (section-level).
- Replace the unique constraint with `unique nulls not distinct (student_id, section_id, class_section_id, session_date)`; the `onConflict` upsert in `ProfessorRepository.submitAttendance` is updated to match.
- Add an index on `(class_section_id, session_date)`.
- Term rollover (`start_new_academic_term`) already archives `attendance_records`; `class_sections` is a protected table, so the FK does not change delete order. Idempotent migration.

## 2. Professor — earlier classes today

- Take Attendance targets one of the professor's classes (`class_sections.professor_id = me`); the roster comes from that class's Active `enrollments` (regular section students stay included via existing logic).
- New `ProfessorRepository.fetchEarlierClassesToday(studentIds, date, classSectionId)`: that day's attendance rows for classes with `start_time` earlier than the current class, ordered by `start_time`, including subject name and professor name. Empty on failure so attendance still loads.
- UI shows a per-student chain, e.g. `Prof. Cruz · Math 8:00 — Present → Prof. Reyes · PE 10:00 — Absent`.
- Visible **only** while taking attendance for the selected day; not in the weekly matrix or other dates. Read-only.

## 3. Tap-in row refinement

- Name + student number left; beneath, a small pill: green `Tapped in 8:02 AM` / grey `No tap yet` (replaces `_KioskTapIndicator`'s inline text).
- Earlier-class chips on the same line, wrapping on narrow widths: Present green, Absent red, Late amber, Excused blue-grey; tooltip carries full "Professor · Subject · time".
- Row height grows from 65px only when chips are present; header/hover styling unchanged.

## 4. Weekly parent SMS

- `sms_settings.weekly_absence_enabled boolean not null default true`.
- `pg_cron` job, **Friday 5:00 PM Asia/Manila** (09:00 UTC), calls `queue_weekly_absence_sms(p_week_start date default current week Monday)`.
- For each student with `Absent` records Mon–Sat of that week, group by subject with counts and queue one `weekly_absence` row through existing `queue_sms`.
- Idempotency: `related_id` = deterministic uuid derived from `student_id || week_start`; `unique (kind, related_id)` prevents double-queueing on re-run.
- Message: `STI Baliuag: Weekly absences for <Name> (Oct 12–17): Math ×2, PE ×1.` Truncate with `…and N more` to stay within a small number of SMS segments.
- No absences → no SMS. Late and Excused are not counted. Legacy rows with `class_section_id is null` are reported under "a class" (no subject name).
- Delivery, retries and invalid-number skipping use the existing `sms_outbox` / `send-sms` pipeline; no Edge Function change.

## Assumptions (confirm or correct)

- Friday 5 PM send time.
- Absent-only, silent on clean weeks.
- Professors take attendance per class they teach.

## Testing

- SQL test script (style of `test_late_replay_after_auto_tap_out.sql`): backfill correctness, weekly grouping, idempotent re-run, no-absence week, invalid guardian number.
- Dart: repository test for `fetchEarlierClassesToday` ordering/exclusion; widget tests for the tap pill and chips; submit upsert uses the new conflict key.

## Out of scope

- Changes to the kiosk tap flow or `send-sms` function.
- Admin UI for the weekly schedule (editable via `sms_settings` / cron for now).
