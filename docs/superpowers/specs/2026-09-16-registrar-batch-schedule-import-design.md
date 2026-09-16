# Registrar Module — Batch Schedule Import (Classes+Professor, Faculty Loading, Room Schedule → Class Schedule)

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
these pivots the Registrar has on hand, reconcile them into one
canonical dataset in our schema, surface any inconsistencies between
sources for the Registrar to resolve, and derive the per-section Class
Schedule view from the result — replacing a manual, error-prone
cross-referencing task, not building a from-scratch timetabling solver.

Sample files (columns/shape only — no real student/staff data) were
reviewed directly during brainstorming for all four formats above.

## Goals

- Batch-upload many files at once (a full term is dozens of small
  per-professor CFL files and per-room Room Schedule files, plus zero or
  one Classes+Professor list) and have the system sort them by format
  automatically.
- Parse each format into a common internal shape: one row per **meeting**
  (subject, component [Lecture/Laboratory/null], section, professor, room,
  day, start time, end time, school year, term).
- Match each meeting's subject/section/professor/room against existing
  `subjects`/`sections`/`profiles`/room-alias data, or flag it as new for
  Registrar confirmation before anything is written.
- Detect and surface conflicts: the same professor or room double-booked
  at an overlapping day/time (within one file, across files in the same
  batch, or against already-committed data), and disagreements between
  sources describing what should be the same meeting.
- Let the Registrar review the parsed batch — matches, new entities to be
  created, and conflicts — before committing anything.
- On commit: write to `class_sections` (with a new child table for
  per-meeting detail — see Component 1) and render the per-section Class
  Schedule view from the result, reusing the existing Class Schedule tab.

## Non-goals (explicitly out of scope for this spec)

- **Inventing room/day/time for a subject nobody has scheduled anywhere
  yet.** If a subject+section appears in the Classes+Professor list but
  in neither CFL nor Room Schedule, it's surfaced as "no schedule data
  found" — the Registrar schedules it manually via the existing one-row
  form, same as today. No constraint-solving scheduler.
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
parsing/matching logic; a new import-wizard screen in
`packages/registrar_module` stays Supabase-agnostic, driven by
plain Dart models the repository produces; `RegistrarConnectedPage` wires
the two together. XLSX parsing uses the `excel` pub package (the
established choice for reading `.xlsx` in Dart/Flutter).

```
[Registrar picks N files] -> [detect format per file] -> [parse into
  ScheduleImportRow list] -> [match/resolve against existing DB data] ->
  [Registrar reviews: matches / new entities / conflicts] -> [commit:
  upsert subjects/sections/profiles/room_aliases/class_sections/
  class_section_meetings] -> [Class Schedule tab renders the result]
```

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

First time an alias is seen with no match, the Registrar picks "this is a
new room" (canonical name = the alias itself) or "this is the same room
as X" (existing canonical name) during the review step (Component 4);
either choice writes a `room_aliases` row so later imports resolve it
automatically.

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
- **Class Schedule** (in case the Registrar ever re-uploads one of these
  as a correction/reference): a cell matching `SCHEDULE OF CLASSES`; the
  section is parsed from the title line above it (e.g. "...(BSTM) 3C").

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
  code) **blocks commit until the Registrar types in its code** — never
  silently invented.
- **Section**: normalize by stripping spaces/hyphens before comparing
  (`BSIT 2A` == `BSIT-2A`) against `sections.name`. No match -> flagged as
  new; program/year_level are inferred from the section name where
  possible (e.g. `BSIT` + `2` -> needs a program-abbreviation ->
  `sections.program` full-name mapping, since our schema stores full
  names like `"BS Information Technology"` — a small Registrar-editable
  mapping, same pattern as room aliases, seeded empty and built up as
  imports surface new abbreviations).
- **Professor**: match by `Instructor ID` when available (Classes+
  Professor list), else by normalized full-name against
  `profiles.first_name`/`last_name` (CFL/Room Schedule). A name starting
  with `New ` and ending in a role word (`Faculty`/`Instructor`) followed
  by a number is treated as a placeholder (Component 1) and
  auto-resolved without asking. Any other unmatched name is flagged for
  the Registrar to either confirm "create new professor" or pick an
  existing one (guards against near-duplicate profiles from name-typo
  variants — never auto-created silently, unlike placeholders).
- **Room**: resolved via `room_aliases` (Component 1); unresolved ->
  flagged in review.

**Conflict detection**, run across the whole batch plus already-committed
data: the same professor or the same room with two meetings on the same
day whose time ranges overlap. Also, if both a CFL and a Room Schedule
row resolve to what looks like the same meeting (same subject + section
+ professor + day) but disagree on room or time, that's surfaced as a
cross-source conflict rather than silently picking one. Conflicts never
hard-block the batch — they're warnings the Registrar can override (real
source data has real mistakes) — but they're never silently dropped
either.

## Component 4: Review screen

Before anything is written: a summary grouped into three lists — **Ready
to import** (fully matched rows), **Needs your input** (new
subjects/sections/professors/rooms awaiting confirmation, each with a
quick create-new-vs-pick-existing control), and **Conflicts** (each with
the competing values and which source file each came from). Commit is
disabled while any "Needs your input" item is unresolved; conflicts can
be acknowledged and proceeded past individually.

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
meeting of each offering, not just one.

## Testing

Signature-guard tests (established pattern) for the new
`ScheduleImportRepository` methods. Parser unit tests per format using
small literal `.xlsx` fixtures covering: the Lecture/Laboratory split,
the two-time-ranges-in-one-cell case, a subject meeting on two different
days at two different times, and a placeholder-professor name. Matching
logic tests covering exact match, normalized match, and the
no-match-flagged path for each entity type. A conflict-detection test
covering same-professor overlap, same-room overlap, and a CFL/Room
Schedule disagreement.

## Migration / rollout order

1. `supabase/add_class_section_meetings_schema.sql` and
   `supabase/add_room_aliases_schema.sql` — shown to the user for manual
   approval in the Supabase SQL Editor, never auto-run (this repo's
   established convention).
2. `ScheduleImportRepository` — format detection + parsers + matching +
   conflict detection (no UI yet, tested standalone).
3. Review screen + wizard UI in `registrar_module`.
4. `class_schedule_view.dart`'s display extended to render multiple
   meetings per offering.
5. `RegistrarConnectedPage` wiring.
