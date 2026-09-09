# Student & Parent Portal — Database Wiring + Good Moral Certificate Requests

## Context

`packages/student_portal_module` was added by a recent merge (PR #11,
"Add Student Portal module and roll out responsive/UI polish across all
dashboards") entirely mock-data-driven — its own `student_portal_mock_data.dart`
says explicitly: "no backend wired up yet." This spec wires it to real
Supabase data for violations, attendance, and schedule, and adds a new
student/parent-initiated Good Moral Certificate request flow.

Three pieces of relevant schema already exist, in varying states of
completeness — this spec was shaped by finding and reading all three
before writing a line of new SQL:

- **`student_violations`** (+ `handbook_offenses`) — fully real, actively
  used by the Discipline Officer module and the RFID kiosk today. No
  gaps.
- **`attendance_records`** (`supabase/add_professor_module_schema.sql`) —
  real, but **section-level**: one status per `(student_id, section_id,
  session_date)`, not per subject. The student portal's mock data
  currently simulates *per-subject* attendance (4 subjects/day, each
  with its own status) — that richness cannot be honestly wired to real
  data yet.
- **`subjects` / `class_sections` / `enrollments`**
  (`supabase/add_subjects_enrollments_schema.sql`, designed in
  `docs/superpowers/specs/2026-09-04-irregular-students-schema-design.md`
  as "Sub-project 1 of 3" of a larger Irregular Students epic) — the
  schema is real and complete (subject/professor/room/days/time,
  properly normalized), but **empty**: "nothing today reads these
  tables yet," and that same spec explicitly defers "Sub-project 3 —
  Enrollment management UI" (the tool that would populate `enrollments`)
  to later. That spec's "Sub-project 2 — Attendance redesign" (tap-in/
  tap-out + per-subject validation, which would resolve the
  `attendance_records` granularity gap above) is also not built.

This spec does not attempt either of those two deferred sub-projects in
full. It adds the one minimal piece of each needed to make the student
portal show real, non-empty data: a scoped-down enrollment tool (bulk-
enroll one section into one class offering, not full irregular-student
management), and section-level (not per-subject) attendance wiring.

## Goals

- Student Portal reads real `student_violations`, real `attendance_records`
  (section-level), and real `enrollments`/`class_sections`/`subjects`
  (once populated) instead of mock data.
- A student (or their linked parent) can submit a Good Moral Certificate
  request from the portal and see its status.
- The Discipline Officer's existing Good Moral Management "Requests"
  queue (already wired and reading real data — see Component 4) marks a
  request `Fulfilled` when the certificate is generated, closing the
  loop back to the student's status view.
- Registrar gets a minimal way to populate `enrollments` so schedules
  aren't permanently empty, without building the full enrollment-
  management UI the schema's own design doc defers.

## Non-goals (explicitly out of scope)

- Per-subject attendance (needs the tap-in/tap-out redesign — a future,
  separate sub-project; noted in code comments so it isn't re-discovered
  from scratch).
- Full irregular-student enrollment management (moving one student into
  a different section for one subject) — the schema supports it, this
  spec doesn't build UI for it.
- The Discipline Officer's "Students List" sub-tab (`fetchStudentDirectoryPage`,
  browsing all students independent of any request) — unrelated existing
  gap, not touched here.
- A deny/reject action on Good Moral requests — no UI for it exists
  today (only "Generate & Print Certificate"); adding one is a
  follow-up if the school wants it. The `status` column is plain `text`
  with a check constraint (not a fixed enum), so adding a `'Denied'`
  value later needs no migration beyond loosening that constraint.

## Architecture

Follows this repo's established convention exactly (every other wired
module — Discipline Officer, Guidance Counselor, Professor — shapes
this way): a presentation-only package (already built) + a
`*ConnectedPage` in `lib/ui/` fetching through a `*Repository` in
`lib/data/`. New files:

- `lib/data/student_portal_repository.dart`
- `lib/ui/student_portal_connected_page.dart`

No new architectural pattern introduced.

## Component 1: Violations

`StudentPortalRepository.fetchViolations(String studentId)` queries:

