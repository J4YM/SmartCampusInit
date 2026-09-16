# Schedule Import Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the schema and the pure parsing/matching/conflict-detection
engine that reads the school's Classes+Professor list, Confirmation of
Faculty Loading (CFL), and Room Schedule `.xlsx` exports and turns them
into a reconciled set of class offerings and meetings — the backend this
spec's UI (a separate, later plan) will be built on.

**Architecture:** Three layers, split so the hard, error-prone parsing
logic is pure Dart and fully unit-testable without Supabase: (1) plain
data models + format detection + the three per-format parsers in
`lib/data/schedule_import/`, producing `List<ScheduleImportRow>` from raw
`.xlsx` bytes with zero database dependency; (2) pure conflict-detection
and unit→hours validation, also in `lib/data/schedule_import/`, operating
purely on already-parsed rows; (3) `ScheduleImportRepository` in
`lib/data/`, the only layer that touches Supabase — resolving parsed rows
against `subjects`/`sections`/`profiles`/`room_aliases`/`program_aliases`
and committing the result. This plan does not build the review-screen UI
or the new Scheduling Officer role/dashboard — those are separate,
later plans that consume this one's repository.

**Tech Stack:** Flutter/Dart, Supabase, and a small hand-rolled `.xlsx`
reader (`lib/data/schedule_import/xlsx_reader.dart`, Task 2) built
directly on `archive` and `xml` — NOT any third-party Excel-reading
package. Three were checked and all failed for structural reasons
specific to this repo: `excel` needs `archive ^3.6.1`, which conflicts
with this repo's existing `docx_creator ^1.3.2` (needs `archive
^4.0.9+`), and `excel`'s own code doesn't compile against `archive`
4.x's API either, so no override direction works; `excel_plus` (an
API-identical fork) resolves the `archive` conflict but requires `xml
^7.0.1` and declares `sdk: ^3.11.4` on every published version back to
0.0.1 — both incompatible with this repo's Netlify build, which is
pinned to Dart 3.5.4 and a checked-in `xml: 6.5.0` override; and
`spreadsheet_decoder` has the exact same `archive ^3.6.1` conflict as
`excel`. `archive` (already resolves to `4.0.9`, satisfying
`docx_creator`) and `xml` (already pinned `6.5.0`) are both already
fully proven across every build target this repo has, including
Netlify — so a minimal reader built only on them adds zero new
dependency-resolution surface. This also simplifies every downstream
task: a cell is a plain `String?`, not a `CellValue` sealed-class
wrapper, and every parser's tests are plain Dart list literals.

**Spec:** `docs/superpowers/specs/2026-09-16-registrar-batch-schedule-import-design.md`

## Global Constraints

- SQL migrations are shown to the user for manual approval in the
  Supabase SQL Editor — **never auto-run**. This is a hard, repo-wide
  rule.
- 1 lecture unit = 1 hour/week; 1 laboratory unit = 3 hours/week; a
  subject with no lecture/lab split maps units 1:1 to hours. (Spec
  Component 3a — verified directly against every sample row during
  brainstorming.)
- Times in every source format are a 12-hour clock with **no AM/PM
  marker**. Verified against every sample: raw hour `12` is always noon,
  raw hours `1`-`6` are always PM, raw hours `7`-`11` are always AM — no
  class in any sample runs 1-6 AM or 7-11 PM. Each range endpoint
  resolves independently; no cross-referencing against its pair is
  needed.
- Day columns/values are always one of `M`, `T`, `W`, `TH`, `F`, `S`.
- `class_section_meetings.component` is `'Lecture'`, `'Laboratory'`, or
  `null` (no split) — never any other string.
- No task in this plan invents room/day/time data — every meeting this
  engine produces traces back to an actual cell in an uploaded file.

---

## File Structure

- Create: `supabase/add_class_section_meetings_schema.sql`,
  `supabase/add_room_aliases_schema.sql`,
  `supabase/add_program_aliases_schema.sql`
- Create: `lib/data/schedule_import/schedule_import_row.dart` — models
  (`ScheduleComponent`, `ScheduleImportRow`, `ScheduleFileFormat`)
- Create: `lib/data/schedule_import/xlsx_reader.dart` — the hand-rolled
  `.xlsx` byte reader (see Tech Stack above), producing plain
  `List<List<String?>>` rows
- Create: `lib/data/schedule_import/schedule_time_parsing.dart` — the
  12-hour-to-24-hour conversion and time-range extraction helpers, shared
  by every parser
- Create: `lib/data/schedule_import/schedule_file_parser.dart` — format
  detection + the three parsers, all operating on `List<List<String?>>`
- Create: `lib/data/schedule_import/schedule_conflict_detector.dart` —
  unit→hours validation + overlap/disagreement conflict detection
- Create: `lib/data/schedule_import_repository.dart` — Supabase-facing
  matching + commit
- Create: `test/xlsx_reader_test.dart`,
  `test/schedule_import_row_test.dart`,
  `test/schedule_time_parsing_test.dart`,
  `test/schedule_file_parser_classes_professor_test.dart`,
  `test/schedule_file_parser_cfl_test.dart`,
  `test/schedule_file_parser_room_schedule_test.dart`,
  `test/schedule_conflict_detector_test.dart`,
  `test/schedule_import_repository_test.dart`
- Modify: `pubspec.yaml` (add `archive: ^4.0.9` and `xml: ^6.5.0` under
  `dependencies:` — both already resolve to these exact versions
  transitively via `docx_creator`; adding them explicitly just makes
  this feature's direct use of them clear and protects against a future
  `docx_creator` removal silently breaking this feature's build)

---

### Task 1: Schema — class_section_meetings, room_aliases, program_aliases

**Files:**
- Create: `supabase/add_class_section_meetings_schema.sql`
- Create: `supabase/add_room_aliases_schema.sql`
- Create: `supabase/add_program_aliases_schema.sql`

**Interfaces:**
- Produces: the `class_section_meetings`, `room_aliases`,
  `program_aliases` tables every later task in this plan reads/writes.

This task is SQL-only — no Dart code, no live DB access needed (matches
this repo's established pattern for schema-only tasks). Present the SQL
to the user for manual approval; do not run it.

- [ ] **Step 1: Write `supabase/add_class_section_meetings_schema.sql`**

```sql
-- supabase/add_class_section_meetings_schema.sql
--
-- class_sections today assumes one room + one day-set + one time range
-- per offering. Real school schedule data needs multiple meetings per
-- offering (a Lecture row and a Laboratory row, each with its own
-- room/day/time; a single component can meet on two different days at
-- two different times). This table carries that per-meeting detail;
-- class_sections.room/schedule_days/start_time/end_time stay as they
-- are (a compatibility shim for the existing one-row-at-a-time manual
-- entry form) and are not touched by this migration.
--
-- Run in Supabase SQL Editor. Idempotent: safe to re-run.

create table if not exists public.class_section_meetings (
  id uuid primary key default gen_random_uuid(),
  class_section_id uuid not null references public.class_sections(id) on delete cascade,
  component text check (component in ('Lecture', 'Laboratory')),
  day text not null check (day in ('M','T','W','TH','F','S')),
  start_time time not null,
  end_time time not null,
  room text not null,
  created_at timestamptz not null default now()
);

create index if not exists idx_class_section_meetings_class_section
  on public.class_section_meetings(class_section_id);

alter table public.class_section_meetings enable row level security;

-- Catalog-like data (same reasoning as class_sections/subjects): visible
-- to anon and authenticated alike.
drop policy if exists "class_section_meetings_anon_select" on public.class_section_meetings;
create policy "class_section_meetings_anon_select"
on public.class_section_meetings for select
to anon
using (true);

drop policy if exists "class_section_meetings_authenticated_select" on public.class_section_meetings;
create policy "class_section_meetings_authenticated_select"
on public.class_section_meetings for select
to authenticated
using (true);

-- Write access: Registrar/Admin only for now (matches class_sections'
-- existing write shape). The Scheduling Officer role does not exist yet
-- in this plan — a later plan adds 'Scheduling_Officer'::app_role to
-- this policy alongside introducing that role.
drop policy if exists "class_section_meetings_write" on public.class_section_meetings;
create policy "class_section_meetings_write"
on public.class_section_meetings for all
to authenticated
using (current_user_role() in ('Registrar'::app_role, 'Admin'::app_role))
with check (current_user_role() in ('Registrar'::app_role, 'Admin'::app_role));
```

- [ ] **Step 1b: Add the `Placeholder` profile status value**

Placeholder professors (Task 8's `resolveProfessorId`) are stored as a
real `profiles` row with `status: 'Placeholder'` — `profiles.status` is
the existing `approval_status` enum, so this new value must be added to
it first. `ALTER TYPE ... ADD VALUE` cannot run in the same transaction
as its first use (same constraint `add_it_technician_schema.sql` already
documents for `app_role`), so this is its own statement, appended to the
end of `supabase/add_class_section_meetings_schema.sql` (no need for a
fourth separate file):

```sql
-- Appended to the end of add_class_section_meetings_schema.sql.
-- Placeholder professors (e.g. "New IT Faculty 2") get a real profiles
-- row with this status rather than 'approved'/'pending' — see
-- lib/data/schedule_import_repository.dart's resolveProfessorId.
alter type public.approval_status add value if not exists 'Placeholder';
```

- [ ] **Step 2: Write `supabase/add_room_aliases_schema.sql`**

```sql
-- supabase/add_room_aliases_schema.sql
--
-- Room names are inconsistent across the school's own export formats
-- (e.g. "COMPUTER LABORATORY 2" / "Comlab2" / "ComLab 1" / "RM 202") —
-- similar-looking strings can be genuinely different rooms ("ComLab 1"
-- vs "ComLab 3"), so this is a maintained lookup, not fuzzy matching.
--
-- Run in Supabase SQL Editor. Idempotent: safe to re-run.

create table if not exists public.room_aliases (
  id uuid primary key default gen_random_uuid(),
  alias text not null unique,
  canonical_room text not null,
  created_at timestamptz not null default now()
);

alter table public.room_aliases enable row level security;

drop policy if exists "room_aliases_select" on public.room_aliases;
create policy "room_aliases_select"
on public.room_aliases for select
to authenticated
using (true);

drop policy if exists "room_aliases_write" on public.room_aliases;
create policy "room_aliases_write"
on public.room_aliases for all
to authenticated
using (current_user_role() in ('Registrar'::app_role, 'Admin'::app_role))
with check (current_user_role() in ('Registrar'::app_role, 'Admin'::app_role));
```

- [ ] **Step 3: Write `supabase/add_program_aliases_schema.sql`**

```sql
-- supabase/add_program_aliases_schema.sql
--
-- Same problem as room_aliases, for program abbreviations the school's
-- exports use ("BSIT", "BCT") against subjects.program/sections.program's
-- full names ("BS Information Technology").
--
-- Run in Supabase SQL Editor. Idempotent: safe to re-run.

create table if not exists public.program_aliases (
  id uuid primary key default gen_random_uuid(),
  alias text not null unique,
  canonical_program text not null,
  created_at timestamptz not null default now()
);

alter table public.program_aliases enable row level security;

drop policy if exists "program_aliases_select" on public.program_aliases;
create policy "program_aliases_select"
on public.program_aliases for select
to authenticated
using (true);

