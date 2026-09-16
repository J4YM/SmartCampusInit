# Batch Schedule Import — Registrar Roster Upload + New Scheduling Officer Role (Classes+Professor, Faculty Loading, Room Schedule → Class Schedule)

## Context

The school's official centralized system (a PeopleSoft/Campus-Solutions-style
SIS — "Career", "Class No" terminology) is the source of truth for
enrollment and grading, but this project is a 3rd-party system running
alongside it, not replacing it. The Registrar currently has to hand-build
the per-section Class Schedule (the artifact `class_schedule_view.dart`
already lets them enter one offering at a time) by manually
cross-referencing several *different exports* the official system already
produces, each a different pivot over the same underlying, already-decided
schedule:

1. **Classes + Professor list** ("Course and Grade Monitoring" report) —
   one row per class offering (`Class No`), with `Course Code`/`Description`
   (subject), `Instructor ID` + name, and enrollment/grade-submission
   tracking. No room, day, time, or section.
2. **Confirmation of Faculty Loading (CFL)** — one file per professor
   (professor's name is the document header, not a row value), listing
   every subject they teach, split into Lecture/Laboratory sub-rows, each
   with day(s)/time(s), room, and **section**. Also carries admin metadata
   (working hours, total units, overload flag, approval signatures) that
   this spec does not act on.
3. **Room Schedule** — one file per room (room name is the document
   header), listing every subject meeting held there, with
   day(s)/time(s), instructor, and section.
4. **Class Schedule** (the target/output shape) — one sheet per section,
   listing every subject the section takes, split into
   Lecture/Laboratory sub-rows, each with day(s)/time(s), room, and
   instructor.

CFL and Room Schedule are two different pivots over data that is **already
fully decided** by the school (subject, section, professor, room, day,
time) — they are not separate constraints to solve for. The real,
confirmed goal (per brainstorming discussion) is: ingest whichever of
these pivots are available, reconcile them into one canonical dataset in
our schema, surface any inconsistencies between sources for a human to
resolve, and derive the per-section Class Schedule view from the result —
replacing a manual, error-prone cross-referencing task, not building a
from-scratch timetabling solver.

**Two different people do this work, and they get two different tools.**
The Registrar only ever has the Classes+Professor list (which subject
each professor is assigned, no room/time/section) — they upload that and
nothing else. A separate person — the **Scheduling Officer** (a distinct
job, not a Registrar sub-permission; matches the "Academic Head"/"Deputy
School Administrator" signatories already visible on the CFL sample) is
the one who actually receives the CFL and Room Schedule files and turns
them into the finished per-section schedule. This spec introduces
Scheduling Officer as a new role with its own dashboard, matching every
other role in this codebase (Registrar, Professor, IT Technician,
Discipline Officer, Guidance Counselor each already have their own
`app_role` value, dashboard package, connected page, and login route).

Sample files (columns/shape only — no real student/staff data) were
reviewed directly during brainstorming for all four formats above.

## Goals

- **New Scheduling Officer role** (Component 0): its own dashboard,
  reachable both through the shared login screen (real Supabase-
  authenticated role, like Registrar/Professor today) and via its own
  dedicated, login-free standalone Windows build (matching
  `main_it_technician.dart`'s pattern).
- **Registrar's scope, unchanged elsewhere:** a new, simple upload for
  the Classes+Professor list only — establishes/validates the
  subject+professor roster. Registrar never sees CFL/Room Schedule
  upload UI at all.
- **Scheduling Officer's scope:** batch-upload many files at once (a full
  term is dozens of small per-professor CFL files and per-room Room
  Schedule files) and have the system sort them by format automatically;
  parse each into a common internal shape: one row per **meeting**
  (subject, component [Lecture/Laboratory/null], section, professor, room,
  day, start time, end time, school year, term); match each meeting's
  subject/section/professor/room against existing
  `subjects`/`sections`/`profiles`/room-alias data, or flag it as new for
  confirmation; cross-check against the Registrar-uploaded roster (a
  subject+professor pairing in CFL/Room Schedule that isn't in the
  roster, or vice versa, is a conflict); detect and surface conflicts —
  the same professor or room double-booked at an overlapping day/time,
  disagreements between CFL and Room Schedule describing what should be
  the same meeting, and a meeting's actual duration not matching what its
  Course Unit count implies (see Component 3a); review before committing
  anything.
- On commit: write to `class_sections` (with a new child table for
  per-meeting detail — see Component 1) and render the per-section Class
  Schedule view from the result, reusing the existing Class Schedule tab.

## Non-goals (explicitly out of scope for this spec)

- **Inventing room/day/time for a subject nobody has scheduled anywhere
  yet.** If a subject+section appears in the Classes+Professor list but
  in neither CFL nor Room Schedule, it's surfaced (to the Scheduling
  Officer, in the review screen) as "no schedule data found" — someone
  schedules it manually via the Registrar's existing one-row form, same
  as today, no constraint-solving scheduler. That existing form does get
  one small enhancement (Component 3a): its Start/End time fields
  prefill a suggested duration derived from the subject's Course Unit
  count, purely as a starting point the person filling it out can
  override — not automatic placement.
- **Exporting back out to a pixel-matching XLSX/PDF** in any of the four
  original formats. v1 renders the per-section schedule in-app, reusing
  `class_schedule_view.dart`'s existing display. A "download as XLSX/PDF"
  action can follow later as its own scoped piece of work.
- **Enforcing professor total-load/overload rules.** CFL's own "Total
  Number of Units", "Total No. of Hours/Week", and "BLUE HIGHLIGHT -
  OVERLOAD" are read as informational metadata (attached to the professor
  record for display) but never block an import or a save.