```dart
_client
    .from('student_violations')
    .select('id, status, created_at, handbook_offenses ( description, category )')
    .eq('student_id', studentId)
    .filter('archived_at', 'is', null)
    .order('created_at', ascending: false);
```

Mapped into the portal's existing `ViolationModel` / `ViolationCategory.fromDbValue`
/ `ViolationStatus` (already designed with the real column shapes in
mind — no model changes needed, this is a pure wiring task).

## Component 2: Attendance (section-level)

`fetchAttendance(String studentId, String sectionId, {required DateTime from, required DateTime to})`
queries `attendance_records` directly:

```dart
_client
    .from('attendance_records')
    .select('session_date, status')
    .eq('student_id', studentId)
    .eq('section_id', sectionId)
    .gte('session_date', from.toIso8601String())
    .lte('session_date', to.toIso8601String());
```

One `AttendanceStatus` per calendar day. The month grid / attendance
ring / day-detail sheet collapse to showing one mark per day instead of
per-subject — `aggregateStatus`'s "worst status wins" rollup becomes
unnecessary for real data (there's only ever one status per day now) but
stays in the codebase unused-but-harmless rather than deleted, since
it's still meaningful once per-subject attendance eventually lands.

Add a code comment at the call site (and in `attendance_models.dart`'s
`AttendanceStatus` doc comment) stating plainly: true per-subject
attendance needs the tap-in/tap-out + per-subject-validation redesign
from `docs/superpowers/specs/2026-09-04-irregular-students-schema-design.md`'s
deferred "Sub-project 2," which does not exist yet.

## Component 3: Schedule + minimal enrollment tool

### Read side (student portal)

`fetchSchedule(String studentId)`:

```dart
_client
    .from('enrollments')
    .select('''
      class_sections (
        room, schedule_days, start_time, end_time,
        subjects ( title ),
        profiles ( first_name, last_name )
      )
    ''')
    .eq('student_id', studentId)
    .eq('status', 'Active');
```

New minimal UI: a "My Schedule" list section on the student portal home
page (not a calendar/timetable redesign — a plain list: Subject —
Professor — Days — Time — Room, one row per active enrollment). Nothing
this detailed exists in the portal today; this is the smallest addition
that makes "connect his schedule" actually visible rather than only
present in a data model nothing renders.

### Write side (Registrar) — the minimal enrollment tool

New Postgres RPC, `security definer`, matching this repo's established
pattern for multi-row transactional writes (`record_rfid_tap`,
`submit_admission_slip`):

```sql
create or replace function public.enroll_section_students(
  p_class_section_id uuid
)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_section_id uuid;
  v_count int;
begin
  select section_id into v_section_id
    from public.class_sections
    where id = p_class_section_id;

  if v_section_id is null then
    raise exception 'Unknown class_sections id: %', p_class_section_id;
  end if;

  insert into public.enrollments (student_id, class_section_id)
  select s.id, p_class_section_id
    from public.students s
    where s.section_id = v_section_id
  on conflict (student_id, class_section_id) do nothing;

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke all on function public.enroll_section_students(uuid) from public;
grant execute on function public.enroll_section_students(uuid) to authenticated;
```

Idempotent (the existing `unique (student_id, class_section_id)`
constraint + `on conflict do nothing` means re-running for the same
offering only enrolls students who joined the section since last run —
handles new admissions cleanly with zero extra logic).

UI: an "Enroll Section" action added to each row of the Registrar's
existing `ClassScheduleView`/`_ScheduleRow` (the "Add Class Schedule"
table) — once that form is wired to create real `class_sections` rows
(see below), each row gets a button calling this RPC and toasting the
returned count ("12 students enrolled").

### Wiring the existing "Add Class Schedule" form to real data

`ClassScheduleView`'s Subject/Teacher dropdowns are currently hardcoded
single values ("Computer Programming 2", "Mr. Clark Gillerdo") — this
spec wires them to real `subjects` (anon/authenticated-readable, no RLS
change needed) and real professors (`profiles` where `role = 'Teacher'`).
"Save Changes" inserts a `class_sections` row instead of being a no-op.
This is the one piece of registrar-side work needed to make the
enrollment tool above meaningful (there must be a real `class_sections`
row to enroll students into).

## Component 4: Good Moral Certificate requests

### Schema change

```sql
alter table public.good_moral_requests
  add column if not exists status text not null default 'Pending';

alter table public.good_moral_requests
  add constraint good_moral_requests_status_check
  check (status in ('Pending', 'Fulfilled'));

drop policy if exists "good_moral_requests_student_insert_own" on public.good_moral_requests;
create policy "good_moral_requests_student_insert_own"
  on public.good_moral_requests
  for insert
  to authenticated
  with check (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and p.role = 'Student'::app_role
        and p.id = good_moral_requests.student_id
    )
  );

drop policy if exists "good_moral_requests_parent_insert_child" on public.good_moral_requests;
create policy "good_moral_requests_parent_insert_child"
  on public.good_moral_requests
  for insert
  to authenticated
  with check (
    exists (
      select 1
      from public.parent_student_links l
      join public.profiles p on p.id = l.parent_id
      where l.parent_id = auth.uid()
        and l.student_id = good_moral_requests.student_id
        and p.role = 'Parent'::app_role
    )
  );
```

(Mirrors the existing `good_moral_requests_student_select_own` /
`good_moral_requests_parent_select_child` SELECT policies exactly —
same shape, `for insert` instead of `for select`.)

### Student/parent side

New "Request a Document" action in the student portal: document type
(defaults to "Good Moral Certificate", matches the existing model's
free-text `document_type`), purpose, optional remarks. Inserts a row
with `requested_by` set to the signed-in user's display name. A simple
status list shows the requester's own past requests (`Pending` /
`Fulfilled`) via the existing student/parent SELECT policies — no new
RLS needed for reads.

