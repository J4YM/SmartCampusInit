# Registrar Module — Grades Schema + Remaining Class Schedule Wiring

## Context

The Registrar module (`packages/registrar_module`, wired via
`lib/data/registrar_repository.dart` and
`lib/ui/registrar_connected_page.dart`) was audited tab-by-tab for what's
still on mock data. Overview, Student Records, and (as of the just-merged
`2026-09-10-student-portal-db-wiring` plan) most of Class Schedule are real.
Two gaps remain that this spec closes:

1. **Grades** — 100% `RegistrarMockData`. No `grades`/`grade_records` table
   exists anywhere in `supabase/*.sql`. This is the biggest remaining gap.
2. **Class Schedule's stand-in fields** — Education Level, Year Level, and
   Section are visually present but disabled (`_NotYetWiredField` in
   `class_schedule_view.dart`), with new class sections always defaulting
   to whichever `sections` row sorts first alphabetically
   (`RegistrarRepository.fetchDefaultSection()`). School Year/Term aren't
   form fields either — derived/hardcoded in `registrar_connected_page.dart`.

Explicitly out of scope (see Non-goals): RFID Notify tab persistence (belongs
with the separate Registrar-RFID-notice → IT Technician sub-project), and the
"mark student irregular" / move-enrollment-to-a-different-class_section flow
that `2026-09-04-irregular-students-schema-design.md` deferred as its own
Sub-project 3.

## Goals

- A real `grades` table, one row per student per `class_sections` offering,
  Registrar-entered, replacing `RegistrarMockData.getGradeRecords()`.
- Fix a real bug the new data will expose: `GradeRemark.fromValue()` has no
  "failing" case, so any grade below 75 (unrecognized remark string) falls
  through to `GradeRemark.outstanding`. Curated mock grades never triggered
  this; real registrar-entered grades will.
- Class Schedule's Section field becomes a real dropdown (mirroring the
  existing Subject/Teacher dropdown pattern), replacing the
  alphabetical-first stand-in. Year Level is derived from the selected
  section rather than a separate picker. School Year/Term become real form
  fields.

## Non-goals (explicitly out of scope)

- RFID Notify tab persistence — belongs with the Registrar-RFID-notice →
  IT Technician Dashboard sub-project (queued next after this one).
- The "mark student irregular" / move-enrollment flow —
  `2026-09-04-irregular-students-schema-design.md`'s deferred Sub-project 3.
  Still no UI, no repository method, after this spec.
- Senior High School support. `GradeRecordModel.educationLevel` has values
  `'College'`/`'Senior High School'`, but no table anywhere in the schema
  has an education-level column, and every seeded `sections` row
  (`supabase/seed_sections.sql`) is a College program. Real `grades` rows
  built by this spec always report `educationLevel: 'College'`. The
  Education Level pill in Class Schedule stays disabled — there is no real
  SHS data path to wire it to.
- Curriculum/requirements-table-driven Subject filtering (subjects scoped
  by program/year level) — explicitly deferred by the schema-design spec,
  unchanged here.

## Architecture

Same established pattern as every other wired feature in this codebase:
`RegistrarRepository` (in `lib/data/`) owns all Supabase access; the
presentation package (`registrar_module`) stays Supabase-agnostic and
receives data through the same `initial*`/callback props it already has for
Class Schedule; `RegistrarConnectedPage` is the wiring layer, gated on
`AppEnv.supabaseConfigured` with a mock-data fallback when unconfigured.

## Component 1: Grades

### Schema

```sql
-- supabase/add_grades_schema.sql

create table if not exists public.grades (
  id uuid primary key default gen_random_uuid(),
  class_section_id uuid not null references public.class_sections(id),
  student_id uuid not null references public.students(id),
  grade numeric(5,2) not null check (grade >= 0 and grade <= 100),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (student_id, class_section_id)
);

create index if not exists idx_grades_class_section on public.grades(class_section_id);
create index if not exists idx_grades_student on public.grades(student_id);

alter table public.grades enable row level security;

drop policy if exists "grades_registrar_all" on public.grades;
create policy "grades_registrar_all"
on public.grades for all
to authenticated
using (current_user_role() in ('Registrar'::app_role, 'Admin'::app_role))
with check (current_user_role() in ('Registrar'::app_role, 'Admin'::app_role));
```

No separate `school_year`/`term`/`section` columns — `class_section_id`
already carries subject, section, school year, and term (via the existing
`class_sections` table), so a grade's context is always available through a
join, with no duplicated/driftable data.

`for all` (not split into separate select/insert/update policies) matches
this table's actual access shape: only Registrar/Admin ever touch `grades`
in any way, unlike tables e.g. `good_moral_requests` where students/parents
need a narrower insert-only policy alongside staff's broader access.

### Repository

`RegistrarRepository` gains:

```dart
Future<List<GradeRecordModel>> fetchGradeRecords();

Future<void> saveGrade({
  required String studentId,
  required String classSectionId,
  required double grade,
});
```

`fetchGradeRecords()` selects `grades` joined through `class_sections` to
`subjects`/`sections`/`profiles` (student), building each `GradeRecordModel`
with:

- `gradeSection`: the joined `sections.name` (e.g. `"BSIT-3B"`) — already
  in the exact `"<program-code>-<year digit><section letter>"` shape
  `GradesView`'s own filter regex expects, so its existing
  program/year/section filtering keeps working unmodified.
- `educationLevel`: always `'College'` (see Non-goals).
- `semester`: the joined `class_sections.term`, normalized to `'1st'`/`'2nd'`
  by taking the leading digit (matching `GradesView`'s existing
  `_semester` toggle values) — if `term` doesn't start with `1` or `2`,
  default to `'1st'` rather than producing a value the filter can't match.