- **Curriculum/requirements-table-driven validation** (e.g. "is this
  subject actually part of this program's curriculum") — same deferral
  as the existing Class Schedule spec.
- Ingesting the Classes+Professor list's grade-submission-compliance data
  (Date Submitted/Date Modified, PRELIM/MIDTERM/PREFINALS/FINALS
  compliance columns) — irrelevant to scheduling, ignored entirely.

## Architecture

Same established pattern as the rest of this codebase: a new
`ScheduleImportRepository` (in `lib/data/`) owns Supabase access and all
parsing/matching logic, shared by both roles' UIs. Registrar's roster
upload lives in `packages/registrar_module` (a small new screen/dialog,
Supabase-agnostic like every other Registrar tab); the Scheduling
Officer's full upload/review/generate flow lives in a new
`packages/scheduling_officer_module`. XLSX parsing uses the `excel` pub
package (the established choice for reading `.xlsx` in Dart/Flutter).

```
Registrar:  [upload Classes+Professor list] -> [parse -> roster rows] ->
  [match/create subjects+profiles] -> [commit roster]

Scheduling Officer:  [pick N CFL/Room Schedule files] -> [detect format
  per file] -> [parse into ScheduleImportRow list] -> [match/resolve
  against existing DB data + the roster] -> [review: matches / new
  entities / conflicts] -> [commit: upsert subjects/sections/profiles/
  room_aliases/class_sections/class_section_meetings] -> [Class Schedule
  tab (Registrar) + Scheduling Officer's own view both render the result]
```

## Component 0: New role — Scheduling Officer

Mirrors the IT Technician role exactly (`add_it_technician_schema.sql`
is the template for every piece below):

- **`app_role` enum**: `alter type public.app_role add value if not
  exists 'Scheduling_Officer';` — run in its own statement/transaction
  per this codebase's existing documented constraint (see
  `add_it_technician_schema.sql`'s comment on why `ALTER TYPE ... ADD
  VALUE` can't share a transaction with its first use).
- **Dashboard package**: `packages/scheduling_officer_module` — a
  Supabase-agnostic presentation package, following
  `discipline_officer_module`'s/`guidance_counselor_module`'s existing
  shape (a dashboard page + tabs, initial\*/callback props, no direct
  Supabase imports).
- **Connected page**: `lib/ui/scheduling_officer_connected_page.dart` —
  wires the dashboard to `ScheduleImportRepository`, following
  `registrar_connected_page.dart`'s pattern (gated on
  `AppEnv.supabaseConfigured`, demo-account id fallback for the RFID-
  style "no real Supabase Auth session" case — see
  `lib/ui/registrar_connected_page.dart`'s `_effectiveRegistrarId`
  precedent, since a `scheduling.demo` static account will need the same
  treatment for any FK write it makes, e.g. `class_sections`'s eventual
  audit/actor columns if this spec adds any).
- **Login route**: a `scheduling.demo` entry in
  `lib/auth/static_demo_accounts.dart` (id `u_scheduling`, matching every
  existing demo account's shape) plus wiring into whatever routes real
  Supabase-authenticated roles to their dashboard (same place
  `AppRole.itTechnician`/`AppRole.registrar` are already routed).
- **Standalone Windows build**: `lib/main_scheduling_officer.dart` — a
  new entry point, no login gate, boots straight into
  `SchedulingOfficerConnectedPage` — copy `lib/main_it_technician.dart`'s
  exact shape (falls back to its connected page's own demo-identity
  default, matching kiosk's "nothing to sign out to" precedent). Plus
  `windows/installer/scheduling_officer_installer.iss`, copying
  `it_technician_installer.iss`'s shape (including its physical-security
  assumption note, since this is the same login-free-on-a-dedicated-
  machine tradeoff).
- **RLS**: every policy in Components 1 and elsewhere in this spec that
  currently reads `current_user_role() in ('Registrar'::app_role,
  'Admin'::app_role)` needs `'Scheduling_Officer'::app_role` added
  wherever the Scheduling Officer's flow writes (class_sections,
  class_section_meetings, room_aliases, subjects, sections) — the
  Registrar's roster-only upload does not need the Scheduling Officer
  role added to anything, since it never touches those tables' write
  paths this spec doesn't already cover.

## Component 1: Schema changes

`class_sections` today assumes one room + one day-set + one time range per
offering — real data needs multiple meetings per offering (a Lecture row
and a Laboratory row, each with its own room/day/time; a single component
can even meet on two different days at two different times, e.g. CTHC1015
in the sample: Wed 3:30-5:00 in one room-context and Fri 10:00-11:30).

```sql
-- supabase/add_class_section_meetings_schema.sql

create table if not exists public.class_section_meetings (
  id uuid primary key default gen_random_uuid(),
  class_section_id uuid not null references public.class_sections(id) on delete cascade,
  component text check (component in ('Lecture', 'Laboratory')), -- null when the subject has no lecture/lab split
  day text not null check (day in ('M','T','W','TH','F','S')),
  start_time time not null,
  end_time time not null,
  room text not null,
  created_at timestamptz not null default now()
);

create index if not exists idx_class_section_meetings_class_section
  on public.class_section_meetings(class_section_id);

-- RLS mirrors class_sections' existing anon+authenticated select policy
-- (catalog-like data) plus registrar/admin-only write, matching this
-- repo's established convention.
```

`class_sections.room`/`schedule_days`/`start_time`/`end_time` become
**deprecated but not dropped** in this spec (existing rows and the
existing manual one-row entry form keep working unchanged, writing a
single `class_section_meetings` row with `component: null` behind the
scenes — the flat columns stay as a compatibility shim, not touched
further). `class_schedule_view.dart`'s display is extended to render
*all* of a `class_section`'s meetings (one line per meeting) instead of
assuming exactly one.

**New: room aliases.** Room names are wildly inconsistent across sources
in the sample data (`COMPUTER LABORATORY 2` / `Comlab2` / `ComLab 1` /
`RM 202`) — similar-looking strings can be genuinely different rooms
(`ComLab 1` vs `ComLab 3`), so fuzzy string matching alone is unsafe.

```sql
-- supabase/add_room_aliases_schema.sql

create table if not exists public.room_aliases (
  id uuid primary key default gen_random_uuid(),
  alias text not null unique,       -- exact string as it appears in an uploaded file
  canonical_room text not null,     -- the name shown everywhere in our UI
  created_at timestamptz not null default now()
);
```

First time an alias is seen with no match, the Scheduling Officer picks
"this is a new room" (canonical name = the alias itself) or "this is the
same room as X" (existing canonical name) during the review step
(Component 4);
either choice writes a `room_aliases` row so later imports resolve it
automatically.

**New: program aliases.** Same problem, same fix, for the program
abbreviations CFL/Room Schedule/Classes+Professor list use (`BSIT`,
`BCT`) against `subjects.program`/`sections.program`'s full names (`"BS
Information Technology"`):

```sql
-- supabase/add_program_aliases_schema.sql

create table if not exists public.program_aliases (
  id uuid primary key default gen_random_uuid(),
  alias text not null unique,          -- e.g. "BSIT", "BCT"
  canonical_program text not null,     -- e.g. "BS Information Technology"
  created_at timestamptz not null default now()
);
```

**Placeholder professors.** Names like `New IT Faculty 2`/`New GE
Instructor 2` (unfilled positions) get a real `profiles` row the first
time they're seen (`role: 'Teacher'`, a new `status: 'Placeholder'` value
alongside the existing `approval_status` values), reused by exact-name
match on later imports — same FK shape as a real professor, so it shows
up correctly anywhere `professor_id` is already joined/displayed, just
visibly flagged as unfilled.