### Discipline Officer side — already built, smaller than first thought

Correction from an earlier read of this spec's own research: this side
is **already fully wired**, not a placeholder. Confirmed by reading the
actual code (the schema file's "still UI-only placeholders" comment is
stale): `DisciplineRepository.fetchGoodMoralRequests()` and
`fetchStudentDirectoryPage()` both exist, are fully implemented (correct
joins, `hasActiveViolation`/`activeViolations` via
`fetchActiveViolationsByStudent()`), and are already called from
`discipline_officer_connected_page.dart` (lines 118-119, 161) feeding
`GoodMoralDashboardController`. `_generateCertificate` (same file,
line 225) is also already wired to the "Generate & Print Certificate"
button and produces the real DOCX via `good_moral_certificate_text.dart`.

The only actual gap: `_generateCertificate` doesn't touch the database
at all today (pure client-side document generation). Add one call at
the end of that method — only when
`selected.sourceSubTab == GoodMoralSubTab.requests` (a Students-List-
sourced generation has no originating request row to update) — updating
that request's row to `status = 'Fulfilled'` via a new
`DisciplineRepository.markGoodMoralRequestFulfilled(String requestId)`.

## Testing

- Repository methods: unit tests following whatever pattern
  `discipline_repository_test.dart` (or the nearest equivalent) already
  establishes for mocking/faking the Supabase client in this repo — check
  for one before writing a new pattern from scratch.
- New UI (My Schedule list, Request a Document flow): widget smoke tests
  matching `student_portal_home_page_smoke_test.dart`'s existing
  convention (the recent merge's own precedent).
- SQL: shown to the user for manual execution in the Supabase SQL Editor
  per this project's established "confirm SQL before DB writes"
  convention — not run automatically.

## Migration / rollout order

1. Run the `good_moral_requests` ALTER + new INSERT policies.
2. Run the `enroll_section_students` RPC creation.
3. Implement and verify Components 1-2 (violations, attendance) —
   lowest risk, no schema changes, pure reads.
4. Implement Component 3 (schedule + enrollment tool) — wire the
   existing Add Class Schedule form to real `subjects`/`class_sections`
   inserts, add the Enroll Section action, wire the student portal's
   read side.
5. Implement Component 4 (Good Moral requests) — student/parent submit
   UI, plus the one Fulfilled-on-generate addition to the Discipline
   Officer side's existing (already-wired) certificate generation.
