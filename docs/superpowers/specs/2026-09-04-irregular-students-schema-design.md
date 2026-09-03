# Irregular Students — Subjects & Enrollment Schema (Sub-project 1 of 3)

## Context

"Irregular student" means: a student's home section (e.g. BSIT-3B) stays
fixed, but for one or more specific subjects they attend a *different*
section's class — most commonly because they're retaking a subject from an
earlier year level, or taking one ahead of their cohort.

Today's schema has no way to express this at all. `students.section_id` is
a single FK — one section, full stop — and `sections` conflates two
different concepts: a homeroom/advisory roster *and* a course offering.
There is no `subjects`, `class_sections`, `enrollments`, or `grades` table
anywhere in the database. This was confirmed by direct inspection of every
`supabase/*.sql` file and by tracing how `students.section_id` is read
throughout the RFID kiosk, Discipline Officer, Professor, and Registrar
modules — all of them assume one section per student.

This gap also blocks the Registrar module's Grades and Class Schedule tabs
(currently mock-only — no backing tables) and the attendance redesign the
school wants (gate tap-in/tap-out, then per-subject teacher validation) —
"validate this subject" has no meaning without subjects existing as real
rows.

This document specs **only** the schema itself — the minimum structure
that lets a student's subject-level enrollments exist independently of
their home section, with zero duplication and zero special-casing for
"irregular" students. Two related pieces are explicitly deferred (see
"Out of scope" below) so this stays a single, reviewable unit of work.

## Approach: uniform enrollment (Approach A)

Every student — regular or irregular — gets explicit `enrollments` rows,
one per subject they're taking. There is no "is_irregular" flag and no
separate override table. A student is irregular *only* in the sense that
one or more of their `enrollments` rows points at a `class_sections` row
whose `section_id` differs from their `students.section_id`. Every other
piece of code (a professor's roster, a per-subject attendance query, a
transcript) reads the exact same `enrollments` table the exact same way
regardless of whether the student is regular or not.

The alternative (an override table only for exceptions, falling back to
"whatever the home section offers" for everyone else) saves some rows at
enrollment time, but pushes a permanent "check overrides, else fall back"
branch into every downstream query — including the attendance validation
flow sub-project 2 will build. At this school's scale (1-2k students ×
~8-12 subjects ≈ 10-25k enrollment rows) that row-count saving is not a
real cost; the branching complexity it avoids is a real, permanent
benefit. See the conversation this spec came out of for the fuller
trade-off discussion.

## Schema

Three new tables. **No existing table's columns change.**

### `subjects`

One row per course offered anywhere in the school (e.g. "Data Structures
and Algorithms"), independent of who teaches it or to which section.

```sql
create table public.subjects (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,        -- e.g. 'CS301'
  title text not null,              -- e.g. 'Data Structures and Algorithms'
  program text,                     -- e.g. 'BS Information Technology' — nullable: some subjects (Euthenics, PE) are cross-program
  year_level int,                   -- nominal year level it's normally taken at; nullable for the same reason
  created_at timestamptz not null default now()
);
```

### `class_sections`

One row per *actual offering* of a subject — a specific professor teaching
a specific subject to a specific roster on a specific schedule. This is
the entity a student actually enrolls in, and the entity a teacher takes
attendance against.

```sql
create table public.class_sections (
  id uuid primary key default gen_random_uuid(),
  subject_id uuid not null references public.subjects(id),
  section_id uuid not null references public.sections(id),  -- the roster this offering is organized under
  professor_id uuid references public.profiles(id),
  room text,
  schedule_days text[],             -- e.g. '{Mon,Wed,Fri}'
  start_time time,
  end_time time,
  school_year text not null,        -- e.g. '2026-2027'
  term text not null,                -- e.g. '1st Semester'
  created_at timestamptz not null default now()
);

create index idx_class_sections_subject on public.class_sections(subject_id);
create index idx_class_sections_section on public.class_sections(section_id);
```

`section_id` here is *organizational*, not restrictive — it's "which
roster this offering nominally belongs to," used for scheduling/admin
filtering. It does not limit who can enroll in it; that's the whole point.

### `enrollments`

The join table: which students are taking which class_sections.

```sql
create table public.enrollments (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students(id),
  class_section_id uuid not null references public.class_sections(id),
  status text not null default 'Active',  -- 'Active' | 'Dropped'
  created_at timestamptz not null default now(),
  unique (student_id, class_section_id)
);

create index idx_enrollments_student on public.enrollments(student_id);
create index idx_enrollments_class_section on public.enrollments(class_section_id);
```

## How this solves "irregular students, no duplication"

- A **regular** student has one `enrollments` row per required subject,
  each pointing at a `class_sections` row whose `section_id` matches
  their `students.section_id`.
- An **irregular** student has the exact same shape of data — one
  `enrollments` row per subject — except one or more of those rows points
  at a `class_sections` row belonging to a *different* section (e.g.
  they're retaking "Data Structures" with BSIT-2B while the rest of their
  subjects are with their real section, BSIT-3B).
- No new student row, no duplicate student identity, no flag to keep in
  sync. "Irregular" is a fact you can *observe* from `enrollments` joined
  to `class_sections`/`sections`, not a state you have to *declare* and
  maintain.

## What stays unchanged

- `students.section_id` / `sections` — untouched. Still the home/advisory
  grouping used exactly as today by the RFID kiosk, Discipline Officer,
  Admin Student Directory, and Registrar.
- `attendance_records` — untouched. Still section-level for now; becomes
  subject-level (referencing `class_sections`) in sub-project 2, not here.
- `class_assignments` (professor ↔ section) — untouched, and **not**
  reconciled with `class_sections.professor_id` in this phase. There is
  now a genuine overlap between the two (a professor can be tied to a
  section two different ways), acknowledged and deliberately deferred —
  resolving it means touching the Professor module's existing
  attendance-taking flow, which is out of scope for a pure schema
  addition. Flagged here so it isn't forgotten.

## Out of scope (deferred to later sub-projects / follow-up specs)

- **Sub-project 2 — Attendance redesign**: the tap-in/tap-out gate log
  plus per-subject teacher validation, now backed by `class_sections`.
- **Sub-project 3 — Enrollment management UI**: Registrar/Admin tooling
  to actually create `class_sections` and bulk-enroll a section's regular
  students, plus a flow for moving one student into a different
  `class_section` for one subject (the actual "mark this student
  irregular for Subject X" action).
- **Curriculum/requirements table** (e.g. "BSIT year 3 requires these 8
  subjects"): would let auto-enrollment be curriculum-driven instead of
  manual. Not required for the schema itself to work — enrollments can be
  created directly — but likely wanted by sub-project 3.
- **RLS policies** for the three new tables: follow this repo's existing
  per-table policy-file pattern (see `supabase/rls_sections_select.sql`
  for the convention); not fully specified here since it's mechanical
  once the tables exist and the relevant roles are known.

## Migration

The three `create table` statements above, run once, in the order shown
(each references the previous). Purely additive — no existing table is
altered, no existing query breaks, no backfill required (existing
students simply have zero `enrollments` rows until sub-project 3's
enrollment UI — or a manual one-off script — populates them).