## Component 2: File-format detection and parsing

Each format has a distinctive, checkable signature — detection reads a
small fixed set of cells per sheet, no guessing:

- **Classes+Professor list**: header row contains `Class No` and
  `Instructor ID`.
- **CFL**: a cell containing the literal text `Confirmation of Faculty
  Loading`; the professor's name is read from the `Instructor:` labeled
  cell (sample page 3).
- **Room Schedule**: a cell containing `ROOM SCHEDULE`; the room name is
  the line directly below it.
- **Class Schedule** (in case the Scheduling Officer ever re-uploads one
  of these as a correction/reference): a cell matching `SCHEDULE OF
  CLASSES`; the section is parsed from the title line above it (e.g.
  "...(BSTM) 3C").

A file matching none of these is rejected with a clear "couldn't
recognize this file's format" message — never silently skipped.

Each parser produces a list of `ScheduleImportRow` (subjectTitle,
subjectCode [Classes+Professor list only], component, section,
professorName or instructorId, room, day, startTime, endTime). Parsing
must handle the two real merged-layout patterns seen in every sample:
a subject spanning a Lecture row + a Laboratory row (each an independent
`ScheduleImportRow`), and a single cell holding two time ranges
separated by `/` (e.g. `12:00-2:00 / 5:00-6:00`), which expands into two
separate `ScheduleImportRow`s sharing everything but the time range.