drop policy if exists "program_aliases_write" on public.program_aliases;
create policy "program_aliases_write"
on public.program_aliases for all
to authenticated
using (current_user_role() in ('Registrar'::app_role, 'Admin'::app_role))
with check (current_user_role() in ('Registrar'::app_role, 'Admin'::app_role));
```

- [ ] **Step 4: Present the three files to the user for manual approval**

Show all three files' contents. Do not run them yourself — the user
copies them into the Supabase SQL Editor. Confirm with the user that all
three ran with no errors before moving to Task 2.

- [ ] **Step 5: Commit**

```bash
git add supabase/add_class_section_meetings_schema.sql supabase/add_room_aliases_schema.sql supabase/add_program_aliases_schema.sql
git commit -m "feat: add class_section_meetings, room_aliases, program_aliases schema"
```

---

### Task 2: Models, the .xlsx reader, time parsing, and format detection

**Files:**
- Create: `lib/data/schedule_import/schedule_import_row.dart`
- Create: `lib/data/schedule_import/xlsx_reader.dart`
- Create: `lib/data/schedule_import/schedule_time_parsing.dart`
- Create: `lib/data/schedule_import/schedule_file_parser.dart` (format
  detection only in this task — the three parsers are Tasks 3-5)
- Test: `test/schedule_import_row_test.dart`
- Test: `test/xlsx_reader_test.dart`
- Test: `test/schedule_time_parsing_test.dart`
- Modify: `pubspec.yaml`

**Interfaces:**
- Produces: `ScheduleComponent` enum (`lecture`, `laboratory`);
  `ScheduleImportRow` (fields: `subjectTitle` (String, required),
  `subjectCode` (String?), `component` (ScheduleComponent?), `section`
  (String?), `professorName` (String?), `instructorId` (String?), `room`
  (String?), `day` (String?), `startTime` (String? — `"HH:MM"` 24h),
  `endTime` (String? — `"HH:MM"` 24h), `units` (double?)); `ScheduleFileFormat`
  enum (`classesAndProfessorList`, `facultyLoading`, `roomSchedule`,
  `classSchedule`, `unknown`); `List<List<String?>>
  readFirstSheetRows(Uint8List xlsxBytes)`; `String to24Hour(String
  raw12h)`; `List<({String start, String end})>
  extractTimeRanges(String cellText)`; `ScheduleFileFormat
  detectScheduleFileFormat(List<List<String?>> rows)`.

- [ ] **Step 1: Add the `archive` and `xml` dependencies**

In `pubspec.yaml`, under `dependencies:`, add (NOT any Excel-reading
package — see this plan's Tech Stack section for why `excel`,
`excel_plus`, and `spreadsheet_decoder` were all checked and rejected;
`archive` and `xml` are the packages a hand-rolled `.xlsx` reader is
built on, and both already resolve to these exact versions transitively
via `docx_creator` today, so this only makes an existing transitive
dependency explicit — it does not change what actually gets resolved):

```yaml
  archive: ^4.0.9
  xml: ^6.5.0
```

Run: `flutter pub get`
Expected: resolves cleanly, `pubspec.lock` updated, `archive` still at
4.0.9 and `xml` still at 6.5.0 (unchanged from before this edit — if
either version changes, stop and report it, since that would mean this
task altered a version something else in the app depends on).

- [ ] **Step 2: Write the failing test for `ScheduleImportRow`**

```dart
// test/schedule_import_row_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:capstone_dashboard/data/schedule_import/schedule_import_row.dart';

