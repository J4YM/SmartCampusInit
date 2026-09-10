# Registrar Grades Schema + Class Schedule Stand-In Wiring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a real `grades` table and wire the Registrar's Grades tab to it, and replace Class Schedule's remaining disabled stand-in fields (Section, Year Level, School Year, Term) with real data.

**Architecture:** Same established pattern as every other wired feature in this codebase — `RegistrarRepository` (`lib/data/registrar_repository.dart`) owns all Supabase access; `packages/registrar_module` stays Supabase-agnostic; `RegistrarConnectedPage`/`RegistrarDashboardPage` wire the two together, falling back to `RegistrarMockData` when `AppEnv.supabaseConfigured` is false.

**Tech Stack:** Flutter, Supabase (Postgres + PostgREST + RLS), the existing `registrar_module` presentation package.

**Spec:** `docs/superpowers/specs/2026-09-10-registrar-grades-and-class-schedule-design.md`

## Global Constraints

- Any new/changed SQL must be shown to the user for manual approval in Supabase's SQL editor — **never auto-run** any SQL yourself, under any circumstance. Just write the file.
- No Senior High School / education-level backing data exists anywhere in the schema (every seeded `sections` row is a College program) — do not invent any. `GradeRecordModel.educationLevel` is always `'College'` for real data; the Education Level pill in Class Schedule stays exactly as-is (disabled, decorative).
- RFID Notify tab persistence and the "mark student irregular" / move-enrollment-to-a-different-class_section flow are explicitly out of scope (spec's Non-goals) — do not touch `RfidManagementView`, `_submitRfidNotifications`, or add any enrollment-editing UI/repository method.
- `remark` is never stored in the database — always recomputed from the numeric `grade` via `GradeRemark.fromGrade()`. Never trust a stored remark string as source of truth.
- Repository methods get signature-guard tests (construct with a fake Supabase URL, tear off the method against its exact function-type signature, never call it) — this codebase's established pattern, e.g. `test/registrar_repository_class_sections_test.dart`.
- Demo-mode fallback convention: every new connected-page callback must be `null` when `AppEnv.supabaseConfigured` is false (or the underlying repository getter returns null), and every presentation-package widget consuming that callback must already fall back to a local snackbar/no-op when it's null — do not remove or weaken any existing demo-mode behavior.

---

### Task 1: `GradeRemark.fromGrade()` — add the missing "failing" case

**Files:**
- Modify: `packages/registrar_module/lib/pages/dashboard/grades_view.dart`
- Test: `packages/registrar_module/test/grade_remark_test.dart`

**Interfaces:**
- Produces: `GradeRemark.failing` (new enum value), `GradeRemark.fromGrade(double grade) -> GradeRemark` (static method).
- Consumes: nothing from other tasks — fully self-contained.

**Context:** `GradeRemark.fromValue(String?)` (the existing JSON-string parser) has no "failing" case — any unrecognized string, including what a failing grade's remark string would be, falls through to `GradeRemark.outstanding` (see `grades_view.dart:48-52`). Curated mock data never triggers this since every demo grade happens to be passing. Task 2's real `fetchGradeRecords()` will use a NEW method, `fromGrade(double)`, that computes remark directly from the numeric grade — never storing or parsing a remark string at all — so this bug can't reach real data. `fromValue` itself is left untouched (still used by `GradeRecordModel.fromJson`, unrelated to this plan).

- [ ] **Step 1: Write the failing test**

```dart
// packages/registrar_module/test/grade_remark_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:registrar_module/registrar_module.dart';

void main() {
  test('GradeRemark.fromGrade maps all four bands correctly', () {
    expect(GradeRemark.fromGrade(95), GradeRemark.outstanding);
    expect(GradeRemark.fromGrade(90), GradeRemark.outstanding);
    expect(GradeRemark.fromGrade(87), GradeRemark.verySatisfactory);
    expect(GradeRemark.fromGrade(85), GradeRemark.verySatisfactory);
    expect(GradeRemark.fromGrade(80), GradeRemark.satisfactory);
    expect(GradeRemark.fromGrade(75), GradeRemark.satisfactory);
    // The bug this task exists to fix: below the passing threshold (75,
    // matching GradesView's own passingRate calculation) must be Failing,
    // never silently fall through to Outstanding.
    expect(GradeRemark.fromGrade(74.9), GradeRemark.failing);
    expect(GradeRemark.fromGrade(0), GradeRemark.failing);
  });
}
```

Check first whether `packages/registrar_module/lib/registrar_module.dart` (the package barrel file) already exports `pages/dashboard/grades_view.dart` or `GradeRemark` specifically — if the test's `import 'package:registrar_module/registrar_module.dart';` doesn't resolve `GradeRemark`, either add the export to the barrel file or import `package:registrar_module/pages/dashboard/grades_view.dart` directly in the test, matching whichever pattern this package's other tests already use for similarly-located types.

- [ ] **Step 2: Run it, confirm it fails**

Run: `flutter test packages/registrar_module/test/grade_remark_test.dart` (from the repo root — do NOT `cd` into the package first; this environment has a known issue where running tests from inside `packages/registrar_module` resolves a stale, incompatible `google_fonts` version and fails to compile for unrelated reasons) — expect failure (`GradeRemark.failing`/`fromGrade` don't exist).

- [ ] **Step 3: Add the `failing` case and `fromGrade` to `GradeRemark`**

Read `packages/registrar_module/lib/pages/dashboard/grades_view.dart` in full first (lines 25-53 are the enum) — this is a small, self-contained edit within it.

```dart
enum GradeRemark {
  outstanding,
  verySatisfactory,
  satisfactory,
  failing;

  String get label => switch (this) {
        GradeRemark.outstanding => 'Outstanding',
        GradeRemark.verySatisfactory => 'Very Satisfactory',
        GradeRemark.satisfactory => 'Satisfactory',
        GradeRemark.failing => 'Failing',
      };

  Color get badgeBackground => switch (this) {
        GradeRemark.outstanding => const Color(0xFFE6F4EA),
        GradeRemark.verySatisfactory => const Color(0x33345892),
        GradeRemark.satisfactory => const Color(0x33FFCC00),
        GradeRemark.failing => const Color(0x33CD4855),
      };

  Color get badgeText => switch (this) {
        GradeRemark.outstanding => RegistrarColors.successGreen,
        GradeRemark.verySatisfactory => RegistrarColors.brightBlue,
        GradeRemark.satisfactory => const Color(0xFF279142),
        GradeRemark.failing => RegistrarColors.dangerRed,
      };

  static GradeRemark fromValue(String? value) => switch (value) {
        'Very Satisfactory' => GradeRemark.verySatisfactory,
        'Satisfactory' => GradeRemark.satisfactory,
        'Failing' => GradeRemark.failing,
        _ => GradeRemark.outstanding,
      };

  /// Computes the remark directly from a numeric grade — used by real data
  /// (RegistrarRepository.fetchGradeRecords), which never stores or reads a
  /// remark string. 75 matches GradesView's own passing-rate threshold.
  static GradeRemark fromGrade(double grade) {
    if (grade < 75) return GradeRemark.failing;
    if (grade >= 90) return GradeRemark.outstanding;
    if (grade >= 85) return GradeRemark.verySatisfactory;
    return GradeRemark.satisfactory;
  }
}
```

(`badgeBackground`'s new `0x33CD4855` is `RegistrarColors.dangerRed` — `0xFFCD4855` — at the same `0x33` alpha the existing `verySatisfactory`/`satisfactory` tints already use, for visual consistency.)

Note: `fromValue`'s existing default case (`_ => GradeRemark.outstanding`) is UNCHANGED by this task — adding the `'Failing' => GradeRemark.failing` case above it does not fix `fromValue`'s "unrecognized string falls through" behavior in general (a genuinely garbled string still defaults to Outstanding), it just means a value that's LITERALLY the string `'Failing'` now round-trips correctly. This is fine and matches the spec: `fromValue` is never used by real data in this plan.

- [ ] **Step 4: Run the test, confirm it passes**

Run: `flutter test packages/registrar_module/test/grade_remark_test.dart` — expect PASS.

- [ ] **Step 5: Run the full suite and analyze**

Run: `flutter test -j 1` (root) — expect all passing except the one pre-existing, unrelated `guidance_counselor_cold_boot_mobile_test.dart` failure. Also run `flutter test packages/registrar_module/test/` (from the repo root) to confirm nothing in that package's existing test suite broke from the enum change (an exhaustive `switch` on `GradeRemark` anywhere else in the package would now fail to compile if it isn't updated — the compiler will tell you exactly where if so; fix any such site the same way `label`/`badgeBackground`/`badgeText` were updated above).

Run: `flutter analyze packages/registrar_module/lib/pages/dashboard/grades_view.dart` — expect no issues.

- [ ] **Step 6: Commit**

```bash
git add packages/registrar_module/lib/pages/dashboard/grades_view.dart packages/registrar_module/test/grade_remark_test.dart
git commit -m "fix: add the missing Failing case to GradeRemark"
```

---

### Task 2: Grades schema + `RegistrarRepository` grades methods

**Files:**
- Create: `supabase/add_grades_schema.sql`
- Modify: `lib/data/registrar_repository.dart`
- Test: `test/registrar_repository_grades_test.dart`

**Interfaces:**
- Produces: `RegistrarRepository.fetchGradeRecords() -> Future<List<GradeRecordModel>>`, `RegistrarRepository.saveGrade({required String studentId, required String classSectionId, required double grade}) -> Future<void>`.
- Consumes: `GradeRemark.fromGrade(double)` (Task 1 — already merged by the time this task runs).

- [ ] **Step 1: Write the SQL migration**

```sql
-- supabase/add_grades_schema.sql
--
-- One grade per student per class_sections offering (subject + section +
-- school year + term, via the existing class_sections table — no separate
-- school_year/term/section columns needed here). Registrar/Admin-only, no
-- student/parent access — unlike good_moral_requests, nothing else needs a
-- narrower insert-only policy for this table.
--
-- Run in Supabase SQL Editor, after add_subjects_enrollments_schema.sql.

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

- [ ] **Step 2: Get user approval, then have them run it in Supabase SQL Editor**

Show the exact SQL above and wait for confirmation before continuing — this repo's established convention: do not run it yourself, and do not proceed past this step until you have explicit confirmation. (If you are a dispatched implementer subagent with no channel to the real human, skip waiting — write the file, note in your report that it's pending manual execution, and continue; your coordinator relays it. Nothing in the remaining steps requires the SQL to have actually been run, since the signature-guard test never calls the live database.)

- [ ] **Step 3: Write the failing signature-guard test**

```dart
// test/registrar_repository_grades_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:registrar_module/registrar_module.dart';
import 'package:capstone_dashboard/data/registrar_repository.dart';

void main() {
  test('fetchGradeRecords and saveGrade have the expected signatures', () {
    final repo = RegistrarRepository(
      SupabaseClient('https://example.invalid', 'anon-key'),
    );

    final Future<List<GradeRecordModel>> Function() fetchGradeRecords =
        repo.fetchGradeRecords;
    expect(fetchGradeRecords, isNotNull);

    final Future<void> Function({
      required String studentId,
      required String classSectionId,
      required double grade,
    }) saveGrade = repo.saveGrade;
    expect(saveGrade, isNotNull);
  });
}
```

- [ ] **Step 4: Run it, confirm it fails**

Run: `flutter test test/registrar_repository_grades_test.dart` — expect failure (`fetchGradeRecords`/`saveGrade` don't exist).

- [ ] **Step 5: Add the methods to `RegistrarRepository`**

Read `lib/data/registrar_repository.dart` in full first — this file already has a `_fullName(String? first, String? last)` private helper (used by `fetchStudents()`) and a `_studentSelect` constant; reuse `_fullName` rather than duplicating it.

`grades` cannot be embedded from `enrollments` via PostgREST (`grades` has no FK back to `enrollments` — it FKs `students`/`class_sections` individually, not `enrollments`), so this fetches `enrollments` (the roster — every currently-active enrollment gets a row, graded or not) and `grades` (existing grades only) as two separate queries and merges them client-side, keyed on `student_id|class_section_id`. This is why the Grades tab can show and edit a grade for a student who's never been graded before, not just already-graded students.

```dart
  /// Active enrollments -> class_sections -> subjects/sections, left-joined
  /// (client-side — see below) against grades. Every actively-enrolled
  /// student gets a row even with no grade yet (defaults to 0.0, which
  /// GradeRemark.fromGrade reports as Failing — "not yet graded" reads the
  /// same as "not yet passing" until a real grade is entered, which is the
  /// honest state rather than inventing a placeholder passing grade).
  Future<List<GradeRecordModel>> fetchGradeRecords() async {
    final enrollmentRows = await _client
        .from('enrollments')
        .select('''
          student_id,
          class_section_id,
          students ( student_number, profiles ( first_name, last_name ) ),
          class_sections ( term, sections ( name, year_level ) )
        ''')
        .eq('status', 'Active');

    final gradeRows =
        await _client.from('grades').select('student_id, class_section_id, grade');

    final gradeByKey = <String, double>{};
    for (final row in gradeRows as List<dynamic>) {
      final r = row as Map<String, dynamic>;
      final key = '${r['student_id']}|${r['class_section_id']}';
      gradeByKey[key] = (r['grade'] as num).toDouble();
    }

    return (enrollmentRows as List<dynamic>).map((e) {
      final row = e as Map<String, dynamic>;
      final studentId = row['student_id'] as String;
      final classSectionId = row['class_section_id'] as String;
      final student = row['students'] as Map<String, dynamic>?;
      final profile = student?['profiles'] as Map<String, dynamic>?;
      final classSection = row['class_sections'] as Map<String, dynamic>?;
      final section = classSection?['sections'] as Map<String, dynamic>?;
      final term = classSection?['term'] as String? ?? '';
      final key = '$studentId|$classSectionId';
      final grade = gradeByKey[key] ?? 0.0;

      return GradeRecordModel(
        id: key,
        studentName: _fullName(
          profile?['first_name'] as String?,
          profile?['last_name'] as String?,
        ),
        studentId: student?['student_number'] as String? ?? '',
        gradeSection: section?['name'] as String? ?? '',
        grade: grade,
        remark: GradeRemark.fromGrade(grade),
        educationLevel: 'College',
        semester: term.startsWith('2') ? '2nd' : '1st',
      );
    }).toList();
  }

  /// Upsert — a registrar re-saving an already-graded student updates the
  /// existing row rather than violating the (student_id, class_section_id)
  /// unique constraint.
  Future<void> saveGrade({
    required String studentId,
    required String classSectionId,
    required double grade,
  }) async {
    await _client.from('grades').upsert(
      {
        'student_id': studentId,
        'class_section_id': classSectionId,
        'grade': grade,
      },
      onConflict: 'student_id,class_section_id',
    );
  }
```

Add the import: `import 'package:registrar_module/registrar_module.dart' show GradeRecordModel, GradeRemark;` if `GradeRecordModel`/`GradeRemark` aren't already reachable from this file's existing `import 'package:registrar_module/registrar_module.dart';` (check the top of the file first — it likely already has a bare `import 'package:registrar_module/registrar_module.dart';` covering this; only add a new import if that one doesn't exist or doesn't export these two types).

`GradeRecordModel.id` is now `'$studentId|$classSectionId'` (a composite key), not a real database row id — `grades.id` (the UUID primary key) is never surfaced to the UI at all. This is an internal encoding local to how the connected-page layer (Task 3) turns a `GradesView.onGradeChanged(id, grade)` callback back into the `studentId`/`classSectionId` `saveGrade` needs — nothing in `registrar_module` needs to know this encoding exists; it only ever treats `id` as an opaque string.

- [ ] **Step 6: Run the test, confirm it passes**

Run: `flutter test test/registrar_repository_grades_test.dart` — expect PASS.

- [ ] **Step 7: Run the full suite and analyze**

Run: `flutter test -j 1` — expect all passing except the one pre-existing, unrelated `guidance_counselor_cold_boot_mobile_test.dart` failure.

Run: `flutter analyze lib/data/registrar_repository.dart` — expect no issues.

- [ ] **Step 8: Commit**

```bash
git add supabase/add_grades_schema.sql lib/data/registrar_repository.dart test/registrar_repository_grades_test.dart
git commit -m "feat: add grades schema + RegistrarRepository fetchGradeRecords/saveGrade"
```

---

### Task 3: Wire the Grades tab into `RegistrarConnectedPage`

**Files:**
- Modify: `lib/ui/registrar_connected_page.dart`
- Modify: `packages/registrar_module/lib/pages/dashboard/registrar_dashboard_page.dart`

**Interfaces:**
- Consumes: `RegistrarRepository.fetchGradeRecords()`/`saveGrade(...)` (Task 2).
- Produces: `RegistrarDashboardPage.onSaveGradeChanges` (new callback prop, type `Future<void> Function(List<GradeRecordModel> records)?`) — no later task in this plan depends on this, but it's the seam between the two files this task touches.

**Context:** `RegistrarDashboardPage` already has `initialGradeRecords` (a constructor prop) and a local `gradeRecords` state field seeded from it, plus `_updateGradeRecord(id, grade)` (local optimistic edit, already wired to `GradesView.onGradeChanged`) and `_saveGradeChanges()` (currently ONLY shows a local demo snackbar — `registrar_dashboard_page.dart:705-709`). `RegistrarConnectedPage` never sets `initialGradeRecords` today, so the Grades tab is 100% `RegistrarMockData` regardless of Supabase config. This task doesn't touch `_updateGradeRecord`, `GradesView`, or `GradeRecordModel` — only adds real load + save wiring around what already exists.

- [ ] **Step 1: Add `onSaveGradeChanges` to `RegistrarDashboardPage` and thread it into `_saveGradeChanges`**

Read `packages/registrar_module/lib/pages/dashboard/registrar_dashboard_page.dart` in full first, specifically: the constructor (around line 217, alongside `initialGradeRecords`), the `didUpdateWidget` override (around line 335-355, which already syncs `scheduleEntries`/`subjectOptions`/`teacherOptions` from their `initial*` props — extend it the same way for `gradeRecords`/`initialGradeRecords`), and `_saveGradeChanges()` (around line 705-709).

Add to the constructor, alongside the other `onSave*`/`on*` callback params:

```dart
    this.onSaveGradeChanges,
```

Add to the class body, alongside `onSaveClassSchedule`'s own field declaration:

```dart
  /// Called with every currently-visible edited grade record when "Save
  /// Changes" is tapped on the Grades tab. Falls back to a local demo
  /// snackbar when omitted (demo behavior) — matches onSaveClassSchedule's
  /// established null-fallback shape exactly.
  final Future<void> Function(List<GradeRecordModel> records)? onSaveGradeChanges;
```

Extend the existing `didUpdateWidget` override with one more block, matching the exact shape of its `scheduleEntries`/`subjectOptions`/`teacherOptions` blocks:

```dart
    final newGrades = widget.initialGradeRecords;
    if (newGrades != null && newGrades != oldWidget.initialGradeRecords) {
      gradeRecords = newGrades;
    }
```

Replace `_saveGradeChanges()`'s body, matching `_saveScheduleChanges`'s exact null-fallback-then-delegate shape:

```dart
  void _saveGradeChanges() {
    final onSaveGradeChanges = widget.onSaveGradeChanges;
    if (onSaveGradeChanges == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Grade changes saved.')),
      );
      return;
    }
    onSaveGradeChanges(gradeRecords);
  }
```

(`gradeRecords` here is the full current tab state, including any edits `_updateGradeRecord` already applied locally — Task 2's `saveGrade` is an upsert, so re-saving every visible record, not just the ones actually changed this session, is harmless and avoids adding separate dirty-tracking. The Grades tab is paginated, so this is always a bounded page-sized batch, never the whole table.)

- [ ] **Step 2: Run analyze to confirm this file alone still compiles**

Run: `flutter analyze packages/registrar_module/lib/pages/dashboard/registrar_dashboard_page.dart` — expect exactly one error: `_RegistrarConnectedPageState` (a different file) doesn't yet supply `onSaveGradeChanges`, which is fine (it's optional/nullable) — actually expect NO issues at all in this file alone, since the new field is nullable and every existing call site of `RegistrarDashboardPage(...)` elsewhere doesn't need to change (it's an additional named parameter with no default requirement). If `flutter analyze` reports anything else, re-read this step's edits before continuing.

- [ ] **Step 3: Wire `RegistrarConnectedPage`: load grades on init, implement `_saveGradeChanges`**

Read `lib/ui/registrar_connected_page.dart` in full first — add a `List<GradeRecordModel>? _gradeRecords;` field (alongside the existing `_scheduleEntries`/`_subjectOptions`/`_teacherOptions` fields), a `_loadGradeRecords()` method (matching `_loadScheduleEntries()`'s exact try/catch/`_toast`-on-failure shape), call it from `initState` alongside the other `addPostFrameCallback` loads, and add a `_saveGradeChanges` method:

```dart
  Future<void> _loadGradeRecords() async {
    final repo = _registrarRepo;
    if (repo == null) return;
    try {
      final records = await repo.fetchGradeRecords();
      if (!mounted) return;
      setState(() => _gradeRecords = records);
    } catch (e) {
      _toast('Could not load grades: $e');
    }
  }

  /// Saves every currently-visible grade record (Task 2's saveGrade is an
  /// upsert, so re-saving unchanged rows alongside edited ones is
  /// harmless), then reloads so the table reflects server-confirmed state
  /// (including the freshly-recomputed GradeRemark for anything that just
  /// crossed a threshold).
  Future<void> _saveGradeChanges(List<GradeRecordModel> records) async {
    final repo = _registrarRepo;
    if (repo == null) return;
    try {
      for (final record in records) {
        final parts = record.id.split('|');
        await repo.saveGrade(
          studentId: parts[0],
          classSectionId: parts[1],
          grade: record.grade,
        );
      }
      await _loadGradeRecords();
      _toast('Grade changes saved.');
    } catch (e) {
      _toast('Could not save grade changes: $e');
    }
  }
```

Add `_loadGradeRecords()` to `initState`'s existing sequence of `WidgetsBinding.instance.addPostFrameCallback((_) => ...)` calls, in the same style as `_loadClassScheduleOptions`/`_loadScheduleEntries`.

In the `build` method's `RegistrarDashboardPage(...)` construction, add:

```dart
      initialGradeRecords: _gradeRecords,
      onSaveGradeChanges: _registrarRepo == null ? null : _saveGradeChanges,
```

(matching `onSaveClassSchedule`'s exact `_registrarRepo == null ? null : ...` null-fallback shape.)

Update this file's class-level doc comment (currently says "Grades still runs on the dashboard's own built-in mock data since there's no `grade_records` table yet" — this is no longer true) to reflect that Grades is now wired too.

- [ ] **Step 4: Run the full suite and analyze**

Run: `flutter test -j 1` — expect all passing except the one pre-existing, unrelated `guidance_counselor_cold_boot_mobile_test.dart` failure.

Run: `flutter analyze lib/ui/registrar_connected_page.dart packages/registrar_module/lib/pages/dashboard/registrar_dashboard_page.dart` — expect no issues.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/registrar_connected_page.dart packages/registrar_module/lib/pages/dashboard/registrar_dashboard_page.dart
git commit -m "feat: wire the Grades tab to real Supabase data"
```

---

### Task 4: `RegistrarRepository.fetchSections()`

**Files:**
- Modify: `lib/data/registrar_repository.dart`
- Test: `test/registrar_repository_sections_test.dart`

**Interfaces:**
- Produces: `SectionOption` (new model — `{id, name, yearLevel}`), `RegistrarRepository.fetchSections() -> Future<List<SectionOption>>`.
- Consumes: nothing from other tasks in this plan — independent of Tasks 1-3.

**IMPORTANT for the next task (Task 5), which you will not see:** `SectionOption` must be defined in `registrar_module` (not in `lib/data/registrar_repository.dart`), matching the exact same reasoning `SubjectOption`/`TeacherOption` already follow in this file (`registrar_module` cannot depend back on the app package that depends on it — see this file's existing doc comment above the `export 'package:registrar_module/registrar_module.dart' show SubjectOption, TeacherOption;` line). `class_schedule_view.dart` needs to import `SectionOption` directly.

- [ ] **Step 1: Write the failing signature-guard test**

```dart
// test/registrar_repository_sections_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:registrar_module/registrar_module.dart';
import 'package:capstone_dashboard/data/registrar_repository.dart';

void main() {
  test('fetchSections has the expected signature', () {
    final repo = RegistrarRepository(
      SupabaseClient('https://example.invalid', 'anon-key'),
    );

    final Future<List<SectionOption>> Function() fetchSections =
        repo.fetchSections;
    expect(fetchSections, isNotNull);
  });
}
```

- [ ] **Step 2: Run it, confirm it fails**

Run: `flutter test test/registrar_repository_sections_test.dart` — expect failure (`SectionOption`/`fetchSections` don't exist).

- [ ] **Step 3: Define `SectionOption` in `registrar_module` and re-export it**

Read `packages/registrar_module/lib/pages/dashboard/class_schedule_view.dart` in full first — add `SectionOption` in this file, right next to the existing `SubjectOption`/`TeacherOption` definitions (same file, same section, matching their exact style):

```dart
/// A section a class-schedule offering can be assigned to. Backed by the
/// real `sections` table via `RegistrarRepository.fetchSections()`.
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
```

Check `packages/registrar_module/lib/registrar_module.dart` (the barrel file) — `class_schedule_view.dart` should already be exported there (since `SubjectOption`/`TeacherOption`/`ScheduleEntryModel` already live in this same file and are already reachable via the barrel); if for some reason it isn't, add `export 'pages/dashboard/class_schedule_view.dart';`.

In `lib/data/registrar_repository.dart`, add `SectionOption` to the existing re-export line:

```dart
export 'package:registrar_module/registrar_module.dart'
    show SubjectOption, TeacherOption, SectionOption;
```

- [ ] **Step 4: Add `fetchSections()` to `RegistrarRepository`**

```dart
  Future<List<SectionOption>> fetchSections() async {
    final rows = await _client
        .from('sections')
        .select('id, name, year_level')
        .order('name');
    return (rows as List<dynamic>).map((e) {
      final row = e as Map<String, dynamic>;
      return SectionOption(
        id: row['id'] as String,
        name: row['name'] as String,
        yearLevel: row['year_level'] as int? ?? 1,
      );
    }).toList();
  }
```

- [ ] **Step 5: Run the test, confirm it passes**

Run: `flutter test test/registrar_repository_sections_test.dart` — expect PASS.

- [ ] **Step 6: Run the full suite and analyze**

Run: `flutter test -j 1` — expect all passing except the one pre-existing, unrelated `guidance_counselor_cold_boot_mobile_test.dart` failure.

Run: `flutter analyze lib/data/registrar_repository.dart packages/registrar_module/lib/pages/dashboard/class_schedule_view.dart` — expect no issues.

- [ ] **Step 7: Commit**

```bash
git add lib/data/registrar_repository.dart packages/registrar_module/lib/pages/dashboard/class_schedule_view.dart packages/registrar_module/lib/registrar_module.dart test/registrar_repository_sections_test.dart
git commit -m "feat: add RegistrarRepository.fetchSections"
```

(Only `git add` `registrar_module.dart` if Step 3 actually needed to change it — it likely already exports `class_schedule_view.dart`, in which case there's nothing to stage there.)

---

### Task 5: Class Schedule — real Section dropdown, derived Year Level, real School Year/Term fields

**Files:**
- Modify: `packages/registrar_module/lib/pages/dashboard/class_schedule_view.dart`
- Modify: `packages/registrar_module/lib/pages/dashboard/registrar_dashboard_page.dart`
- Modify: `packages/registrar_module/lib/data/registrar_mock_data.dart`
- Modify: `lib/ui/registrar_connected_page.dart`
- Modify: `lib/data/registrar_repository.dart`

**Interfaces:**
- Consumes: `SectionOption`/`RegistrarRepository.fetchSections()` (Task 4).
- Produces: nothing further in this plan — this is the last task.

**Context — read all three of these files in full before starting, they've each been touched by earlier work in this session and this brief's understanding of their current shape may not be exact:**

`class_schedule_view.dart`'s `_ClassScheduleViewState` currently has purely-local, never-threaded-through-props fields `_educationLevel`/`_yearLevel`/`_section` (strings), each wrapped in a disabled `_NotYetWiredField`. `_handleSaveChanges()` validates `_selectedSubjectId`/`_selectedProfessorId`/room/startTime/endTime/`_selectedDays` and calls `widget.onSaveChanges(subjectId:, professorId:, room:, days:, startTime:, endTime:)` — no section/schoolYear/term at all today.

`registrar_connected_page.dart`'s `_saveClassSchedule` currently calls `repo.fetchDefaultSection()` for the section (a "first available section alphabetically" stand-in) and hardcodes `schoolYear: _currentSchoolYear()` / `term: _defaultTerm` (`'1st Semester'`) — none of these three values come from the form.

- [ ] **Step 1: Replace Year Level/Section stand-ins with a real Section dropdown in `class_schedule_view.dart`**

Add to `ClassScheduleView`'s constructor (alongside `subjectOptions`/`teacherOptions`):

```dart
    this.sectionOptions = const [],
```

```dart
  final List<SectionOption> sectionOptions;
```

Remove `_yearLevel` and `_section` fields from `_ClassScheduleViewState`. Add:

```dart
  String? _selectedSectionId;
```

Add a `_SectionDropdown` widget, matching `_SubjectDropdown`'s exact shape (same file, search for `_SubjectDropdown`'s current definition and mirror it exactly — `DropdownButtonFormField<String>` with `initialValue`/`items`/`onChanged`, a `FieldLabel` above it):

```dart
class _SectionDropdown extends StatelessWidget {
  const _SectionDropdown({
    required this.options,
    required this.selectedId,
    required this.onChanged,
  });

  final List<SectionOption> options;
  final String? selectedId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const FieldLabel('Section'),
        DropdownButtonFormField<String>(
          initialValue: selectedId,
          items: [
            for (final option in options)
              DropdownMenuItem(value: option.id, child: Text(option.name)),
          ],
          onChanged: onChanged,
        ),
      ],
    );
  }
}
```

(If reading `_SubjectDropdown`'s real current definition shows a different actual shape than this brief's reproduction — e.g. a different constructor parameter name, a wrapping widget this brief doesn't know about — use what the file actually has, matching it exactly, not this snippet.)

Replace the two `_NotYetWiredField`-wrapped Year Level/Section widgets (in the `Wrap` inside `_AddClassScheduleCard`'s build method) with:

```dart
              SizedBox(
                width: 370,
                child: _SectionDropdown(
                  options: sectionOptions,
                  selectedId: selectedSectionId,
                  onChanged: onSectionChanged,
                ),
              ),
```

`_AddClassScheduleCard` (the private widget hosting the form) needs `sectionOptions`/`selectedSectionId`/`onSectionChanged` added to its own constructor and threaded down from `_ClassScheduleViewState.build()`, the same way `subjectOptions`/`selectedSubjectId`/`onSubjectChanged` are already threaded — mirror that exact pattern.

Add a small derived-year-level caption directly under the Section dropdown (not a separate interactive control — Year Level is now just a readout of whichever section is selected):

```dart
              if (selectedSectionId != null)
                Builder(builder: (context) {
                  final selected = sectionOptions
                      .where((s) => s.id == selectedSectionId)
                      .firstOrNull;
                  if (selected == null) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Year ${selected.yearLevel}',
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        color: RegistrarColors.mutedText(context),
                      ),
                    ),
                  );
                }),
```

(Place this `if` block directly after the `SizedBox`-wrapped `_SectionDropdown` in the same `Wrap`'s children list, or immediately below the `Wrap` if that reads more naturally once you see the actual surrounding layout — either is fine, it's a small caption, not a structural element.)

Education Level's `_NotYetWiredField`-wrapped `_EducationLevelField` is UNCHANGED — leave it exactly as it is.

Update the explanatory caption text below the first `Wrap` (currently: `'Education Level, Year Level, and Section aren\'t wired to a real section yet — new class sections use the first available section alphabetically regardless of these. Subject and Teacher above are real.'`) to reflect that Section is now real:

```dart
          Text(
            'Education Level isn\'t wired to a real section yet — every '
            'class section is College-level regardless of this field. '
            'Subject, Teacher, and Section above are real.',
            style: GoogleFonts.poppins(
              fontSize: 11,
              fontStyle: FontStyle.italic,
              color: RegistrarColors.mutedText(context),
            ),
          ),
```

- [ ] **Step 2: Add real School Year/Term fields**

Add to `_ClassScheduleViewState`:

```dart
  late final TextEditingController _schoolYearController;
  String _term = '1st Semester';
```

In `initState()`, alongside the existing controller initializations, pre-fill the school year the same way `registrar_connected_page.dart`'s `_currentSchoolYear()` currently derives it (new school year starts in June) — this widget has no access to that private helper, so reproduce the same logic locally:

```dart
    final now = DateTime.now();
    final startYear = now.month >= 6 ? now.year : now.year - 1;
    _schoolYearController =
        TextEditingController(text: '$startYear-${startYear + 1}');
```

Dispose `_schoolYearController` in `dispose()` alongside the other controllers.

Add a `_TermDropdown` (or reuse `_SectionDropdown`'s shape with a fixed 2-item list — simplest is a small dedicated widget, matching this form's other dropdown widgets):

```dart
class _TermDropdown extends StatelessWidget {
  const _TermDropdown({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const FieldLabel('Term'),
        DropdownButtonFormField<String>(
          initialValue: value,
          items: const [
            DropdownMenuItem(value: '1st Semester', child: Text('1st Semester')),
            DropdownMenuItem(value: '2nd Semester', child: Text('2nd Semester')),
          ],
          onChanged: onChanged,
        ),
      ],
    );
  }
}
```

Add a School Year `_LabeledTextField` (same widget already used for Room/Start Time/End Time) and the new `_TermDropdown` to the second `Wrap` in `_AddClassScheduleCard` (alongside Teacher/Room/Start Time/End Time/Days), threading `schoolYearController`/`term`/`onTermChanged` down the same way the other fields are threaded.

- [ ] **Step 3: Update `_handleSaveChanges` and `onSaveChanges`'s signature**

`ClassScheduleView.onSaveChanges`'s function type gains three more required named parameters:

```dart
  final void Function({
    required String subjectId,
    required String professorId,
    required String sectionId,
    required String schoolYear,
    required String term,
    required String room,
    required List<String> days,
    required String startTime,
    required String endTime,
  })? onSaveChanges;
```

`_handleSaveChanges()` validates and passes the three new values, matching its existing validation style (silent no-op on any missing required field — this brief's Task 4's own already-deferred minor finding about this being a silent no-op with no user feedback is UNCHANGED/still out of scope for this task):

```dart
  void _handleSaveChanges() {
    final subjectId = _selectedSubjectId;
    final professorId = _selectedProfessorId;
    final sectionId = _selectedSectionId;
    final schoolYear = _schoolYearController.text.trim();
    final room = _roomController.text.trim();
    final startTime = _startTimeController.text.trim();
    final endTime = _endTimeController.text.trim();
    if (subjectId == null ||
        professorId == null ||
        sectionId == null ||
        schoolYear.isEmpty ||
        room.isEmpty ||
        startTime.isEmpty ||
        endTime.isEmpty ||
        _selectedDays.isEmpty) {
      return;
    }
    widget.onSaveChanges?.call(
      subjectId: subjectId,
      professorId: professorId,
      sectionId: sectionId,
      schoolYear: schoolYear,
      term: _term,
      room: room,
      days: _selectedDays.toList(),
      startTime: startTime,
      endTime: endTime,
    );
  }
```

- [ ] **Step 4: Update `RegistrarDashboardPage`'s `_saveScheduleChanges` and thread `sectionOptions`**

Read `registrar_dashboard_page.dart`'s `_saveScheduleChanges` (already read in Task 3, re-read now since this task changes it further) and its `ClassScheduleView(...)` construction (around line 655-661).

Add `sectionOptions`/`initialSectionOptions` threading to `RegistrarDashboardPage`, matching `subjectOptions`/`initialSubjectOptions`'s exact existing pattern (constructor param, state field seeded in `initState`, synced in `didUpdateWidget`, passed to `ClassScheduleView(...)`).

`_saveScheduleChanges`'s parameter list and its `widget.onSaveClassSchedule?.call(...)` forwarding both gain `sectionId`/`schoolYear`/`term`, matching `_handleSaveChanges`'s new signature exactly:

```dart
  void _saveScheduleChanges({
    required String subjectId,
    required String professorId,
    required String sectionId,
    required String schoolYear,
    required String term,
    required String room,
    required List<String> days,
    required String startTime,
    required String endTime,
  }) {
    final onSaveClassSchedule = widget.onSaveClassSchedule;
    if (onSaveClassSchedule == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Class schedule changes saved.')),
      );
      return;
    }
    onSaveClassSchedule(
      subjectId: subjectId,
      professorId: professorId,
      sectionId: sectionId,
      schoolYear: schoolYear,
      term: term,
      room: room,
      days: days,
      startTime: startTime,
      endTime: endTime,
    );
  }
```

`RegistrarDashboardPage.onSaveClassSchedule`'s own function-type field declaration needs the same three new required named parameters added, matching `_saveScheduleChanges`'s new signature.

- [ ] **Step 5: Add mock fallback for `sectionOptions`**

Read `packages/registrar_module/lib/data/registrar_mock_data.dart` — it already has `getSubjectOptions()`/`getTeacherOptions()` (added alongside the earlier Class Schedule wiring). Add a matching `getSectionOptions()`:

```dart
  static List<SectionOption> getSectionOptions() => const [
        SectionOption(id: 'sec1', name: 'BSIT-3B', yearLevel: 3),
        SectionOption(id: 'sec2', name: 'BSIT-4A', yearLevel: 4),
      ];
```

Wire this as the fallback for `initialSectionOptions` in `RegistrarDashboardPage`'s `initState`, matching `initialSubjectOptions ?? RegistrarMockData.getSubjectOptions()`'s exact pattern.

- [ ] **Step 6: Wire `registrar_connected_page.dart` end-to-end — remove the stand-in, use the real form values**

Read `_saveClassSchedule` (already read in earlier tasks' context, re-read now for its exact current line numbers before editing) and `initState`.

Add `_loadSections()` (matching `_loadClassScheduleOptions()`'s shape) fetching `repo.fetchSections()` into a new `List<SectionOption>? _sectionOptions;` field, call it from `initState`, and pass `initialSectionOptions: _sectionOptions` into `RegistrarDashboardPage(...)`.

Replace `_saveClassSchedule`'s body: remove the `fetchDefaultSection()` call and the "no sections exist" branch entirely (the form now requires a real section selection before `onSaveChanges` ever fires, so this can't happen via the UI anymore), and use the form's real `sectionId`/`schoolYear`/`term` directly:

```dart
  Future<void> _saveClassSchedule({
    required String subjectId,
    required String professorId,
    required String sectionId,
    required String schoolYear,
    required String term,
    required String room,
    required List<String> days,
    required String startTime,
    required String endTime,
  }) async {
    final repo = _registrarRepo;
    if (repo == null) return;
    try {
      await repo.createClassSection(
        subjectId: subjectId,
        sectionId: sectionId,
        professorId: professorId,
        room: room,
        days: days,
        startTime: startTime,
        endTime: endTime,
        schoolYear: schoolYear,
        term: term,
      );
      await _loadScheduleEntries();
      _toast('Class section created.');
    } catch (e) {
      _toast('Could not create class section: $e');
    }
  }
```

- [ ] **Step 7: Remove `fetchDefaultSection` and `_currentSchoolYear`/`_defaultTerm`**

`RegistrarRepository.fetchDefaultSection()` (`lib/data/registrar_repository.dart`) has no remaining callers after Step 6 — delete it entirely (method + its doc comment). `registrar_connected_page.dart`'s `_currentSchoolYear()` helper and `_defaultTerm` constant also have no remaining callers after Step 6 — delete both.

If `test/registrar_repository_class_sections_test.dart` (from the earlier Class Schedule wiring task) references `fetchDefaultSection` anywhere, remove that reference — re-read the test file first to check before assuming.

- [ ] **Step 8: Run the full suite and analyze**

Run: `flutter test -j 1` — expect all passing except the one pre-existing, unrelated `guidance_counselor_cold_boot_mobile_test.dart` failure.

Run: `flutter analyze lib/data/registrar_repository.dart lib/ui/registrar_connected_page.dart packages/registrar_module` — expect no issues.

- [ ] **Step 9: Commit**

```bash
git add lib/data/registrar_repository.dart lib/ui/registrar_connected_page.dart packages/registrar_module/lib/pages/dashboard/class_schedule_view.dart packages/registrar_module/lib/pages/dashboard/registrar_dashboard_page.dart packages/registrar_module/lib/data/registrar_mock_data.dart test/registrar_repository_class_sections_test.dart
git commit -m "feat: wire Class Schedule's Section/School Year/Term to real data"
```

(Only `git add` `test/registrar_repository_class_sections_test.dart` if Step 7 actually needed to change it.)