## Component 3: Matching / reconciliation

For each parsed row, resolve against existing data:

- **Subject**: match by `subjects.code` when the source row has one
  (Classes+Professor list); otherwise by case/whitespace-normalized
  `subjects.title` (CFL/Room Schedule carry no code at all). No match ->
  flagged as a new subject in the review step; since `subjects.code` is
  `not null unique`, a new subject sourced from CFL/Room Schedule (no
  code) **blocks commit until the Scheduling Officer types in its
  code** — never silently invented.
- **Section**: normalize by stripping spaces/hyphens before comparing
  (`BSIT 2A` == `BSIT-2A`) against `sections.name`. No match -> flagged as
  new; program/year_level are inferred from the section name where
  possible (e.g. `BSIT` + `2` -> needs a program-abbreviation ->
  `sections.program` full-name mapping, since our schema stores full
  names like `"BS Information Technology"` — a small mapping the
  Scheduling Officer builds up, same pattern as room aliases, seeded
  empty and filled in as imports surface new abbreviations).
- **Professor**: match by `Instructor ID` when available (Classes+
  Professor list), else by normalized full-name against
  `profiles.first_name`/`last_name` (CFL/Room Schedule). A name starting
  with `New ` and ending in a role word (`Faculty`/`Instructor`) followed
  by a number is treated as a placeholder (Component 1) and
  auto-resolved without asking. Any other unmatched name is flagged for
  the Scheduling Officer to either confirm "create new professor" or
  pick an existing one (guards against near-duplicate profiles from
  name-typo variants — never auto-created silently, unlike placeholders).
- **Room**: resolved via `room_aliases` (Component 1); unresolved ->
  flagged in review.
- **Roster cross-check**: every subject+professor pairing the Registrar's
  Classes+Professor upload established is checked against what CFL/Room
  Schedule actually show. A pairing in the roster with no matching
  CFL/Room Schedule meeting at all is the "no schedule data found" case
  (Non-goals); a CFL/Room Schedule meeting whose subject+professor
  pairing isn't in the roster at all is flagged too — either the roster
  is stale or the loading/room file has the wrong professor.

## Component 3a: Unit -> hours validation

Standard convention, confirmed directly against every sample row: **1
lecture unit = 1 hour/week, 1 laboratory unit = 3 hours/week** (every
"Lecture N" row in the samples sums to exactly N hours across however
many days it's split into; every "Laboratory (3 hours)" row is fixed at
3 hours regardless of its unit count being labeled "1"). A subject with
no lecture/lab split maps its whole unit count 1:1 to hours (a 3-unit
GEDC subject = 3 hours/week), matching the samples exactly.