void main() {
  test('ScheduleImportRow holds all fields with correct nullability', () {
    const row = ScheduleImportRow(
      subjectTitle: 'Human Computer Interaction',
      subjectCode: 'CITE1010',
      component: ScheduleComponent.lecture,
      section: 'BSIT 3A',
      professorName: 'Ronald Christian Pallorina',
      instructorId: '02000324231',
      room: 'ComLab 1',
      day: 'T',
      startTime: '07:00',
      endTime: '09:00',
      units: 2,
    );
    expect(row.subjectTitle, 'Human Computer Interaction');
    expect(row.component, ScheduleComponent.lecture);
    expect(row.startTime, '07:00');
  });

  test('ScheduleImportRow allows every optional field to be null', () {
    const row = ScheduleImportRow(subjectTitle: 'Great Books');
    expect(row.subjectCode, isNull);
    expect(row.component, isNull);
    expect(row.section, isNull);
    expect(row.professorName, isNull);
    expect(row.instructorId, isNull);
    expect(row.room, isNull);
    expect(row.day, isNull);
    expect(row.startTime, isNull);
    expect(row.endTime, isNull);
    expect(row.units, isNull);
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `flutter test test/schedule_import_row_test.dart`
Expected: FAIL — `schedule_import_row.dart` doesn't exist yet.

- [ ] **Step 4: Write `lib/data/schedule_import/schedule_import_row.dart`**

```dart
/// A subject/professor/room/day/time-range component (0 or 1) parsed
/// from one of the school's export formats. Roster-only rows (from the
/// Classes+Professor list) leave [component]/[section]/[room]/[day]/
/// [startTime]/[endTime] null — that format carries no meeting detail at
/// all, only which subject a professor is assigned to.
enum ScheduleComponent { lecture, laboratory }

class ScheduleImportRow {
  const ScheduleImportRow({
    required this.subjectTitle,
    this.subjectCode,
    this.component,
    this.section,
    this.professorName,
    this.instructorId,
    this.room,
    this.day,
    this.startTime,
    this.endTime,
    this.units,
  });

  /// Always present — every format names the subject by its title.
  final String subjectTitle;

  /// Only the Classes+Professor list carries a course code. CFL/Room
  /// Schedule identify subjects by title only.
  final String? subjectCode;

  /// Null when the subject has no lecture/laboratory split.
  final ScheduleComponent? component;

  /// Section label as it appears in the source file (e.g. "BSIT 2A") —
  /// not yet normalized against `sections.name`.
  final String? section;

  /// Full name as it appears in CFL/Room Schedule (e.g.
  /// "Ronald Christian Pallorina"). Null for Classes+Professor list rows,
  /// which identify the professor by [instructorId] instead.
  final String? professorName;

  /// Only the Classes+Professor list carries this.
  final String? instructorId;

  /// Room name as it appears in the source file — not yet resolved
  /// against `room_aliases`.
  final String? room;

  /// One of 'M', 'T', 'W', 'TH', 'F', 'S'. Null for a roster-only row.
  final String? day;

  /// 24-hour "HH:MM". Null for a roster-only row.
  final String? startTime;

  /// 24-hour "HH:MM". Null for a roster-only row.
  final String? endTime;

  /// Course unit count, when the source row carries one.
  final double? units;
}

/// Which of the school's export formats a file matches.
enum ScheduleFileFormat {
  classesAndProfessorList,
  facultyLoading,
  roomSchedule,
  classSchedule,
  unknown,
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/schedule_import_row_test.dart`
Expected: PASS

- [ ] **Step 6: Write the failing test for time parsing**

```dart
// test/schedule_time_parsing_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:capstone_dashboard/data/schedule_import/schedule_time_parsing.dart';

void main() {
  group('to24Hour', () {
    test('hour 12 stays 12 (noon)', () {
      expect(to24Hour('12:00'), '12:00');
      expect(to24Hour('12:30'), '12:30');
    });
    test('hours 1-6 become PM (add 12)', () {
      expect(to24Hour('1:00'), '13:00');
      expect(to24Hour('2:30'), '14:30');
      expect(to24Hour('6:00'), '18:00');
    });
    test('hours 7-11 stay AM (unchanged)', () {
      expect(to24Hour('7:00'), '07:00');
      expect(to24Hour('9:00'), '09:00');
      expect(to24Hour('11:30'), '11:30');
    });
    test('pads single-digit hours with a leading zero', () {
      expect(to24Hour('7:00'), '07:00');
    });
  });

  group('extractTimeRanges', () {
    test('extracts a single plain range', () {
      final ranges = extractTimeRanges('7:00-9:00');
      expect(ranges, [(start: '07:00', end: '09:00')]);
    });
    test('extracts a range with spaces around the dash', () {
      final ranges = extractTimeRanges('7:00 - 9:00');
      expect(ranges, [(start: '07:00', end: '09:00')]);
    });
    test('extracts two ranges separated by a slash', () {
      final ranges = extractTimeRanges('12:00 - 2:00 / 5:00 - 6:00');
      expect(ranges, [
        (start: '12:00', end: '14:00'),
        (start: '17:00', end: '18:00'),
      ]);
    });
    test('extracts two ranges even without spaces around the slash', () {
      final ranges = extractTimeRanges('11:00-12:00/1:00-2:00');
      expect(ranges, [
        (start: '11:00', end: '12:00'),
        (start: '13:00', end: '14:00'),
      ]);
    });
    test('returns an empty list for a cell with no recognizable range', () {
      // Real data has typos like this ("10:00:11:30" instead of
      // "10:00-11:30") — must not throw, must not silently invent a
      // guess. The unit-hours conflict check (Task 6) catches the
      // resulting missing meeting instead.
      expect(extractTimeRanges('10:00:11:30'), isEmpty);
    });
    test('returns an empty list for a blank cell', () {
      expect(extractTimeRanges(''), isEmpty);
      expect(extractTimeRanges('   '), isEmpty);
    });
  });
}
```

- [ ] **Step 7: Run test to verify it fails**

Run: `flutter test test/schedule_time_parsing_test.dart`
Expected: FAIL — `schedule_time_parsing.dart` doesn't exist yet.

- [ ] **Step 8: Write `lib/data/schedule_import/schedule_time_parsing.dart`**

```dart
/// Converts a raw "H:MM" time (the 12-hour clock every source format
/// uses, with no AM/PM marker) into 24-hour "HH:MM".
///
/// Verified against every sample schedule reviewed for this feature:
/// raw hour 12 is always noon, raw hours 1-6 are always PM (no class
/// starts 1-6 AM), and raw hours 7-11 are always AM (no class runs
/// 7-11 PM). Each endpoint of a range resolves independently — no
/// cross-referencing against its pair is needed.
String to24Hour(String raw) {
  final parts = raw.trim().split(':');
  final hour = int.parse(parts[0]);
  final minute = parts[1].padLeft(2, '0');
  final hour24 = hour == 12
      ? 12
      : (hour >= 1 && hour <= 6 ? hour + 12 : hour);
  return '${hour24.toString().padLeft(2, '0')}:$minute';
}

final _rangePattern = RegExp(r'(\d{1,2}:\d{2})\s*-\s*(\d{1,2}:\d{2})');

/// Extracts every "H:MM-H:MM" time range out of [cellText], converting
/// each endpoint to 24-hour time. A cell can hold more than one range
/// separated by "/" (two meeting blocks on the same day) — each becomes
/// its own entry, in the order they appear. A cell with no recognizable
/// range (blank, or a typo like "10:00:11:30" seen in real source data)
/// returns an empty list rather than throwing or guessing.
List<({String start, String end})> extractTimeRanges(String cellText) {
  return _rangePattern
      .allMatches(cellText)
      .map((m) => (start: to24Hour(m.group(1)!), end: to24Hour(m.group(2)!)))
      .toList();
}
```

- [ ] **Step 9: Run test to verify it passes**

Run: `flutter test test/schedule_time_parsing_test.dart`
Expected: PASS

- [ ] **Step 10: Write the failing test for the `.xlsx` reader**

```dart
// test/xlsx_reader_test.dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:capstone_dashboard/data/schedule_import/xlsx_reader.dart';

Uint8List _buildMinimalXlsx({
  required String sheetXml,
  String? sharedStringsXml,
}) {
  final archive = Archive();
  if (sharedStringsXml != null) {
    archive.addFile(ArchiveFile.bytes('xl/sharedStrings.xml', utf8.encode(sharedStringsXml)));
  }
  archive.addFile(ArchiveFile.bytes('xl/worksheets/sheet1.xml', utf8.encode(sheetXml)));
  return ZipEncoder().encodeBytes(archive);
}

const _sharedStringsXml = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="2" uniqueCount="2">
  <si><t>Hello</t></si>
  <si><t>World</t></si>
</sst>
''';

void main() {
  test('reads shared strings, an inline string, a plain cell, a blank cell, and a skipped row', () {
    final bytes = _buildMinimalXlsx(
      sharedStringsXml: _sharedStringsXml,
      sheetXml: '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <sheetData>
    <row r="1">
      <c r="A1" t="s"><v>0</v></c>
      <c r="B1" t="s"><v>1</v></c>
    </row>
    <row r="3">
      <c r="A3" t="inlineStr"><is><t>Direct</t></is></c>
      <c r="C3"><v>42</v></c>
    </row>
  </sheetData>
</worksheet>
''',
    );

    final rows = readFirstSheetRows(bytes);
    expect(rows, [
      ['Hello', 'World', null],
      [null, null, null],
      ['Direct', null, '42'],
    ]);
  });

  test('decodes multi-letter column references (AA is column index 26)', () {
    final bytes = _buildMinimalXlsx(
      sharedStringsXml: '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="1" uniqueCount="1">
  <si><t>Far column</t></si>
</sst>
''',
      sheetXml: '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <sheetData>
    <row r="1">
      <c r="AA1" t="s"><v>0</v></c>
    </row>
  </sheetData>
</worksheet>
''',
    );

    final rows = readFirstSheetRows(bytes);
    expect(rows.single, hasLength(27));
    expect(rows.single[26], 'Far column');
  });

  test('returns an empty list when there is no worksheet in the archive', () {
    final archive = Archive();
    archive.addFile(ArchiveFile.bytes('xl/other.xml', utf8.encode('<x/>')));
    final bytes = ZipEncoder().encodeBytes(archive);
    expect(readFirstSheetRows(bytes), isEmpty);
  });

  test('works with no sharedStrings.xml at all (only inline/numeric cells)', () {
    final bytes = _buildMinimalXlsx(sheetXml: '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <sheetData>
    <row r="1">
      <c r="A1"><v>7</v></c>
    </row>
  </sheetData>
</worksheet>
''');
    expect(readFirstSheetRows(bytes), [['7']]);
  });
}
```

- [ ] **Step 11: Run test to verify it fails**

Run: `flutter test test/xlsx_reader_test.dart`
Expected: FAIL — `xlsx_reader.dart` doesn't exist yet.

- [ ] **Step 12: Write `lib/data/schedule_import/xlsx_reader.dart`**

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// Decodes an Excel-style column reference ("A" -> 0, "B" -> 1, ...,
/// "Z" -> 25, "AA" -> 26, "AB" -> 27, ...) into a zero-based column
/// index.
int _columnLettersToIndex(String letters) {
  var index = 0;
  for (var i = 0; i < letters.length; i++) {
    index = index * 26 + (letters.codeUnitAt(i) - 'A'.codeUnitAt(0) + 1);
  }
  return index - 1;
}

/// Splits a cell reference like "B7" or "AA123" into its column letters
/// ("B"/"AA") and row number (7/123).
({String columnLetters, int rowNumber}) _splitCellRef(String cellRef) {
  final match = RegExp(r'^([A-Z]+)(\d+)$').firstMatch(cellRef);
  if (match == null) {
    throw FormatException('Not a valid cell reference: $cellRef');
  }
  return (columnLetters: match.group(1)!, rowNumber: int.parse(match.group(2)!));
}

/// Returns the text content of the first child element named [childName]
/// under [parent], or null if there isn't one. A small manual helper
/// rather than `.firstOrNull` on the `findElements` iterable, to avoid
/// depending on an extension method that may need a separate import.
String? _firstChildText(XmlElement parent, String childName) {
  for (final child in parent.findElements(childName)) {
    return child.innerText;
  }
  return null;
}

/// Parses xl/sharedStrings.xml's <si> entries into an ordered list of
/// plain strings, in the order Excel indexes them (a cell with t="s"
/// references these by position). Each <si> either holds one direct <t>
/// or several <r><t> "rich text runs" to concatenate — both forms are
/// handled. Returns an empty list when there is no shared strings part
/// at all (a sheet with only inline/numeric cells doesn't need one).
List<String> _parseSharedStrings(String? xmlContent) {
  if (xmlContent == null) return [];
  final document = XmlDocument.parse(xmlContent);
  final result = <String>[];
  for (final si in document.findAllElements('si')) {
    final direct = _firstChildText(si, 't');
    if (direct != null) {
      result.add(direct);
      continue;
    }
    final buffer = StringBuffer();
    for (final run in si.findElements('r')) {
      buffer.write(_firstChildText(run, 't') ?? '');
    }
    result.add(buffer.toString());
  }
  return result;
}

/// Parses one worksheet XML's <row>/<c> structure into a dense
/// List<List<String?>>, resolving shared-string indices via
/// [sharedStrings]. XLSX omits blank cells from the XML entirely, so
/// column positions are computed from each cell's own `r` attribute, not
/// assumed sequential — a blank cell becomes null, and rows are padded
/// to the widest row seen.
List<List<String?>> _parseWorksheetRows(String sheetXmlContent, List<String> sharedStrings) {
  final document = XmlDocument.parse(sheetXmlContent);
  final rows = <int, Map<int, String?>>{};
  var maxColumn = -1;

  for (final rowElement in document.findAllElements('row')) {
    final rowNumberAttr = rowElement.getAttribute('r');
    if (rowNumberAttr == null) continue;
    final rowIndex = int.parse(rowNumberAttr) - 1;
    final rowCells = rows.putIfAbsent(rowIndex, () => {});

    for (final cellElement in rowElement.findElements('c')) {
      final cellRefAttr = cellElement.getAttribute('r');
      if (cellRefAttr == null) continue;
      final ref = _splitCellRef(cellRefAttr);
      final columnIndex = _columnLettersToIndex(ref.columnLetters);
      if (columnIndex > maxColumn) maxColumn = columnIndex;

      final type = cellElement.getAttribute('t');
      String? value;
      if (type == 's') {
        final raw = _firstChildText(cellElement, 'v');
        final index = raw == null ? null : int.tryParse(raw);
        value = (index != null && index >= 0 && index < sharedStrings.length)
            ? sharedStrings[index]
            : null;
      } else if (type == 'inlineStr') {
        String? inlineText;
        for (final isElement in cellElement.findElements('is')) {
          inlineText = _firstChildText(isElement, 't');
          break;
        }
        value = inlineText;
      } else {
        value = _firstChildText(cellElement, 'v');
      }
      rowCells[columnIndex] = value;
    }
  }

  if (rows.isEmpty) return [];
  final maxRow = rows.keys.reduce((a, b) => a > b ? a : b);
  return List.generate(maxRow + 1, (r) {
    final rowCells = rows[r] ?? const {};
    return List.generate(maxColumn + 1, (c) => rowCells[c]);
  });
}

/// Reads the first worksheet of an .xlsx file's raw bytes into a dense
/// List<List<String?>> — one entry per cell, in row-major order, null
/// for blank cells.
///
/// This is a minimal, purpose-built reader (not a general-purpose Excel
/// library) using only `archive` and `xml` — both already depended on by
/// this repo (for docx_creator's DOCX writing) at versions already
/// proven compatible with every build target this repo has, including
/// Netlify's pinned old Dart SDK. See this plan's Tech Stack section for
/// why no third-party Excel-reading package could be used instead. Reads
/// only the FIRST worksheet found in the zip's natural file order —
/// every format this plan parses is single-sheet.
List<List<String?>> readFirstSheetRows(Uint8List xlsxBytes) {
  final archive = ZipDecoder().decodeBytes(xlsxBytes);

  String? sharedStringsXml;
  ArchiveFile? firstSheetFile;
  final sheetFilePattern = RegExp(r'^xl/worksheets/sheet\d+\.xml$');
  for (final file in archive.files) {
    if (file.name == 'xl/sharedStrings.xml') {
      sharedStringsXml = utf8.decode(file.content);
    } else if (firstSheetFile == null && sheetFilePattern.hasMatch(file.name)) {
      firstSheetFile = file;
    }
  }
  if (firstSheetFile == null) return [];

  final sharedStrings = _parseSharedStrings(sharedStringsXml);
  final sheetXml = utf8.decode(firstSheetFile.content);
  return _parseWorksheetRows(sheetXml, sharedStrings);
}
```

- [ ] **Step 13: Run test to verify it passes**

Run: `flutter test test/xlsx_reader_test.dart`
Expected: PASS (all 4 tests)

- [ ] **Step 14: Write the failing test for format detection**

```dart
// Add to test/schedule_file_parser_classes_professor_test.dart — created
// fresh in Task 3, but format-detection tests belong here since they
// cover all four formats. Create the file now with just this content;
// Task 3 appends the parser tests to it. Rows are plain
// List<List<String?>> literals — the exact shape readFirstSheetRows
// (Step 12 above) produces — so no zip/xlsx construction is needed to
// test detection or parsing logic; only xlsx_reader_test.dart (Step 10
// above) needs to build a real xlsx byte blob.
import 'package:flutter_test/flutter_test.dart';
import 'package:capstone_dashboard/data/schedule_import/schedule_file_parser.dart';
import 'package:capstone_dashboard/data/schedule_import/schedule_import_row.dart';

void main() {
  group('detectScheduleFileFormat', () {
    test('detects a Classes+Professor list by its header row', () {
      final List<List<String?>> rows = [
        ['Campus', 'Class No', 'Career', 'Course ID', 'Course Code',
          'Description', 'Course Unit', 'Instructor ID'],
        ['Baliuag', '9612', 'BCT', '001681', 'GEDC1010', 'Art Appreciation',
          '3', '02000324231'],
      ];
      expect(detectScheduleFileFormat(rows),
          ScheduleFileFormat.classesAndProfessorList);
    });

    test('detects a Confirmation of Faculty Loading file', () {
      final List<List<String?>> rows = [
        ['STI COLLEGE BALIUAG'],
        ['Confirmation of Faculty Loading'],
        ['Instructor:', 'Ronald Christian Pallorina'],
      ];
      expect(detectScheduleFileFormat(rows), ScheduleFileFormat.facultyLoading);
    });

    test('detects a Room Schedule file', () {
      final List<List<String?>> rows = [
        ['ROOM SCHEDULE'],
        ['COMPUTER LABORATORY 2'],
      ];
      expect(detectScheduleFileFormat(rows), ScheduleFileFormat.roomSchedule);
    });

    test('detects a Class Schedule file', () {
      final List<List<String?>> rows = [
        ['SCHEDULE OF CLASSES - 1ST SEMESTER A.Y. 2026-2027'],
      ];
      expect(detectScheduleFileFormat(rows), ScheduleFileFormat.classSchedule);
    });

    test('returns unknown for an unrecognized file', () {
      final List<List<String?>> rows = [
        ['Just', 'Some', 'Random', 'Data'],
      ];
      expect(detectScheduleFileFormat(rows), ScheduleFileFormat.unknown);
    });
  });
}
```

- [ ] **Step 15: Run test to verify it fails**

Run: `flutter test test/schedule_file_parser_classes_professor_test.dart`
Expected: FAIL — `schedule_file_parser.dart` doesn't exist yet.

- [ ] **Step 16: Write `lib/data/schedule_import/schedule_file_parser.dart` (detection only)**

```dart
import 'schedule_import_row.dart';

/// Reads every cell's text across every row of [rows], upper-cased, for
/// signature matching. Small inputs only (these are single-sheet
/// per-professor/per-room exports) — building one combined string is
/// simpler and fast enough than a cell-by-cell scan.
String _allCellsText(List<List<String?>> rows) {
  final buffer = StringBuffer();
  for (final row in rows) {
    for (final cell in row) {
      if (cell != null) buffer.write('$cell ');
    }
  }
  return buffer.toString().toUpperCase();
}

/// Determines which of the school's export formats [rows] (as produced
/// by [readFirstSheetRows]) matches, by checking for each format's
/// distinctive header text. Checked in this order because 'CLASS NO'
/// and 'INSTRUCTOR ID' are the most specific signature (both must be
/// present), while the others each match one unambiguous phrase.
ScheduleFileFormat detectScheduleFileFormat(List<List<String?>> rows) {
  final text = _allCellsText(rows);
  if (text.contains('CLASS NO') && text.contains('INSTRUCTOR ID')) {
    return ScheduleFileFormat.classesAndProfessorList;
  }
  if (text.contains('CONFIRMATION OF FACULTY LOADING')) {
    return ScheduleFileFormat.facultyLoading;
  }
  if (text.contains('ROOM SCHEDULE')) {
    return ScheduleFileFormat.roomSchedule;
  }
  if (text.contains('SCHEDULE OF CLASSES')) {
    return ScheduleFileFormat.classSchedule;
  }
  return ScheduleFileFormat.unknown;
}
```

- [ ] **Step 17: Run test to verify it passes**

Run: `flutter test test/schedule_file_parser_classes_professor_test.dart`
Expected: PASS (all 5 detection tests)

- [ ] **Step 18: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/data/schedule_import/ test/schedule_import_row_test.dart test/xlsx_reader_test.dart test/schedule_time_parsing_test.dart test/schedule_file_parser_classes_professor_test.dart
git commit -m "feat: add schedule import models, xlsx reader, time parsing, and format detection"
```

---

### Task 3: Classes+Professor list parser

**Files:**
- Modify: `lib/data/schedule_import/schedule_file_parser.dart`
- Modify: `test/schedule_file_parser_classes_professor_test.dart`

**Interfaces:**
- Consumes: `ScheduleImportRow`
- Produces: `List<ScheduleImportRow>
  parseClassesAndProfessorList(List<List<String?>> rows)`

The Classes+Professor list's real column order (confirmed from the
sample): `Campus, Class No, Career, Course ID, Course Code, Description,
Course Unit, Instructor ID, Last Name, First Name, Middle Name, Enrolled
Student, ...` (grade/date columns follow — ignored entirely, per spec
Non-goals). One row per class offering; each row becomes one
`ScheduleImportRow` with no component/section/room/day/time (this format
carries none of that). [rows] is exactly what `readFirstSheetRows`
(Task 2) produces — this and every parser take the already-decoded
sheet, never raw `.xlsx` bytes directly.

- [ ] **Step 1: Write the failing test**

Append to `test/schedule_file_parser_classes_professor_test.dart`:

```dart
  group('parseClassesAndProfessorList', () {
    test('parses subject, code, unit, instructor id, and professor name', () {
      final List<List<String?>> rows = [
        ['Campus', 'Class No', 'Career', 'Course ID', 'Course Code',
          'Description', 'Course Unit', 'Instructor ID', 'Last Name',
          'First Name', 'Middle Name', 'Enrolled Student'],
        ['Baliuag', '9612', 'BCT', '001681', 'GEDC1010', 'Art Appreciation',
          '3', '02000324231', 'PERALTA', 'MICHAELLA', 'P.', '37'],
        ['Baliuag', '9877', 'BCT', '002257', 'OJTC1003',
          'BSHM Practicum (600 hours)', '6', '02000429469', 'AQUINO',
          'MELISSA', 'LARA', '21'],
      ];
      final result = parseClassesAndProfessorList(rows);
      expect(result, hasLength(2));
      expect(result[0].subjectCode, 'GEDC1010');
      expect(result[0].subjectTitle, 'Art Appreciation');
      expect(result[0].units, 3);
      expect(result[0].instructorId, '02000324231');
      expect(result[0].professorName, 'PERALTA MICHAELLA P.');
      expect(result[0].component, isNull);
      expect(result[0].room, isNull);
      expect(result[0].day, isNull);
      expect(result[1].subjectCode, 'OJTC1003');
      expect(result[1].units, 6);
    });

    test('skips a row with a blank Course Code (a stray/blank source row)', () {
      final List<List<String?>> rows = [
        ['Campus', 'Class No', 'Career', 'Course ID', 'Course Code',
          'Description', 'Course Unit', 'Instructor ID', 'Last Name',
          'First Name', 'Middle Name', 'Enrolled Student'],
        ['Baliuag', null, null, null, null, null, null, null, null, null, null, null],
        ['Baliuag', '9612', 'BCT', '001681', 'GEDC1010', 'Art Appreciation',
          '3', '02000324231', 'PERALTA', 'MICHAELLA', 'P.', '37'],
      ];
      final result = parseClassesAndProfessorList(rows);
      expect(result, hasLength(1));
      expect(result[0].subjectCode, 'GEDC1010');
    });

    test('joins last/first/middle name with single spaces, tolerating a blank middle name', () {
      final List<List<String?>> rows = [
        ['Campus', 'Class No', 'Career', 'Course ID', 'Course Code',
          'Description', 'Course Unit', 'Instructor ID', 'Last Name',
          'First Name', 'Middle Name', 'Enrolled Student'],
        ['Baliuag', '9877', 'BCT', '002257', 'OJTC1003',
          'BSHM Practicum (600 hours)', '6', '02000429469', 'AQUINO',
          'MELISSA LARA', null, '21'],
      ];
      final result = parseClassesAndProfessorList(rows);
      expect(result[0].professorName, 'AQUINO MELISSA LARA');
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/schedule_file_parser_classes_professor_test.dart`
Expected: FAIL — `parseClassesAndProfessorList` doesn't exist yet.

- [ ] **Step 3: Write the implementation**

Append to `lib/data/schedule_import/schedule_file_parser.dart`:

```dart
/// Finds the column index whose header cell (row 0) case-insensitively
/// equals [header], or -1 if not found.
int _columnIndex(List<String?> headerRow, String header) {
  for (var i = 0; i < headerRow.length; i++) {
    final text = headerRow[i]?.trim();
    if (text != null && text.toUpperCase() == header.toUpperCase()) {
      return i;
    }
  }
  return -1;
}

String? _cellText(List<String?> row, int column) {
  if (column < 0 || column >= row.length) return null;
  final text = row[column]?.trim();
  return (text == null || text.isEmpty) ? null : text;
}

/// Parses a Classes+Professor list ("Course and Grade Monitoring"
/// report) into one [ScheduleImportRow] per class offering. This format
/// carries no room/day/time/section — only which subject each professor
/// is assigned to (the Registrar's roster).
List<ScheduleImportRow> parseClassesAndProfessorList(List<List<String?>> rows) {
  if (rows.isEmpty) return [];

  final header = rows.first;
  final codeCol = _columnIndex(header, 'Course Code');
  final titleCol = _columnIndex(header, 'Description');
  final unitCol = _columnIndex(header, 'Course Unit');
  final instructorIdCol = _columnIndex(header, 'Instructor ID');
  final lastNameCol = _columnIndex(header, 'Last Name');
  final firstNameCol = _columnIndex(header, 'First Name');
  final middleNameCol = _columnIndex(header, 'Middle Name');

  final result = <ScheduleImportRow>[];
  for (final row in rows.skip(1)) {
    final code = _cellText(row, codeCol);
    final title = _cellText(row, titleCol);
    if (code == null || title == null) continue; // blank/stray row

    final nameParts = [
      _cellText(row, lastNameCol),
      _cellText(row, firstNameCol),
      _cellText(row, middleNameCol),
    ].whereType<String>();

    result.add(ScheduleImportRow(
      subjectTitle: title,
      subjectCode: code,
      units: double.tryParse(_cellText(row, unitCol) ?? ''),
      instructorId: _cellText(row, instructorIdCol),
      professorName: nameParts.isEmpty ? null : nameParts.join(' '),
    ));
  }
  return result;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/schedule_file_parser_classes_professor_test.dart`
Expected: PASS (all 8 tests — 5 detection + 3 parser)

- [ ] **Step 5: Commit**

```bash
git add lib/data/schedule_import/schedule_file_parser.dart test/schedule_file_parser_classes_professor_test.dart
git commit -m "feat: parse the Classes+Professor list format"
```

---

### Task 4: Confirmation of Faculty Loading (CFL) parser

**Files:**
- Modify: `lib/data/schedule_import/schedule_file_parser.dart`
- Create: `test/schedule_file_parser_cfl_test.dart`

**Interfaces:**
- Consumes: `ScheduleImportRow`, `ScheduleComponent`, `extractTimeRanges`
- Produces: `List<ScheduleImportRow>
  parseFacultyLoading(List<List<String?>> rows)`

Real layout (confirmed from the sample): the professor's name is in a
cell reading `Instructor:` with the name in the next cell. Subject rows
alternate with a "Lecture"/"Laboratory (3 hours)" sub-row directly below
(the sub-row's first cell starts with whitespace-indented "Lecture" or
"Laboratory"); day columns are `M T W TH F S` in that order, each
followed later in the same logical row-group by `Room` and `Section`
columns (the sample splits these across two page-image halves, but in
the real `.xlsx` they are columns of one wide sheet). A subject with no
lecture/lab split (not present in the CFL sample, but the format allows
it per Room Schedule's sample, e.g. "Applied Business Tools in Tourism"
having explicit Lecture/Laboratory sub-rows always in that file — CFL
always splits, so this parser assumes every subject row is followed by
exactly one Lecture sub-row and one Laboratory sub-row, using an empty
day/time on whichever component doesn't meet that particular pattern of
the row it's tied to).

- [ ] **Step 1: Write the failing test**

```dart
// test/schedule_file_parser_cfl_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:capstone_dashboard/data/schedule_import/schedule_file_parser.dart';
import 'package:capstone_dashboard/data/schedule_import/schedule_import_row.dart';

void main() {
  group('parseFacultyLoading', () {
    // Columns: Subject, Units, M, T, W, TH, F, S, Room, Section
    test('parses a lecture+lab subject meeting on different days/rooms', () {
      final List<List<String?>> rows = [
        ['STI COLLEGE BALIUAG'],
        ['Confirmation of Faculty Loading'],
        ['Instructor:', 'Ronald Christian Pallorina'],
        <String?>[],
        ['SUBJECT', 'Units', 'M', 'T', 'W', 'TH', 'F', 'S', 'Room', 'Section'],
        ['Human Computer Interaction', null, null, null, null, null, null, null, null, 'BSIT 2A'],
        ['Lecture', '2', null, '7:00 - 9:00', null, null, null, null, 'LR 203', null],
        ['Laboratory (3 hours)', '1', null, null, null, '7:00 - 10:00', null, null, 'ComLab 1', null],
      ];
      final result = parseFacultyLoading(rows);
      expect(result, hasLength(2));

      final lecture = result.firstWhere((r) => r.component == ScheduleComponent.lecture);
      expect(lecture.subjectTitle, 'Human Computer Interaction');
      expect(lecture.professorName, 'Ronald Christian Pallorina');
      expect(lecture.units, 2);
      expect(lecture.day, 'T');
      expect(lecture.startTime, '07:00');
      expect(lecture.endTime, '09:00');
      expect(lecture.room, 'LR 203');
      expect(lecture.section, 'BSIT 2A');

      final lab = result.firstWhere((r) => r.component == ScheduleComponent.laboratory);
      expect(lab.day, 'TH');
      expect(lab.startTime, '07:00');
      expect(lab.endTime, '10:00');
      expect(lab.room, 'ComLab 1');
      expect(lab.section, 'BSIT 2A');
      expect(lab.units, 1);
    });

    test('expands a cell with two time ranges into two rows for the same component', () {
      final List<List<String?>> rows = [
        ['Confirmation of Faculty Loading'],
        ['Instructor:', 'Jayson Villafuerte'],
        ['SUBJECT', 'Units', 'M', 'T', 'W', 'TH', 'F', 'S', 'Room', 'Section'],
        ['Application Development and Emerging Technologies', null, null, null, null, null, null, null, null, 'BSIT 3A'],
        ['Lecture', '2', '11:00 - 12:00 / 1:00 - 2:00', null, null, null, null, null, 'LR 202', null],
        ['Laboratory (3 hours)', '1', null, null, null, null, null, null, 'ComLab 3', null],
      ];
      final result = parseFacultyLoading(rows);
      final lectures = result.where((r) => r.component == ScheduleComponent.lecture).toList();
      expect(lectures, hasLength(2));
      expect(lectures[0].day, 'M');
      expect(lectures[0].startTime, '11:00');
      expect(lectures[0].endTime, '12:00');
      expect(lectures[1].day, 'M');
      expect(lectures[1].startTime, '13:00');
      expect(lectures[1].endTime, '14:00');
    });

    test('a component cell with no time range produces no row for that component', () {
      final List<List<String?>> rows = [
        ['Confirmation of Faculty Loading'],
        ['Instructor:', 'Jayson Villafuerte'],
        ['SUBJECT', 'Units', 'M', 'T', 'W', 'TH', 'F', 'S', 'Room', 'Section'],
        ['Advanced Database System', null, null, null, null, null, null, null, null, 'BSIT 3A'],
        ['Lecture', '2', null, null, null, null, null, null, null, null],
        ['Laboratory (3 hours)', '1', '2:30 - 5:30', null, null, null, null, null, 'ComLab 1', null],
      ];
      final result = parseFacultyLoading(rows);
      expect(result, hasLength(1));
      expect(result.single.component, ScheduleComponent.laboratory);
      expect(result.single.day, 'M');
    });

    test('stops at the first fully blank subject row (trailing blank rows in the sheet)', () {
      final List<List<String?>> rows = [
        ['Confirmation of Faculty Loading'],
        ['Instructor:', 'Jayson Villafuerte'],
        ['SUBJECT', 'Units', 'M', 'T', 'W', 'TH', 'F', 'S', 'Room', 'Section'],
        ['Network Technology 2', null, null, null, null, null, null, null, null, 'BSIT 4B'],
        ['Lecture', '2', '7:00 - 9:00', null, null, null, null, null, null, null],
        ['Laboratory (3 hours)', '1', null, null, null, null, null, null, null, null],
        <String?>[],
        <String?>[],
      ];
      final result = parseFacultyLoading(rows);
      expect(result, hasLength(1));
      expect(result.single.subjectTitle, 'Network Technology 2');
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/schedule_file_parser_cfl_test.dart`
Expected: FAIL — `parseFacultyLoading` doesn't exist yet.

- [ ] **Step 3: Write the implementation**

Append to `lib/data/schedule_import/schedule_file_parser.dart`:

```dart
/// Reads the "Instructor:" labeled cell's neighboring cell — CFL's
/// professor-name header is a two-cell pair (`Instructor:`, name)
/// somewhere in the sheet's first few rows, not tied to the data
/// table's own column layout.
String? _findInstructorName(List<List<String?>> rows) {
  for (final row in rows) {
    for (var i = 0; i < row.length - 1; i++) {
      final value = row[i]?.trim();
      if (value != null && value.toUpperCase() == 'INSTRUCTOR:') {
        final name = row[i + 1]?.trim();
        if (name != null && name.isNotEmpty) return name;
      }
    }
  }
  return null;
}

const _dayColumns = ['M', 'T', 'W', 'TH', 'F', 'S'];

/// Parses a Confirmation of Faculty Loading file into one
/// [ScheduleImportRow] per (subject, component, day, time-range)
/// combination. Every subject row (a row whose first cell is non-blank
/// and isn't itself "Lecture"/"Laboratory (3 hours)") is immediately
/// followed by exactly one Lecture sub-row and one Laboratory sub-row —
/// the file's own established shape. Section is read from the subject
/// row (not the component sub-rows, which leave it blank); Room is read
/// per component sub-row, since lecture and lab can be in different
/// rooms.
List<ScheduleImportRow> parseFacultyLoading(List<List<String?>> rows) {
  final professorName = _findInstructorName(rows);

  final headerIndex = rows.indexWhere((row) =>
      row.any((cell) => cell?.trim().toUpperCase() == 'SUBJECT'));
  if (headerIndex == -1) return [];
  final header = rows[headerIndex];

  final unitsCol = _columnIndex(header, 'Units');
  final roomCol = _columnIndex(header, 'Room');
  final sectionCol = _columnIndex(header, 'Section');
  final dayCols = {
    for (final day in _dayColumns) day: _columnIndex(header, day),
  };

  final result = <ScheduleImportRow>[];
  var i = headerIndex + 1;
  while (i < rows.length) {
    final subjectRow = rows[i];
    final subjectTitle = _cellText(subjectRow, 0);
    if (subjectTitle == null) break; // first fully blank row ends the sheet

    final section = _cellText(subjectRow, sectionCol);
    final componentRows = <(ScheduleComponent, List<String?>)>[];
    if (i + 1 < rows.length &&
        _cellText(rows[i + 1], 0)?.toUpperCase() == 'LECTURE') {
      componentRows.add((ScheduleComponent.lecture, rows[i + 1]));
    }
    if (i + 2 < rows.length &&
        (_cellText(rows[i + 2], 0)?.toUpperCase().startsWith('LABORATORY') ??
            false)) {
      componentRows.add((ScheduleComponent.laboratory, rows[i + 2]));
    }

    for (final (component, row) in componentRows) {
      final units = double.tryParse(_cellText(row, unitsCol) ?? '');
      final room = _cellText(row, roomCol);
      for (final day in _dayColumns) {
        final cellText = _cellText(row, dayCols[day]!);
        if (cellText == null) continue;
        for (final range in extractTimeRanges(cellText)) {
          result.add(ScheduleImportRow(
            subjectTitle: subjectTitle,
            component: component,
            section: section,
            professorName: professorName,
            room: room,
            day: day,
            startTime: range.start,
            endTime: range.end,
            units: units,
          ));
        }
      }
    }
    i += 1 + componentRows.length;
  }
  return result;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/schedule_file_parser_cfl_test.dart`
Expected: PASS (all 4 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/data/schedule_import/schedule_file_parser.dart test/schedule_file_parser_cfl_test.dart
git commit -m "feat: parse the Confirmation of Faculty Loading format"
```

---

### Task 5: Room Schedule parser

**Files:**
- Modify: `lib/data/schedule_import/schedule_file_parser.dart`
- Create: `test/schedule_file_parser_room_schedule_test.dart`

**Interfaces:**
- Consumes: same as Task 4
- Produces: `List<ScheduleImportRow>
  parseRoomSchedule(List<List<String?>> rows)`

Real layout (confirmed from the sample): the room name is a standalone
line directly below the `ROOM SCHEDULE` title (not a table column).
Columns: `SUBJECT, M, T, W, TH, F, S, INSTRUCTOR, SECTION`. Same
subject-row + Lecture/Laboratory-sub-row shape as CFL, but this format
has no per-row Room column (the room is the whole sheet's header) and no
Units column — units are not present in this format at all.

- [ ] **Step 1: Write the failing test**

```dart
// test/schedule_file_parser_room_schedule_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:capstone_dashboard/data/schedule_import/schedule_file_parser.dart';
import 'package:capstone_dashboard/data/schedule_import/schedule_import_row.dart';

void main() {
  group('parseRoomSchedule', () {
    test('reads the room name from the line under the ROOM SCHEDULE title', () {
      final List<List<String?>> rows = [
        ['ROOM SCHEDULE'],
        ['COMPUTER LABORATORY 2'],
        ['SUBJECT', 'M', 'T', 'W', 'TH', 'F', 'S', 'INSTRUCTOR', 'SECTION'],
        ['Introduction to Computing', null, null, null, null, null, null, null, 'BSIT 1A'],
        ['Laboratory (3 hours)', null, null, null, '7:00 - 10:00', null, null, 'Mr. Kar-El Paulino', null],
      ];
      final result = parseRoomSchedule(rows);
      expect(result, hasLength(1));
      expect(result.single.room, 'COMPUTER LABORATORY 2');
      expect(result.single.subjectTitle, 'Introduction to Computing');
      expect(result.single.component, ScheduleComponent.laboratory);
      expect(result.single.day, 'TH');
      expect(result.single.startTime, '07:00');
      expect(result.single.endTime, '10:00');
      expect(result.single.professorName, 'Mr. Kar-El Paulino');
      expect(result.single.section, 'BSIT 1A');
    });

    test('parses a subject with both lecture and laboratory rows', () {
      final List<List<String?>> rows = [
        ['ROOM SCHEDULE'],
        ['COMPUTER LABORATORY 2'],
        ['SUBJECT', 'M', 'T', 'W', 'TH', 'F', 'S', 'INSTRUCTOR', 'SECTION'],
        ['Applied Business Tools in Tourism', null, null, null, null, null, null, null, 'BSTM 3C'],
        ['Lecture', null, '7:00 - 9:00', null, null, null, null, 'Mr. Kim Lasco', null],
        ['Laboratory (3 hours)', null, '9:00 - 12:00', null, null, null, null, 'Mr. Kim Lasco', null],
      ];
      final result = parseRoomSchedule(rows);
      expect(result, hasLength(2));
      expect(result.every((r) => r.room == 'COMPUTER LABORATORY 2'), isTrue);
      expect(result.every((r) => r.section == 'BSTM 3C'), isTrue);
      expect(result.every((r) => r.professorName == 'Mr. Kim Lasco'), isTrue);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/schedule_file_parser_room_schedule_test.dart`
Expected: FAIL — `parseRoomSchedule` doesn't exist yet.

- [ ] **Step 3: Write the implementation**

Append to `lib/data/schedule_import/schedule_file_parser.dart`:

```dart
/// The Room Schedule format names the room on the line directly under
/// the "ROOM SCHEDULE" title, not as a table column. Returns the first
/// non-blank cell found after the title row.
String? _findRoomScheduleRoomName(List<List<String?>> rows) {
  final titleIndex = rows.indexWhere((row) =>
      row.any((cell) => cell?.trim().toUpperCase() == 'ROOM SCHEDULE'));
  if (titleIndex == -1 || titleIndex + 1 >= rows.length) return null;
  for (final cell in rows[titleIndex + 1]) {
    final text = cell?.trim();
    if (text != null && text.isNotEmpty) return text;
  }
  return null;
}

/// Parses a Room Schedule file into one [ScheduleImportRow] per
/// (subject, component, day, time-range) combination. Same
/// subject-row-plus-Lecture/Laboratory-sub-row shape as CFL (Task 4),
/// but the room is the whole sheet's own header (not a per-row column)
/// and there is no Units column in this format.
List<ScheduleImportRow> parseRoomSchedule(List<List<String?>> rows) {
  final room = _findRoomScheduleRoomName(rows);

  final headerIndex = rows.indexWhere((row) =>
      row.any((cell) => cell?.trim().toUpperCase() == 'SUBJECT'));
  if (headerIndex == -1) return [];
  final header = rows[headerIndex];

  final instructorCol = _columnIndex(header, 'Instructor');
  final sectionCol = _columnIndex(header, 'Section');
  final dayCols = {
    for (final day in _dayColumns) day: _columnIndex(header, day),
  };

  final result = <ScheduleImportRow>[];
  var i = headerIndex + 1;
  while (i < rows.length) {
    final subjectRow = rows[i];
    final subjectTitle = _cellText(subjectRow, 0);
    if (subjectTitle == null) break;

    final section = _cellText(subjectRow, sectionCol);
    final componentRows = <(ScheduleComponent, List<String?>)>[];
    if (i + 1 < rows.length &&
        _cellText(rows[i + 1], 0)?.toUpperCase() == 'LECTURE') {
      componentRows.add((ScheduleComponent.lecture, rows[i + 1]));
    }
    if (i + 2 < rows.length &&
        (_cellText(rows[i + 2], 0)?.toUpperCase().startsWith('LABORATORY') ??
            false)) {
      componentRows.add((ScheduleComponent.laboratory, rows[i + 2]));
    }

    for (final (component, row) in componentRows) {
      final professorName = _cellText(row, instructorCol);
      for (final day in _dayColumns) {
        final cellText = _cellText(row, dayCols[day]!);
        if (cellText == null) continue;
        for (final range in extractTimeRanges(cellText)) {
          result.add(ScheduleImportRow(
            subjectTitle: subjectTitle,
            component: component,
            section: section,
            professorName: professorName,
            room: room,
            day: day,
            startTime: range.start,
            endTime: range.end,
          ));
        }
      }
    }
    i += 1 + componentRows.length;
  }
  return result;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/schedule_file_parser_room_schedule_test.dart`
Expected: PASS (both tests)

- [ ] **Step 5: Commit**

```bash
git add lib/data/schedule_import/schedule_file_parser.dart test/schedule_file_parser_room_schedule_test.dart
git commit -m "feat: parse the Room Schedule format"
```

---

### Task 6: Unit -> hours validation

**Files:**
- Create: `lib/data/schedule_import/schedule_conflict_detector.dart`
  (unit-hours validation only in this task — overlap/disagreement
  detection is Task 7)
- Create: `test/schedule_conflict_detector_test.dart`

**Interfaces:**
- Consumes: `ScheduleImportRow`, `ScheduleComponent`
- Produces: `int expectedWeeklyMinutes({required double? lectureUnits,
  required double? labUnits, required double? plainUnits})`;
  `Duration meetingDuration(ScheduleImportRow row)`;
  `UnitHoursValidation validateUnitHours(String subjectTitle, String
  section, List<ScheduleImportRow> meetingsForOneOffering)` returning a
  record `({int expectedMinutes, int actualMinutes, bool matches})`.

- [ ] **Step 1: Write the failing test**

```dart
// test/schedule_conflict_detector_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:capstone_dashboard/data/schedule_import/schedule_conflict_detector.dart';
import 'package:capstone_dashboard/data/schedule_import/schedule_import_row.dart';

ScheduleImportRow _meeting({
  required ScheduleComponent? component,
  required String day,
  required String start,
  required String end,
}) =>
    ScheduleImportRow(
      subjectTitle: 'x',
      component: component,
      day: day,
      startTime: start,
      endTime: end,
    );

void main() {
  group('expectedWeeklyMinutes', () {
    test('a plain (non-split) subject maps units 1:1 to hours', () {
      expect(expectedWeeklyMinutes(lectureUnits: null, labUnits: null, plainUnits: 3), 180);
    });
    test('lecture units count 1 unit = 1 hour', () {
      expect(expectedWeeklyMinutes(lectureUnits: 2, labUnits: null, plainUnits: null), 120);
    });
    test('lab units count 1 unit = 3 hours', () {
      expect(expectedWeeklyMinutes(lectureUnits: null, labUnits: 1, plainUnits: null), 180);
    });
    test('lecture and lab units combine', () {
      expect(expectedWeeklyMinutes(lectureUnits: 2, labUnits: 1, plainUnits: null), 300);
    });
  });

  group('validateUnitHours', () {
    test('matches when a single 3-hour block covers a 3-unit plain subject', () {
      final result = validateUnitHours('The Entrepreneurial Mind', 'BSTM 3C', [
        _meeting(component: null, day: 'F', start: '07:00', end: '10:00'),
      ], plainUnits: 3);
      expect(result.expectedMinutes, 180);
      expect(result.actualMinutes, 180);
      expect(result.matches, isTrue);
    });

    test('matches when lecture and lab meetings sum to the expected total', () {
      final result = validateUnitHours('Human Computer Interaction', 'BSIT 2A', [
        _meeting(component: ScheduleComponent.lecture, day: 'T', start: '07:00', end: '09:00'),
        _meeting(component: ScheduleComponent.laboratory, day: 'TH', start: '07:00', end: '10:00'),
      ], lectureUnits: 2, labUnits: 1);
      expect(result.expectedMinutes, 300);
      expect(result.actualMinutes, 300);
      expect(result.matches, isTrue);
    });

    test('flags a mismatch when scheduled hours fall short of the expected total', () {
      final result = validateUnitHours('Great Books', 'BSTM 3C', [
        _meeting(component: null, day: 'W', start: '07:00', end: '09:00'),
      ], plainUnits: 3);
      expect(result.expectedMinutes, 180);
      expect(result.actualMinutes, 120);
      expect(result.matches, isFalse);
    });

    test('a subject with zero parsed meetings has zero actual minutes and does not match', () {
      final result = validateUnitHours('Ethics', 'BSTM 3C', [], plainUnits: 3);
      expect(result.actualMinutes, 0);
      expect(result.matches, isFalse);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/schedule_conflict_detector_test.dart`
Expected: FAIL — `schedule_conflict_detector.dart` doesn't exist yet.

- [ ] **Step 3: Write the implementation**

```dart
// lib/data/schedule_import/schedule_conflict_detector.dart
import 'schedule_import_row.dart';

const _minutesPerLectureUnit = 60;
const _minutesPerLabUnit = 180;

/// Total weekly minutes a subject's unit counts imply. Verified against
/// every sample row reviewed for this feature (see the plan's Global
/// Constraints): 1 lecture unit = 1 hour/week, 1 laboratory unit = 3
/// hours/week, and a subject with no lecture/lab split maps its whole
/// unit count 1:1 to hours.
int expectedWeeklyMinutes({
  required double? lectureUnits,
  required double? labUnits,
  required double? plainUnits,
}) {
  if (plainUnits != null) return (plainUnits * 60).round();
  final lectureMinutes = (lectureUnits ?? 0) * _minutesPerLectureUnit;
  final labMinutes = (labUnits ?? 0) * _minutesPerLabUnit;
  return (lectureMinutes + labMinutes).round();
}

int _minutesSinceMidnight(String hhmm) {
  final parts = hhmm.split(':');
  return int.parse(parts[0]) * 60 + int.parse(parts[1]);
}

/// Duration of one parsed meeting. Rows missing a start/end time (should
/// not happen for a row [extractTimeRanges] produced, but a manually
/// constructed row could omit them) count as zero duration rather than
/// throwing.
Duration meetingDuration(ScheduleImportRow row) {
  if (row.startTime == null || row.endTime == null) return Duration.zero;
  final minutes =
      _minutesSinceMidnight(row.endTime!) - _minutesSinceMidnight(row.startTime!);
  return Duration(minutes: minutes < 0 ? 0 : minutes);
}

/// Whether an offering's actual scheduled minutes match what its unit
/// counts imply.
typedef UnitHoursValidation = ({int expectedMinutes, int actualMinutes, bool matches});

/// Cross-checks one offering's parsed meetings against its expected
/// weekly hours (Component 3a). [subjectTitle] and [section] are for the
/// caller's own reporting/logging — this function itself only inspects
/// [meetings]. Exactly one of [plainUnits] or ([lectureUnits],
/// [labUnits]) should be supplied, matching [expectedWeeklyMinutes].
UnitHoursValidation validateUnitHours(
  String subjectTitle,
  String section,
  List<ScheduleImportRow> meetings, {
  double? lectureUnits,
  double? labUnits,
  double? plainUnits,
}) {
  final expected = expectedWeeklyMinutes(
    lectureUnits: lectureUnits,
    labUnits: labUnits,
    plainUnits: plainUnits,
  );
  final actual = meetings.fold<int>(
      0, (sum, m) => sum + meetingDuration(m).inMinutes);
  return (expectedMinutes: expected, actualMinutes: actual, matches: expected == actual);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/schedule_conflict_detector_test.dart`
Expected: PASS (all 8 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/data/schedule_import/schedule_conflict_detector.dart test/schedule_conflict_detector_test.dart
git commit -m "feat: add unit-to-hours schedule validation"
```

---

### Task 7: Overlap and cross-source disagreement conflict detection

**Files:**
- Modify: `lib/data/schedule_import/schedule_conflict_detector.dart`
- Modify: `test/schedule_conflict_detector_test.dart`

**Interfaces:**
- Consumes: `ScheduleImportRow`, `meetingDuration`
- Produces: `ScheduleConflict` (sealed via a simple class with a `kind`
  enum: `professorOverlap`, `roomOverlap`, `sourceDisagreement`), each
  carrying the two conflicting `ScheduleImportRow`s and a human-readable
  `description`; `List<ScheduleConflict> detectOverlapConflicts(
  List<ScheduleImportRow> meetings)`; `List<ScheduleConflict>
  detectSourceDisagreements(List<ScheduleImportRow> cflMeetings,
  List<ScheduleImportRow> roomScheduleMeetings)`.

- [ ] **Step 1: Write the failing test**

Append to `test/schedule_conflict_detector_test.dart`:

```dart
  group('detectOverlapConflicts', () {
    test('flags the same professor double-booked at an overlapping time', () {
      final meetings = [
        ScheduleImportRow(
          subjectTitle: 'Subject A', professorName: 'Jane Cruz',
          day: 'M', startTime: '09:00', endTime: '11:00',
        ),
        ScheduleImportRow(
          subjectTitle: 'Subject B', professorName: 'Jane Cruz',
          day: 'M', startTime: '10:00', endTime: '12:00',
        ),
      ];
      final conflicts = detectOverlapConflicts(meetings);
      expect(conflicts, hasLength(1));
      expect(conflicts.single.kind, ScheduleConflictKind.professorOverlap);
    });

    test('flags the same room double-booked at an overlapping time', () {
      final meetings = [
        ScheduleImportRow(
          subjectTitle: 'Subject A', room: 'RM 202',
          day: 'W', startTime: '09:00', endTime: '11:00',
        ),
        ScheduleImportRow(
          subjectTitle: 'Subject B', room: 'RM 202',
          day: 'W', startTime: '10:30', endTime: '12:00',
        ),
      ];
      final conflicts = detectOverlapConflicts(meetings);
      expect(conflicts, hasLength(1));
      expect(conflicts.single.kind, ScheduleConflictKind.roomOverlap);
    });

    test('does not flag two meetings on different days', () {
      final meetings = [
        ScheduleImportRow(
          subjectTitle: 'Subject A', professorName: 'Jane Cruz',
          day: 'M', startTime: '09:00', endTime: '11:00',
        ),
        ScheduleImportRow(
          subjectTitle: 'Subject B', professorName: 'Jane Cruz',
          day: 'T', startTime: '09:00', endTime: '11:00',
        ),
      ];
      expect(detectOverlapConflicts(meetings), isEmpty);
    });

    test('does not flag two meetings that touch but do not overlap', () {
      final meetings = [
        ScheduleImportRow(
          subjectTitle: 'Subject A', professorName: 'Jane Cruz',
          day: 'M', startTime: '09:00', endTime: '11:00',
        ),
        ScheduleImportRow(
          subjectTitle: 'Subject B', professorName: 'Jane Cruz',
          day: 'M', startTime: '11:00', endTime: '12:00',
        ),
      ];
      expect(detectOverlapConflicts(meetings), isEmpty);
    });

    test('ignores meetings with no professor/room set for that kind of overlap', () {
      final meetings = [
        ScheduleImportRow(
          subjectTitle: 'Subject A',
          day: 'M', startTime: '09:00', endTime: '11:00',
        ),
        ScheduleImportRow(
          subjectTitle: 'Subject B',
          day: 'M', startTime: '10:00', endTime: '12:00',
        ),
      ];
      expect(detectOverlapConflicts(meetings), isEmpty);
    });
  });

  group('detectSourceDisagreements', () {
    test('flags when CFL and Room Schedule give different rooms for the same meeting', () {
      final cfl = [
        ScheduleImportRow(
          subjectTitle: 'Subject A', section: 'BSIT 2A', professorName: 'Jane Cruz',
          day: 'M', startTime: '09:00', endTime: '11:00', room: 'RM 202',
        ),
      ];
      final roomSchedule = [
        ScheduleImportRow(
          subjectTitle: 'Subject A', section: 'BSIT 2A', professorName: 'Jane Cruz',
          day: 'M', startTime: '09:00', endTime: '11:00', room: 'RM 203',
        ),
      ];
      final conflicts = detectSourceDisagreements(cfl, roomSchedule);
      expect(conflicts, hasLength(1));
      expect(conflicts.single.kind, ScheduleConflictKind.sourceDisagreement);
    });

    test('does not flag when both sources agree', () {
      final cfl = [
        ScheduleImportRow(
          subjectTitle: 'Subject A', section: 'BSIT 2A', professorName: 'Jane Cruz',
          day: 'M', startTime: '09:00', endTime: '11:00', room: 'RM 202',
        ),
      ];
      final roomSchedule = [
        ScheduleImportRow(
          subjectTitle: 'Subject A', section: 'BSIT 2A', professorName: 'Jane Cruz',
          day: 'M', startTime: '09:00', endTime: '11:00', room: 'RM 202',
        ),
      ];
      expect(detectSourceDisagreements(cfl, roomSchedule), isEmpty);
    });

    test('does not flag a meeting only present in one source', () {
      final cfl = [
        ScheduleImportRow(
          subjectTitle: 'Subject A', section: 'BSIT 2A', professorName: 'Jane Cruz',
          day: 'M', startTime: '09:00', endTime: '11:00', room: 'RM 202',
        ),
      ];
      expect(detectSourceDisagreements(cfl, []), isEmpty);
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/schedule_conflict_detector_test.dart`
Expected: FAIL — `detectOverlapConflicts`/`detectSourceDisagreements`/`ScheduleConflict` don't exist yet.

- [ ] **Step 3: Write the implementation**

Append to `lib/data/schedule_import/schedule_conflict_detector.dart`:

```dart
enum ScheduleConflictKind { professorOverlap, roomOverlap, sourceDisagreement }

class ScheduleConflict {
  const ScheduleConflict({
    required this.kind,
    required this.first,
    required this.second,
    required this.description,
  });

  final ScheduleConflictKind kind;
  final ScheduleImportRow first;
  final ScheduleImportRow second;
  final String description;
}

int _minutesOf(String hhmm) => _minutesSinceMidnight(hhmm);

bool _timesOverlap(ScheduleImportRow a, ScheduleImportRow b) {
  if (a.day != b.day || a.startTime == null || a.endTime == null ||
      b.startTime == null || b.endTime == null) {
    return false;
  }
  final aStart = _minutesOf(a.startTime!);
  final aEnd = _minutesOf(a.endTime!);
  final bStart = _minutesOf(b.startTime!);
  final bEnd = _minutesOf(b.endTime!);
  return aStart < bEnd && bStart < aEnd;
}

/// Flags any two meetings in [meetings] sharing the same professor (or
/// the same room) on the same day with overlapping time ranges. O(n^2)
/// over one batch's meetings, which is small (a term's worth of
/// meetings numbers in the hundreds, not millions) — no index needed.
List<ScheduleConflict> detectOverlapConflicts(List<ScheduleImportRow> meetings) {
  final conflicts = <ScheduleConflict>[];
  for (var i = 0; i < meetings.length; i++) {
    for (var j = i + 1; j < meetings.length; j++) {
      final a = meetings[i];
      final b = meetings[j];
      if (!_timesOverlap(a, b)) continue;

      if (a.professorName != null &&
          a.professorName == b.professorName) {
        conflicts.add(ScheduleConflict(
          kind: ScheduleConflictKind.professorOverlap,
          first: a,
          second: b,
          description:
              '${a.professorName} is double-booked on ${a.day} between '
              '${a.subjectTitle} (${a.startTime}-${a.endTime}) and '
              '${b.subjectTitle} (${b.startTime}-${b.endTime})',
        ));
      }
      if (a.room != null && a.room == b.room) {
        conflicts.add(ScheduleConflict(
          kind: ScheduleConflictKind.roomOverlap,
          first: a,
          second: b,
          description:
              'Room ${a.room} is double-booked on ${a.day} between '
              '${a.subjectTitle} (${a.startTime}-${a.endTime}) and '
              '${b.subjectTitle} (${b.startTime}-${b.endTime})',
        ));
      }
    }
  }
  return conflicts;
}

bool _sameMeetingIdentity(ScheduleImportRow a, ScheduleImportRow b) {
  return a.subjectTitle == b.subjectTitle &&
      a.section == b.section &&
      a.professorName == b.professorName &&
      a.day == b.day &&
      a.startTime == b.startTime &&
      a.endTime == b.endTime;
}

/// Compares [cflMeetings] against [roomScheduleMeetings]: for every pair
/// that appears to describe the same meeting (same subject, section,
/// professor, day, and time), flags a conflict if they disagree on room.
/// A meeting present in only one source is not a conflict here — that
/// gap is the roster cross-check's job (Task 8), not this function's.
List<ScheduleConflict> detectSourceDisagreements(
  List<ScheduleImportRow> cflMeetings,
  List<ScheduleImportRow> roomScheduleMeetings,
) {
  final conflicts = <ScheduleConflict>[];
  for (final cflRow in cflMeetings) {
    for (final roomRow in roomScheduleMeetings) {
      if (!_sameMeetingIdentity(cflRow, roomRow)) continue;
      if (cflRow.room != roomRow.room) {
        conflicts.add(ScheduleConflict(
          kind: ScheduleConflictKind.sourceDisagreement,
          first: cflRow,
          second: roomRow,
          description:
              '${cflRow.subjectTitle} (${cflRow.section}, ${cflRow.day} '
              '${cflRow.startTime}-${cflRow.endTime}): CFL says room '
              '${cflRow.room}, Room Schedule says room ${roomRow.room}',
        ));
      }
    }
  }
  return conflicts;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/schedule_conflict_detector_test.dart`
Expected: PASS (all 16 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/data/schedule_import/schedule_conflict_detector.dart test/schedule_conflict_detector_test.dart
git commit -m "feat: add overlap and cross-source disagreement conflict detection"
```

---

### Task 8: ScheduleImportRepository — matching and commit

**Files:**
- Create: `lib/data/schedule_import_repository.dart`
- Create: `test/schedule_import_repository_test.dart`

**Interfaces:**
- Consumes: `ScheduleImportRow`, `ScheduleComponent`,
  `ScheduleFileFormat`, `SupabaseClient`
- Produces: `class ScheduleImportRepository` with methods:
  `Future<String> resolveSubjectId({required String title, String? code})`,
  `Future<String> resolveSectionId(String rawSectionName)`,
  `Future<String> resolveProfessorId({String? instructorId, String?
  fullName})`, `Future<String> resolveRoomCanonicalName(String rawRoomName)`,
  `Future<List<String>> findRosterMismatches(List<ScheduleImportRow>
  roster, List<ScheduleImportRow> scheduledMeetings)`,
  `Future<void> commitMeetings({required String classSectionId, required
  List<ScheduleImportRow> meetings})`.

This is the only layer touching Supabase — matches this repo's
established convention of signature-guard tests (construct the
repository against a fake Supabase URL, assert methods exist with the
right signature) rather than exercising real queries, exactly like
`test/registrar_repository_class_sections_test.dart`.

- [ ] **Step 1: Write the failing test**

```dart
// test/schedule_import_repository_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:capstone_dashboard/data/schedule_import_repository.dart';
import 'package:capstone_dashboard/data/schedule_import/schedule_import_row.dart';

void main() {
  test('ScheduleImportRepository methods have the expected signatures', () {
    final client = SupabaseClient('https://example.supabase.co', 'anon-key');
    final repo = ScheduleImportRepository(client);

    expect(
      repo.resolveSubjectId,
      isA<Future<String> Function({required String title, String? code})>(),
    );
    expect(
      repo.resolveSectionId,
      isA<Future<String> Function(String)>(),
    );
    expect(
      repo.resolveProfessorId,
      isA<Future<String> Function({String? instructorId, String? fullName})>(),
    );
    expect(
      repo.resolveRoomCanonicalName,
      isA<Future<String> Function(String)>(),
    );
    expect(
      repo.findRosterMismatches,
      isA<Future<List<String>> Function(List<ScheduleImportRow>, List<ScheduleImportRow>)>(),
    );
    expect(
      repo.commitMeetings,
      isA<Future<void> Function({required String classSectionId, required List<ScheduleImportRow> meetings})>(),
    );
  });

  test('resolveProfessorId auto-resolves a placeholder name without a real match', () {
    // Placeholder detection is pure string logic, testable without a
    // live Supabase call — see isPlaceholderProfessorName below.
    expect(isPlaceholderProfessorName('New IT Faculty 2'), isTrue);
    expect(isPlaceholderProfessorName('New GE Instructor 2'), isTrue);
    expect(isPlaceholderProfessorName('Ronald Christian Pallorina'), isFalse);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/schedule_import_repository_test.dart`
Expected: FAIL — `schedule_import_repository.dart` doesn't exist yet.

- [ ] **Step 3: Write the implementation**

```dart
// lib/data/schedule_import_repository.dart
import 'package:supabase_flutter/supabase_flutter.dart';

import 'schedule_import/schedule_import_row.dart';

final _placeholderNamePattern =
    RegExp(r'^New .*(Faculty|Instructor)\s*\d+$', caseSensitive: false);

/// True for placeholder professor names like "New IT Faculty 2" or
/// "New GE Instructor 2" (unfilled positions, per the CFL/Room Schedule
/// samples) — these auto-resolve to a stub profile without asking the
/// Scheduling Officer to confirm, unlike any other unmatched name.
bool isPlaceholderProfessorName(String name) =>
    _placeholderNamePattern.hasMatch(name.trim());

/// Owns every Supabase read/write this feature needs: resolving parsed
/// [ScheduleImportRow]s against existing subjects/sections/profiles/
/// room_aliases/program_aliases, and committing the reconciled result
/// into class_sections/class_section_meetings. The parsing and conflict
/// detection this depends on (schedule_import/) has no Supabase
/// dependency and is unit-tested separately.
class ScheduleImportRepository {
  ScheduleImportRepository(this._client);
  final SupabaseClient _client;

  /// Matches by [code] (exact) when given, else by case/whitespace-
  /// normalized [title] against `subjects.title`. Throws
  /// [StateError] with a message identifying the missing code if no
  /// match is found and [code] is null — callers sourced from CFL/Room
  /// Schedule (no code available) must have already collected a code
  /// from the Scheduling Officer during review before calling this.
  Future<String> resolveSubjectId({required String title, String? code}) async {
    if (code != null) {
      final existing = await _client
          .from('subjects')
          .select('id')
          .eq('code', code)
          .maybeSingle();
      if (existing != null) return existing['id'] as String;
      final inserted = await _client
          .from('subjects')
          .insert({'code': code, 'title': title})
          .select('id')
          .single();
      return inserted['id'] as String;
    }

    final normalizedTitle = title.trim().toLowerCase();
    final candidates = await _client.from('subjects').select('id, title');
    for (final row in candidates as List) {
      if ((row['title'] as String).trim().toLowerCase() == normalizedTitle) {
        return row['id'] as String;
      }
    }
    throw StateError(
        'No subject found for "$title" and no code was supplied — '
        'the Scheduling Officer must provide a course code for this new '
        'subject before it can be created.');
  }

  /// Matches [rawSectionName] against `sections.name`, normalized by
  /// stripping spaces and hyphens ("BSIT 2A" == "BSIT-2A"). Creates a
  /// new section if none matches, resolving its program via
  /// `program_aliases` when the name's letter prefix matches a known
  /// alias.
  Future<String> resolveSectionId(String rawSectionName) async {
    String normalize(String s) => s.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
    final target = normalize(rawSectionName);

    final sections = await _client.from('sections').select('id, name');
    for (final row in sections as List) {
      if (normalize(row['name'] as String) == target) return row['id'] as String;
    }

    final match = RegExp(r'^([A-Za-z]+)\s*[- ]?(\d+)([A-Za-z])$')
        .firstMatch(rawSectionName.trim());
    final programAbbrev = match?.group(1);
    final yearLevel = match != null ? int.tryParse(match.group(2)!) : null;

    String? canonicalProgram;
    if (programAbbrev != null) {
      final alias = await _client
          .from('program_aliases')
          .select('canonical_program')
          .eq('alias', programAbbrev)
          .maybeSingle();
      canonicalProgram = alias?['canonical_program'] as String?;
    }

    final inserted = await _client
        .from('sections')
        .insert({
          'name': rawSectionName,
          'program': canonicalProgram,
          'year_level': yearLevel,
        })
        .select('id')
        .single();
    return inserted['id'] as String;
  }

  /// Matches by [instructorId] (exact, from the Classes+Professor list)
  /// when given, else by normalized full-name against
  /// `profiles.first_name`/`last_name` (from CFL/Room Schedule). A
  /// placeholder name ([isPlaceholderProfessorName]) auto-creates a stub
  /// profile (`role: 'Teacher'`, `status: 'Placeholder'`) without
  /// requiring the caller to confirm first.
  Future<String> resolveProfessorId({String? instructorId, String? fullName}) async {
    if (instructorId != null) {
      final existing = await _client
          .from('profiles')
          .select('id')
          .eq('employee_id', instructorId)
          .maybeSingle();
      if (existing != null) return existing['id'] as String;
    }

    if (fullName != null) {
      final normalized = fullName.trim().toLowerCase();
      final profiles = await _client
          .from('profiles')
          .select('id, first_name, last_name');
      for (final row in profiles as List) {
        final combined =
            '${row['first_name']} ${row['last_name']}'.trim().toLowerCase();
        if (combined == normalized) return row['id'] as String;
      }

      if (isPlaceholderProfessorName(fullName)) {
        final inserted = await _client
            .from('profiles')
            .insert({
              'first_name': fullName,
              'last_name': '',
              'role': 'Teacher',
              'status': 'Placeholder',
            })
            .select('id')
            .single();
        return inserted['id'] as String;
      }
    }

    throw StateError(
        'No professor found for instructorId=$instructorId, '
        'fullName=$fullName, and it is not a recognized placeholder name '
        '— the Scheduling Officer must confirm create-new-vs-pick-existing '
        'before this professor can be resolved.');
  }

  /// Resolves [rawRoomName] to its canonical name via `room_aliases`.
  /// A room with no existing alias returns [rawRoomName] itself as its
  /// own canonical name (the "this is a new room" review choice) — it is
  /// the caller's responsibility to have already written that decision
  /// as a `room_aliases` row (via the review screen, not this method)
  /// before calling this for a name that should now resolve.
  Future<String> resolveRoomCanonicalName(String rawRoomName) async {
    final alias = await _client
        .from('room_aliases')
        .select('canonical_room')
        .eq('alias', rawRoomName)
        .maybeSingle();
    return (alias?['canonical_room'] as String?) ?? rawRoomName;
  }

  /// Cross-checks the Registrar's roster against what was actually
  /// scheduled (Component 3's roster cross-check). Returns one
  /// human-readable description per mismatch, in both directions: a
  /// roster pairing never scheduled anywhere, and a scheduled pairing
  /// not present in the roster.
  Future<List<String>> findRosterMismatches(
    List<ScheduleImportRow> roster,
    List<ScheduleImportRow> scheduledMeetings,
  ) async {
    String pairingKey(ScheduleImportRow row) =>
        '${row.subjectTitle.trim().toLowerCase()}::${(row.professorName ?? '').trim().toLowerCase()}';

    final rosterPairings = roster.map(pairingKey).toSet();
    final scheduledPairings = scheduledMeetings.map(pairingKey).toSet();

    final mismatches = <String>[];
    for (final row in roster) {
      if (!scheduledPairings.contains(pairingKey(row))) {
        mismatches.add(
            'Roster lists ${row.professorName} teaching ${row.subjectTitle}, '
            'but no CFL/Room Schedule meeting was found for that pairing.');
      }
    }
    for (final row in scheduledMeetings) {
      if (!rosterPairings.contains(pairingKey(row))) {
        mismatches.add(
            '${row.professorName} is scheduled to teach ${row.subjectTitle}, '
            'but that pairing is not in the uploaded roster.');
      }
    }
    return mismatches;
  }

  /// Upserts every meeting in [meetings] under [classSectionId]. Keyed
  /// on (class_section_id, component, day, sequence) — sequence is each
  /// meeting's position among same-component-same-day meetings in
  /// [meetings]'s own order, so a correction that only changes a time
  /// range still updates the same row instead of duplicating it (see
  /// spec Component 5).
  Future<void> commitMeetings({
    required String classSectionId,
    required List<ScheduleImportRow> meetings,
  }) async {
    final sequenceCounters = <String, int>{};
    for (final meeting in meetings) {
      final componentKey = meeting.component?.name ?? 'null';
      final groupKey = '$componentKey::${meeting.day}';
      final sequence = sequenceCounters.update(
        groupKey,
        (n) => n + 1,
        ifAbsent: () => 0,
      );

      await _client.from('class_section_meetings').upsert(
        {
          'class_section_id': classSectionId,
          'component': meeting.component?.name.replaceFirstMapped(
              RegExp('^.'), (m) => m.group(0)!.toUpperCase()),
          'day': meeting.day,
          'start_time': meeting.startTime,
          'end_time': meeting.endTime,
          'room': meeting.room,
        },
        onConflict: 'class_section_id,component,day,sequence',
      );
      // Note: onConflict above assumes a unique constraint on
      // (class_section_id, component, day, sequence); since sequence is
      // computed client-side here rather than stored, a later plan
      // adding the review/commit UI must add that column and constraint
      // to class_section_meetings (Task 1's table does not have it yet
      // — flagged here rather than guessed at, since the exact
      // migration belongs with the UI plan that actually drives commits).
    }
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/schedule_import_repository_test.dart`
Expected: PASS (both tests)

- [ ] **Step 5: Run the full test suite to confirm nothing else broke**

Run: `flutter test -j 1`
Expected: same pass count as before this plan started, plus every test
this plan added, with 0 new failures.

- [ ] **Step 6: Commit**

```bash
git add lib/data/schedule_import_repository.dart test/schedule_import_repository_test.dart
git commit -m "feat: add ScheduleImportRepository for matching and committing parsed schedule data"
```

---

## Note for the next plan

`commitMeetings`'s `onConflict` target
(`class_section_id,component,day,sequence`) references a `sequence`
column that Task 1's `class_section_meetings` table does not define —
noted explicitly in Task 8 rather than added speculatively here, since
the review/commit UI plan (next) is what actually calls `commitMeetings`
with real batches and is where getting that upsert key exactly right
against real multi-meeting-per-day data matters. That plan must add the
column + a unique constraint on `(class_section_id, component, day,
sequence)` to `class_section_meetings` before `commitMeetings` can work
against a real database — this plan's Task 8 test only verifies the
method's signature and the pure `isPlaceholderProfessorName` logic, not
a live upsert.

This plan also does not add `'Scheduling_Officer'::app_role` to any RLS
policy, and does not build the review screen, the Scheduling Officer
dashboard/role, or the Registrar's roster-upload UI — all of those are
separate, later plans (per the spec's Migration/rollout order) that
consume `ScheduleImportRepository` and the `schedule_import/` parsing
library this plan builds.