- `remark`: NOT read from the database — always recomputed from `grade` by
  `GradeRemark` (see the fix below), never trusted as stored state.

`saveGrade` is an upsert (`insert ... on conflict (student_id,
class_section_id) do update`) — a registrar re-saving an already-graded
student updates the existing row rather than violating the unique
constraint.

### Fixing `GradeRemark`'s missing failing case

`packages/registrar_module/lib/pages/dashboard/grades_view.dart`: add a
`failing` case, a red badge (matching this package's existing
`RegistrarColors` failure/error color, whatever it's already called
elsewhere in this file's siblings — check before inventing a new one), and
compute `remark` from the numeric grade using these thresholds (typical
Philippine school remark bands, matching the existing `passingRate`
threshold of `>= 75`):

```dart
static GradeRemark fromGrade(double grade) {
  if (grade < 75) return GradeRemark.failing;
  if (grade >= 90) return GradeRemark.outstanding;
  if (grade >= 85) return GradeRemark.verySatisfactory;
  return GradeRemark.satisfactory;
}
```

`GradeRemark.fromValue(String?)` (the JSON-string-based constructor) stays
for whatever locally still calls it, but `RegistrarRepository.fetchGradeRecords()`
uses `GradeRemark.fromGrade()` directly — it never has a remark string from
the database to parse, since remark isn't stored.

### Connected page wiring

`RegistrarConnectedPage`: load `fetchGradeRecords()` alongside the other
Class Schedule fetches already happening on init; wire `onGradeChanged`
(local optimistic update, matching how `GradesView` already handles
per-cell edits before "Save Changes") and `onSaveChanges` to call
`saveGrade` for every edited record, then reload. Follow this file's
existing `_toast()` success/failure convention (already used for Class
Schedule saves and Enroll Section) — a batch save of N grades reports
one toast, not N.

## Component 2: Class Schedule — real Section, School Year, Term

### Section dropdown

`RegistrarRepository` gains:

```dart
class SectionOption {
  const SectionOption({
    required this.id,
    required this.name,
    required this.yearLevel,
  });

  final String id;
  final String name;       // e.g. "BSIT-3B"
  final int yearLevel;     // e.g. 3
}

Future<List<SectionOption>> fetchSections();
```

`class_schedule_view.dart`: replace the `_NotYetWiredField`-wrapped Year
Level pill group and Section pill group with a single real
`_SectionDropdown` (same shape as the existing `_SubjectDropdown`/
`_TeacherDropdown`), using `SectionOption.name` as the display label. Year
Level's pill group is removed entirely — a caption or small subtitle under
the dropdown shows the selected section's derived year level (e.g. "Year
3"), read from `SectionOption.yearLevel`, not a separate interactive
control. Education Level stays exactly as it is today
(`_NotYetWiredField`-wrapped, disabled, with its existing caption) — no
real backing data exists for it (see Non-goals).

`RegistrarRepository.createClassSection(...)` already accepts `sectionId`
as a parameter (from the earlier plan) — `fetchDefaultSection()` and its
"first available section alphabetically" fallback path are removed
entirely, since the form now always supplies a real, registrar-selected
section id. If no section is selected when "Save Changes" is tapped, block
with a validation toast (matching `_handleSaveChanges`'s existing
silent-no-op-on-missing-fields pattern — same behavior class as the
Subject/Teacher/Room/Time fields already require).

### School Year / Term fields

Replace `registrar_connected_page.dart`'s `_currentSchoolYear()` helper and
hardcoded `_defaultTerm = '1st Semester'` with two real form fields in
`class_schedule_view.dart`:

- **School Year**: a `_LabeledTextField` (same widget already used for
  Room/Start Time/End Time), pre-filled with the current computed school
  year (keep `_currentSchoolYear()`'s logic as the pre-fill default, just
  make it editable rather than the only value ever sent) — free text is
  the honest minimum here, matching this form's existing Room/Time fields,
  since there's no school-year reference table to populate a dropdown from
  (same reasoning the original plan used for Room/Time).
- **Term**: a dropdown (same `DropdownButtonFormField` shape as
  `_SubjectDropdown`/`_TeacherDropdown`/`_SectionDropdown`, for visual
  consistency with this form's other real dropdowns) with the two options
  `'1st Semester'`/`'2nd Semester'` — matching `GradesView`'s semester
  toggle's actual values/casing exactly, to keep the two tabs' data
  consistent — replacing the hardcoded `_defaultTerm` constant.

## Testing

Signature-guard tests (this codebase's established repository-test
pattern) for `fetchGradeRecords`, `saveGrade`, and `fetchSections` — same
shape as `test/registrar_repository_class_sections_test.dart`. A model test
for `GradeRemark.fromGrade()` covering all four bands including the new
`failing` case (the bug this spec exists partly to fix) — the exact kind of
case a prior task's review would have caught if it existed before real
data reached this codepath.

## Migration / rollout order

1. `supabase/add_grades_schema.sql` — shown to the user for manual
   approval in the Supabase SQL Editor, never auto-run (this repo's
   established convention). Everything else in this spec compiles and
   tests against a fake Supabase URL without the migration having run yet;
   only live Grades tab usage is blocked until it has.
2. Grades repository + connected-page wiring + `GradeRemark` fix.
3. Class Schedule's Section dropdown + School Year/Term fields (independent
   of Grades — either order works, but Grades is listed first since it's
   the larger, schema-carrying change).