For each resolved offering, sum its meetings' durations per component
and compare to `expected_hours = lecture_units * 1 + lab_units * 3` (or
`units * 1` when there's no split). A mismatch is a conflict (below) —
flagged as "N hours scheduled, M expected from unit count" — the
Scheduling Officer can still proceed (a real school schedule can
legitimately deviate), never a hard block.

This same rule feeds one small, separate enhancement to the *existing*
manual one-row entry form (`class_schedule_view.dart`, used when a
subject has no CFL/Room Schedule data at all — see Non-goals): its
Start/End time fields prefill with a suggested duration derived from the
subject's units — never an automatic day/room placement, purely a
starting value the person filling it out can change.

**Conflict detection**, run across the whole batch plus already-committed
data: the same professor or the same room with two meetings on the same
day whose time ranges overlap. Also, if both a CFL and a Room Schedule
row resolve to what looks like the same meeting (same subject + section
+ professor + day) but disagree on room or time, that's surfaced as a
cross-source conflict rather than silently picking one. Conflicts never
hard-block the batch — they're warnings the Scheduling Officer can
override (real source data has real mistakes) — but they're never
silently dropped either.

## Component 4: Review screen

Before anything is written: a summary grouped into three lists — **Ready
to import** (fully matched rows), **Needs your input** (new
subjects/sections/professors/rooms awaiting confirmation, each with a
quick create-new-vs-pick-existing control), and **Conflicts** (each with
the competing values and which source file each came from). Commit is
disabled while any "Needs your input" item is unresolved; conflicts can
be acknowledged and proceeded past individually. This screen belongs to
the Scheduling Officer's dashboard — the Registrar's roster upload has
its own, much simpler confirm-and-save step (new subjects/professors
found in the roster, nothing else, since there's no room/time/conflict
data in that file at all).

## Component 5: Commit and render

On confirm: upsert `subjects`/`sections`/`profiles`/`room_aliases`/program
mappings as resolved in Component 4, then upsert `class_sections` (one
per unique subject+section+school_year+term) and
`class_section_meetings` (one per resolved `ScheduleImportRow`).

Re-uploading a corrected file must update existing meetings rather than
duplicate them, but `class_section_id + component + day` is not a safe
key on its own — the two-time-ranges-in-one-cell case (Component 2)
intentionally produces two meetings sharing exactly that triple, only
distinguished by their time range, which is precisely the field a
correction might change. The key instead includes an explicit sequence:
order a component's meetings on a given day by their original column
position (left-to-right within the merged cell, or row order for
same-day/different-time rows), and key on
`class_section_id + component + day + sequence` (sequence `0`, `1`, ...
in that order). A correction that changes only the time range still
matches the same key and updates in place; a genuine addition of a new
meeting gets the next sequence number rather than colliding.

The Class Schedule tab's existing per-section view
(`class_schedule_view.dart`) is extended to read and render every
meeting of each offering, not just one — this same widget is reused
(not duplicated) inside the Scheduling Officer's dashboard so both
roles see an identical rendering of the same data.

## Testing

Signature-guard tests (established pattern) for the new
`ScheduleImportRepository` methods. Parser unit tests per format using
small literal `.xlsx` fixtures covering: the Lecture/Laboratory split,
the two-time-ranges-in-one-cell case, a subject meeting on two different
days at two different times, and a placeholder-professor name. Matching
logic tests covering exact match, normalized match, and the
no-match-flagged path for each entity type. A conflict-detection test
covering same-professor overlap, same-room overlap, a CFL/Room Schedule
disagreement, a unit-hours mismatch (Component 3a), and a roster
cross-check miss in both directions. A widget-wiring test for
`SchedulingOfficerConnectedPage`, mirroring the existing
`it_technician_dashboard_tab_wiring_test.dart` pattern.

## Migration / rollout order

1. `supabase/add_it_technician_schema.sql`-style role addition: `alter
   type ... add value 'Scheduling_Officer'` plus its demo system profile
   seed (Component 0) — shown to the user for manual approval, never
   auto-run.
2. `supabase/add_class_section_meetings_schema.sql`,
   `supabase/add_room_aliases_schema.sql`, and
   `supabase/add_program_aliases_schema.sql` — same manual-approval
   convention.
3. `ScheduleImportRepository` — format detection + parsers + matching +
   conflict detection + the unit-hours rule (no UI yet, tested
   standalone).
4. `class_schedule_view.dart`'s display extended to render multiple
   meetings per offering (shared by both dashboards).
5. `packages/scheduling_officer_module` — upload/review/generate UI.
6. `SchedulingOfficerConnectedPage` + `lib/main_scheduling_officer.dart`
   + `scheduling_officer_installer.iss` + `scheduling.demo` account.
7. Registrar's roster-only upload (small addition to `registrar_module`)
   + `RegistrarConnectedPage` wiring.
