# Student & Parent Portal DB Wiring + Good Moral Requests Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire `student_portal_module` (currently entirely mock-data-driven) to real Supabase data for violations, attendance, and schedule, and add a new student/parent-initiated Good Moral Certificate request flow that closes the loop into the Discipline Officer's already-wired queue.

**Architecture:** Follows this repo's established convention exactly — a presentation-only package (`student_portal_module`, already built) wired via a new `StudentPortalConnectedPage` (`lib/ui/`) reading through a new `StudentPortalRepository` (`lib/data/`), same shape as every other dashboard module in this codebase.

**Tech Stack:** Flutter, `supabase_flutter`, existing `student_portal_module`/`registrar_module`/`discipline_officer_module` packages.

**Spec:** `docs/superpowers/specs/2026-09-09-student-portal-db-wiring-design.md`

## Global Constraints

- Attendance wiring is section-level only (`attendance_records`) — per-subject attendance needs a not-yet-built tap-in/tap-out redesign; do not attempt to fake per-subject granularity from section-level data.
- The enrollment tool is a minimal bulk "enroll this section into this class_sections offering" action — not the full irregular-student management UI (moving one student into a different section for one subject).
- No deny/reject action on Good Moral requests — only `'Pending'` and `'Fulfilled'` statuses.
- SQL migrations are written to `supabase/*.sql` files for the user to run manually in the Supabase SQL Editor — never executed automatically by an implementer or agent.
- `profiles.id == students.id == auth.uid()` for a Student session (confirmed via the existing `good_moral_requests_student_select_own` RLS policy) — use this directly, no extra lookup needed to resolve "this student's own id."
- Demo/static accounts have ids like `"u_counselor"` (not valid UUIDs) — guard any Supabase filter using a signed-in user's id the same way `GuidanceCounselorConnectedPage._notifiableUserId` already does (return `null`/skip the real fetch when the id doesn't look like a UUID), so the portal doesn't throw when opened under a demo account.

---

### Task 1: `StudentPortalRepository` — violations + attendance

**Files:**
- Create: `lib/data/student_portal_repository.dart`
- Test: `test/student_portal_repository_test.dart`

**Interfaces:**
- Produces: `StudentPortalRepository(SupabaseClient)`, `Future<List<StudentViolationModel>> fetchViolations(String studentId)`, `Future<List<AttendanceEntry>> fetchAttendance(String studentId, String sectionId, {required DateTime from, required DateTime to})`.
- Consumes: `StudentViolationModel` (`package:student_portal_module/models/violation_models.dart`), `AttendanceEntry`/`AttendanceStatusX.fromDbValue` (`package:student_portal_module/models/attendance_models.dart`) — both already exist, unmodified by this task.

- [ ] **Step 1: Write the failing signature-guard test**

This repo's established convention for repository methods (see `test/students_repository_fetch_page_test.dart`) is a compile-time signature guard — construct the repository with a fake URL and tear off the method against the exact expected function type, without calling it (no real network request).

```dart
// test/student_portal_repository_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:student_portal_module/models/attendance_models.dart';
import 'package:student_portal_module/models/violation_models.dart';
import 'package:capstone_dashboard/data/student_portal_repository.dart';

void main() {
  test('fetchViolations and fetchAttendance have the expected signatures', () {
    final repo = StudentPortalRepository(
      SupabaseClient('https://example.invalid', 'anon-key'),
    );

    final Future<List<StudentViolationModel>> Function(String studentId)
        fetchViolations = repo.fetchViolations;
    expect(fetchViolations, isNotNull);

    final Future<List<AttendanceEntry>> Function(
      String studentId,
      String sectionId, {
      required DateTime from,
      required DateTime to,
    }) fetchAttendance = repo.fetchAttendance;
    expect(fetchAttendance, isNotNull);
  });
}
```

- [ ] **Step 2: Run it, confirm it fails**

Run: `flutter test test/student_portal_repository_test.dart` — expect failure (`student_portal_repository.dart` doesn't exist / `StudentPortalRepository` undefined).

- [ ] **Step 3: Write `lib/data/student_portal_repository.dart`**

`StudentViolationModel`'s constructor takes `{id, title, category, status, dateFiled, description, recordedBy}` directly (not via `.fromJson`, since `student_violations`'s real columns don't match that JSON shape one-to-one — `title`/`category` come from the joined `handbook_offenses` row). `AttendanceEntry` requires non-null `subjectId`/`subjectName`; Task 3 makes those nullable to fit section-level data honestly — this task already writes against the post-Task-3 nullable shape so the two tasks don't conflict.

```dart
import 'package:student_portal_module/models/attendance_models.dart';
import 'package:student_portal_module/models/violation_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Wires `student_portal_module`'s presentation layer to real Supabase data.
/// See `docs/superpowers/specs/2026-09-09-student-portal-db-wiring-design.md`.
class StudentPortalRepository {
  StudentPortalRepository(this._client);

  final SupabaseClient _client;

  /// `student_violations` joined to `handbook_offenses`, excluding archived
  /// rows — matches the same shape `DisciplineRepository` already queries
  /// this table with.
  Future<List<StudentViolationModel>> fetchViolations(String studentId) async {
    final rows = await _client
        .from('student_violations')
        .select('''
          id,
          status,
          created_at,
          incident_notes,
          reported_by,
          handbook_offenses ( description, category )
        ''')
        .eq('student_id', studentId)
        .filter('archived_at', 'is', null)
        .order('created_at', ascending: false);

    return (rows as List<dynamic>).map((e) {
      final row = e as Map<String, dynamic>;
      final offense = row['handbook_offenses'] as Map<String, dynamic>?;
      return StudentViolationModel(
        id: row['id'] as String,
        title: offense?['description'] as String? ?? 'Violation',
        category: ViolationCategoryX.fromDbValue(
          offense?['category'] as String? ?? 'Minor',
        ),
        status: ViolationStatusX.fromDbValue(row['status'] as String),
        dateFiled: DateTime.parse(row['created_at'] as String),
        description: row['incident_notes'] as String? ?? '',
        recordedBy: row['reported_by'] as String? ?? '',
      );
    }).toList();
  }

  /// `attendance_records` is section-level (one status per student per
  /// section per day) — NOT per-subject. See this repo's
  /// docs/superpowers/specs/2026-09-04-irregular-students-schema-design.md,
  /// which explicitly defers true per-subject attendance (tap-in/tap-out +
  /// per-subject validation) to a future, not-yet-built sub-project. Each
  /// returned `AttendanceEntry` has `subjectId`/`subjectName` left null
  /// (see Task 3's model change) rather than inventing a fake subject.
  Future<List<AttendanceEntry>> fetchAttendance(
    String studentId,
    String sectionId, {
    required DateTime from,
    required DateTime to,
  }) async {
    final rows = await _client
        .from('attendance_records')
        .select('session_date, status')
        .eq('student_id', studentId)
        .eq('section_id', sectionId)
        .gte('session_date', from.toIso8601String().substring(0, 10))
        .lte('session_date', to.toIso8601String().substring(0, 10));

    return (rows as List<dynamic>).map((e) {
      final row = e as Map<String, dynamic>;
      return AttendanceEntry(
        date: DateTime.parse(row['session_date'] as String),
        subjectId: null,
        subjectName: null,
        status: AttendanceStatusX.fromDbValue(row['status'] as String),
      );
    }).toList();
  }
}
```

- [ ] **Step 4: Run the test, confirm it passes**

Run: `flutter test test/student_portal_repository_test.dart` — expect this to still FAIL at this point, because Task 3 hasn't made `AttendanceEntry.subjectId`/`subjectName` nullable yet, so `subjectId: null` in Step 3's code won't compile. This is expected and correct — Step 5 (commit) is deliberately skipped until Task 3 lands. Leave the code as-is; do not work around it by inventing placeholder subject values, since that would contradict Task 3's model change and Global Constraints.

- [ ] **Step 5: Commit — deferred**

Do not commit yet. This task's commit happens as part of Task 3's Step 5 (see Task 3), once the model change this code depends on exists and the full test suite (including this file) actually passes. Note this clearly in your task report so the controller doesn't expect a standalone commit here.

---

### Task 2: Make `AttendanceEntry.subjectId`/`subjectName` nullable

**Files:**
- Modify: `packages/student_portal_module/lib/models/attendance_models.dart`
- Modify: `packages/student_portal_module/lib/widgets/day_detail_sheet.dart:121`
- Test: `packages/student_portal_module/test/attendance_models_test.dart`

**Interfaces:**
- Consumes: nothing new.
- Produces: `AttendanceEntry` with `String? subjectId` and `String? subjectName` (previously non-nullable `required`) — Task 1's `fetchAttendance` already depends on this being nullable.

- [ ] **Step 1: Write the failing test**

```dart
// packages/student_portal_module/test/attendance_models_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:student_portal_module/models/attendance_models.dart';

void main() {
  test('AttendanceEntry allows a null subject (section-level attendance)', () {
    final entry = AttendanceEntry(
      date: DateTime(2026, 9, 10),
      subjectId: null,
      subjectName: null,
      status: AttendanceStatus.present,
    );

    expect(entry.subjectId, isNull);
    expect(entry.subjectName, isNull);
  });

  test('fromJson tolerates missing subject_id/subject_name', () {
    final entry = AttendanceEntry.fromJson({
      'session_date': '2026-09-10T00:00:00.000',
      'status': 'present',
    });

    expect(entry.subjectId, isNull);
    expect(entry.subjectName, isNull);
  });
}
```

- [ ] **Step 2: Run it, confirm it fails**

Run: `flutter test packages/student_portal_module/test/attendance_models_test.dart` — expect a compile failure (`subjectId`/`subjectName` are `required`, and `fromJson` does `json['subject_id'] as String` with no `?`, which throws on a missing key).

- [ ] **Step 3: Update `attendance_models.dart`**

```dart
class AttendanceEntry {
  const AttendanceEntry({
    required this.date,
    this.subjectId,
    this.subjectName,
    required this.status,
    this.timeIn,
    this.remarks,
  });

  final DateTime date;

  /// Null for section-level attendance (no per-subject data exists yet —
  /// see StudentPortalRepository.fetchAttendance's doc comment).
  final String? subjectId;
  final String? subjectName;
  final AttendanceStatus status;
  final String? timeIn;
  final String? remarks;

  factory AttendanceEntry.fromJson(Map<String, dynamic> json) {
    return AttendanceEntry(
      date: DateTime.parse(json['session_date'] as String),
      subjectId: json['subject_id'] as String?,
      subjectName: json['subject_name'] as String?,
      status: AttendanceStatusX.fromDbValue(json['status'] as String),
      timeIn: json['time_in'] as String?,
      remarks: json['remarks'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'session_date': date.toIso8601String(),
      'subject_id': subjectId,
      'subject_name': subjectName,
      'status': status.name,
      'time_in': timeIn,
      'remarks': remarks,
    };
  }
}
```

- [ ] **Step 4: Update the one display site**

`day_detail_sheet.dart:121` currently does `Text(entry.subjectName, ...)`, which no longer compiles against a nullable `String?`. Change to:

```dart
                          Text(
                            entry.subjectName ?? 'Daily Attendance',
```

- [ ] **Step 5: Run the tests, confirm everything passes — including Task 1's**

Run: `flutter test packages/student_portal_module/test/attendance_models_test.dart` — expect PASS.

Run: `flutter test test/student_portal_repository_test.dart` (from Task 1) — expect PASS now that the type it depends on is nullable.

Run: `flutter test` (full suite) — confirm nothing else in `student_portal_module` broke (the mock data generator, other widget tests referencing `AttendanceEntry`).

- [ ] **Step 6: Commit (covers Task 1 + Task 2 together)**

```bash
git add lib/data/student_portal_repository.dart test/student_portal_repository_test.dart packages/student_portal_module/lib/models/attendance_models.dart packages/student_portal_module/lib/widgets/day_detail_sheet.dart packages/student_portal_module/test/attendance_models_test.dart
git commit -m "feat: wire student portal violations/attendance to real Supabase data"
```

---

### Task 3: `StudentPortalConnectedPage` — resolve session, wire violations + attendance

**Files:**
- Create: `lib/ui/student_portal_connected_page.dart`
- Modify: `lib/ui/admin/admin_hub_page.dart` (route `SystemModuleId.studentParentPortal` through the new connected page)
- Test: `test/student_portal_connected_page_test.dart`

**Interfaces:**
- Consumes: `StudentPortalRepository` (Task 1), `AppUser`/`AppRole` (`lib/auth/`), `AppEnv.supabaseConfigured` (`lib/env.dart`), `StudentPortalHomePage` (unmodified, already supports `initialViolations`/`initialAttendance`).
- Produces: `StudentPortalConnectedPage({AppUser? currentUser, VoidCallback? onReturnToHub, VoidCallback? onSignOut})`.

- [ ] **Step 1: Write the failing widget test**

```dart
// test/student_portal_connected_page_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:capstone_dashboard/auth/app_role.dart';
import 'package:capstone_dashboard/auth/app_user.dart';
import 'package:capstone_dashboard/ui/student_portal_connected_page.dart';

void main() {
  testWidgets('renders the portal home page without Supabase configured',
      (tester) async {
    const user = AppUser(
      id: 'u_student',
      displayName: 'Demo Student',
      role: AppRole.student,
      username: 'student',
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: StudentPortalConnectedPage(currentUser: user),
      ),
    );
    await tester.pumpAndSettle();

    // AppEnv.supabaseConfigured is false in this test environment, so the
    // page falls back to StudentPortalHomePage's own mock data rather than
    // hanging on a real fetch — same convention as every other connected
    // page in this codebase.
    expect(find.text('Demo Student'), findsWidgets);
  });
}
```

- [ ] **Step 2: Run it, confirm it fails**

Run: `flutter test test/student_portal_connected_page_test.dart` — expect failure (`student_portal_connected_page.dart` doesn't exist).

- [ ] **Step 3: Write `lib/ui/student_portal_connected_page.dart`**

Resolves `studentId`/`sectionId` for a Student session directly (`profiles.id == students.id == auth.uid()`, confirmed by the existing `good_moral_requests` RLS policies), or for a Parent session, looks up their linked child(ren) via `parent_student_links` (same table `students_repository.dart`'s `_selectEmbed` already embeds from the other direction) and auto-selects when there's exactly one.

```dart
import 'package:flutter/material.dart';
import 'package:student_portal_module/student_portal_module.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/app_role.dart';
import '../auth/app_user.dart';
import '../data/student_portal_repository.dart';
import '../env.dart';

/// Wires the presentation-only [StudentPortalHomePage] to Supabase
/// (violations, attendance — see [StudentPortalRepository]). Falls back to
/// the page's own built-in mock data when Supabase isn't configured or the
/// signed-in account is a static demo account (id not a real UUID), same
/// convention every other connected page in this codebase follows.
class StudentPortalConnectedPage extends StatefulWidget {
  const StudentPortalConnectedPage({
    super.key,
    this.currentUser,
    this.onReturnToHub,
    this.onSignOut,
  });

  final AppUser? currentUser;
  final VoidCallback? onReturnToHub;
  final VoidCallback? onSignOut;

  @override
  State<StudentPortalConnectedPage> createState() =>
      _StudentPortalConnectedPageState();
}

class _StudentPortalConnectedPageState
    extends State<StudentPortalConnectedPage> {
  List<StudentViolationModel>? _violations;
  List<AttendanceEntry>? _attendance;

  StudentPortalRepository? get _repo {
    if (!AppEnv.supabaseConfigured) return null;
    return StudentPortalRepository(Supabase.instance.client);
  }

  /// `null` for static demo accounts (ids like "u_student" aren't real
  /// UUIDs and have no backing `students`/`profiles` row) — same guard
  /// `GuidanceCounselorConnectedPage._notifiableUserId` already uses.
  String? get _studentId {
    final user = widget.currentUser;
    if (user == null || user.role != AppRole.student) return null;
    if (user.id.startsWith('u_')) return null;
    return user.id;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = _repo;
    final studentId = _studentId;
    if (repo == null || studentId == null) return;

    try {
      final violations = await repo.fetchViolations(studentId);
      if (mounted) setState(() => _violations = violations);
    } catch (_) {
      // Falls back to the page's own mock data — no error state needed for
      // a read-only preview; matches this repo's convention elsewhere.
    }
  }

  @override
  Widget build(BuildContext context) {
    return StudentPortalHomePage(
      studentName: widget.currentUser?.displayName ?? 'Demo Student',
      onSignOut: widget.onSignOut,
      onReturnToHub: widget.onReturnToHub,
      initialViolations: _violations,
      initialAttendance: _attendance,
    );
  }
}
```

Note: `_attendance` intentionally stays `null` (falls back to mock) in this task — wiring it needs `sectionId`, which requires one extra `students` lookup. Add that lookup and populate `_attendance` for real:

```dart
  Future<void> _load() async {
    final repo = _repo;
    final studentId = _studentId;
    if (repo == null || studentId == null) return;

    try {
      final violations = await repo.fetchViolations(studentId);
      if (mounted) setState(() => _violations = violations);
    } catch (_) {}

    try {
      final studentRow = await Supabase.instance.client
          .from('students')
          .select('section_id')
          .eq('id', studentId)
          .maybeSingle();
      final sectionId = studentRow?['section_id'] as String?;
      if (sectionId == null) return;

      final now = DateTime.now();
      final attendance = await repo.fetchAttendance(
        studentId,
        sectionId,
        from: now.subtract(const Duration(days: 90)),
        to: now,
      );
      if (mounted) setState(() => _attendance = attendance);
    } catch (_) {}
  }
```

Replace the plan's first `_load` sketch with this final version in the actual file — write only this final version, not both.

- [ ] **Step 4: Wire the route in `admin_hub_page.dart`**

Replace the existing direct push (around line 139-147):

```dart
      case SystemModuleId.studentParentPortal:
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (routeContext) => StudentPortalHomePage(
              onReturnToHub: () => Navigator.of(routeContext).pop(),
            ),
          ),
        );
        return;
```

with:

```dart
      case SystemModuleId.studentParentPortal:
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (routeContext) => StudentPortalConnectedPage(
              currentUser: user,
              onReturnToHub: () => Navigator.of(routeContext).pop(),
            ),
          ),
        );
        return;
```

Add the import (`import 'student_portal_connected_page.dart';` — adjust the relative path to match this file's existing import style) and remove the now-unused `StudentPortalHomePage` import if nothing else in this file references it directly (check with a search before removing).

- [ ] **Step 5: Run the tests, confirm everything passes**

Run: `flutter test test/student_portal_connected_page_test.dart` — expect PASS.

Run: `flutter test` (full suite) — this is the point where Task 1's deferred commit and this task's work land together; confirm the full suite is green, including `test/student_portal_repository_test.dart`.

Run: `flutter analyze lib/ui/student_portal_connected_page.dart lib/ui/admin/admin_hub_page.dart lib/data/student_portal_repository.dart` — expect no issues.

- [ ] **Step 6: Commit**

```bash
git add lib/ui/student_portal_connected_page.dart lib/ui/admin/admin_hub_page.dart test/student_portal_connected_page_test.dart
git commit -m "feat: wire Student Portal into the Admin Hub with real violations/attendance"
```

---

### Task 4: Registrar `ClassScheduleView` — real subjects/teachers, real `class_sections` writes

**Files:**
- Modify: `lib/data/registrar_repository.dart`
- Modify: `packages/registrar_module/lib/pages/dashboard/class_schedule_view.dart`
- Modify: `lib/ui/registrar_connected_page.dart`
- Test: `test/registrar_repository_class_sections_test.dart`

**Interfaces:**
- Produces: `RegistrarRepository.fetchSubjects() -> Future<List<SubjectOption>>`, `RegistrarRepository.fetchTeachers() -> Future<List<TeacherOption>>`, `RegistrarRepository.createClassSection({required String subjectId, required String sectionId, required String professorId, required String room, required List<String> days, required String startTime, required String endTime, required String schoolYear, required String term}) -> Future<String>` (returns the new `class_sections.id`).
- Consumes: `SubjectModel`/`TeacherOption` are new small models defined in this task (not from `student_portal_module` — this is registrar-side, a different package).

- [ ] **Step 1: Write the failing signature-guard test**

```dart
// test/registrar_repository_class_sections_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:capstone_dashboard/data/registrar_repository.dart';

void main() {
  test('fetchSubjects, fetchTeachers, createClassSection have expected signatures', () {
    final repo = RegistrarRepository(
      SupabaseClient('https://example.invalid', 'anon-key'),
    );

    final Future<List<SubjectOption>> Function() fetchSubjects =
        repo.fetchSubjects;
    expect(fetchSubjects, isNotNull);

    final Future<List<TeacherOption>> Function() fetchTeachers =
        repo.fetchTeachers;
    expect(fetchTeachers, isNotNull);

    final Future<String> Function({
      required String subjectId,
      required String sectionId,
      required String professorId,
      required String room,
      required List<String> days,
      required String startTime,
      required String endTime,
      required String schoolYear,
      required String term,
    }) createClassSection = repo.createClassSection;
    expect(createClassSection, isNotNull);
  });
}
```

- [ ] **Step 2: Run it, confirm it fails**

Run: `flutter test test/registrar_repository_class_sections_test.dart` — expect failure (`SubjectOption`/`TeacherOption`/the three methods don't exist).

- [ ] **Step 3: Add the models and methods to `lib/data/registrar_repository.dart`**

Add near the top of the file (alongside any existing small option/DTO classes in this file — if none exist, add them just above the `RegistrarRepository` class):

```dart
class SubjectOption {
  const SubjectOption({required this.id, required this.code, required this.title});

  final String id;
  final String code;
  final String title;

  String get label => '$code — $title';
}

class TeacherOption {
  const TeacherOption({required this.id, required this.fullName});

  final String id;
  final String fullName;
}
```

Add inside the `RegistrarRepository` class body:

```dart
  Future<List<SubjectOption>> fetchSubjects() async {
    final rows = await _client
        .from('subjects')
        .select('id, code, title')
        .order('code');
    return (rows as List<dynamic>).map((e) {
      final row = e as Map<String, dynamic>;
      return SubjectOption(
        id: row['id'] as String,
        code: row['code'] as String,
        title: row['title'] as String,
      );
    }).toList();
  }

  Future<List<TeacherOption>> fetchTeachers() async {
    final rows = await _client
        .from('profiles')
        .select('id, first_name, last_name')
        .eq('role', 'Teacher')
        .order('last_name');
    return (rows as List<dynamic>).map((e) {
      final row = e as Map<String, dynamic>;
      final first = (row['first_name'] as String?) ?? '';
      final last = (row['last_name'] as String?) ?? '';
      return TeacherOption(
        id: row['id'] as String,
        fullName: '$first $last'.trim(),
      );
    }).toList();
  }

  /// Creates one `class_sections` offering (a specific subject taught by a
  /// specific professor to a specific home section, on a specific
  /// schedule). See docs/superpowers/specs/2026-09-04-irregular-students-schema-design.md
  /// for the full schema rationale. Returns the new row's id.
  Future<String> createClassSection({
    required String subjectId,
    required String sectionId,
    required String professorId,
    required String room,
    required List<String> days,
    required String startTime,
    required String endTime,
    required String schoolYear,
    required String term,
  }) async {
    final row = await _client
        .from('class_sections')
        .insert({
          'subject_id': subjectId,
          'section_id': sectionId,
          'professor_id': professorId,
          'room': room,
          'schedule_days': days,
          'start_time': startTime,
          'end_time': endTime,
          'school_year': schoolYear,
          'term': term,
        })
        .select('id')
        .single();
    return row['id'] as String;
  }
```

- [ ] **Step 4: Run the test, confirm it passes**

Run: `flutter test test/registrar_repository_class_sections_test.dart` — expect PASS.

- [ ] **Step 5: Wire `ClassScheduleView`'s dropdowns to real data**

Read `packages/registrar_module/lib/pages/dashboard/class_schedule_view.dart` in full before editing (already read once during spec research — re-read now for exact current line numbers, since Task order means other edits may have shifted them).

`ClassScheduleView`'s constructor gains the option lists and selection state (mirroring the existing `educationLevel`/`onEducationLevelChanged` controlled-value pattern exactly):

```dart
class ClassScheduleView extends StatefulWidget {
  const ClassScheduleView({
    super.key,
    required this.entries,
    this.onSaveChanges,
    this.subjectOptions = const [],
    this.teacherOptions = const [],
  });

  final List<ScheduleEntryModel> entries;
  final List<SubjectOption> subjectOptions;
  final List<TeacherOption> teacherOptions;

  /// Called with the assembled form values when "Save Changes" is tapped.
  /// Falls back to no-op when omitted (demo behavior).
  final void Function({
    required String subjectId,
    required String professorId,
    required String room,
    required List<String> days,
    required String startTime,
    required String endTime,
  })? onSaveChanges;
```

(`SubjectOption`/`TeacherOption` come from `lib/data/registrar_repository.dart` — Step 3 above; import them into this file.) `_ClassScheduleViewState` gains matching selection fields (`String? _selectedSubjectId`, `String? _selectedProfessorId`, `_roomController`/`_startTimeController`/`_endTimeController` `TextEditingController`s, initialized in `initState` and disposed in `dispose`), and its `_AddClassScheduleCard(...)` instantiation passes them down plus a `_handleSaveChanges` method that validates the required fields are non-null/non-empty and calls `widget.onSaveChanges?.call(...)` with the assembled values.

`_AddClassScheduleCard` replaces its two hardcoded dropdowns:

```dart
              SizedBox(
                width: 370,
                child: _SubjectDropdown(
                  options: subjectOptions,
                  selectedId: selectedSubjectId,
                  onChanged: onSubjectChanged,
                ),
              ),
```

```dart
              SizedBox(
                width: 370,
                child: _TeacherDropdown(
                  options: teacherOptions,
                  selectedId: selectedProfessorId,
                  onChanged: onProfessorChanged,
                ),
              ),
```

replacing the previous `_LabeledDropdown(label: 'Subject', value: 'Computer Programming 2')` and `_LabeledDropdown(label: 'Teacher', value: 'Mr. Clark Gillerdo')` respectively, with `_AddClassScheduleCard`'s own constructor gaining the matching `subjectOptions`/`teacherOptions`/`selectedSubjectId`/`onSubjectChanged`/`selectedProfessorId`/`onProfessorChanged` parameters (same threading pattern as `selectedDays`/`onDayToggled`). Add two small new private widgets in this file, `_SubjectDropdown` and `_TeacherDropdown`, each a thin wrapper around Flutter's `DropdownButtonFormField` with a `FieldLabel` above it matching `_LabeledDropdown`'s existing layout. Before writing these, check `DropdownField`'s own definition (from `package:dashboard_layout/dashboard_layout.dart`, imported at the top of this file) — if it already accepts `items`/`onChanged` and this plan's read of it (as a fixed-display-`value`-only widget, based only on how `_LabeledDropdown` happens to call it) was wrong, use `DropdownField` directly instead of introducing `DropdownButtonFormField`, for visual consistency with the rest of this form:

```dart
class _SubjectDropdown extends StatelessWidget {
  const _SubjectDropdown({
    required this.options,
    required this.selectedId,
    required this.onChanged,
  });

  final List<SubjectOption> options;
  final String? selectedId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const FieldLabel('Subject'),
        DropdownButtonFormField<String>(
          initialValue: selectedId,
          items: [
            for (final option in options)
              DropdownMenuItem(value: option.id, child: Text(option.label)),
          ],
          onChanged: onChanged,
        ),
      ],
    );
  }
}
```

`_TeacherDropdown` is the same shape, using `TeacherOption.fullName` instead of `.label` and its own `selectedId`/`onChanged`. Room and Time Slot's existing `_LabeledDropdown(label: 'Room', value: 'CL03')` / `_LabeledDropdown(label: 'Time Slot', value: '8:30 AM - 10:00 AM')` become plain `TextField`s wrapped the same way (`FieldLabel` + a bound `TextEditingController`), since there's no existing `rooms`/`time_slots` reference table to populate a dropdown from — free text is the honest minimum here, not a dropdown pretending to have real options behind it.

- [ ] **Step 6: Wire `registrar_connected_page.dart`**

Load `SubjectOption`/`TeacherOption` lists on page init (same pattern as any other list this page already loads), hold the form's current selections in state, and call `RegistrarRepository.createClassSection` from the wired `onSaveChanges`, showing a snackbar on success/failure (matching this file's existing snackbar convention for other save actions).

- [ ] **Step 7: Run the full test suite and analyze**

Run: `flutter test` — expect all passing, no regressions in existing `registrar_module` or `registrar_connected_page` tests.

Run: `flutter analyze lib/data/registrar_repository.dart packages/registrar_module/lib/pages/dashboard/class_schedule_view.dart lib/ui/registrar_connected_page.dart` — expect no issues.

- [ ] **Step 8: Commit**

```bash
git add lib/data/registrar_repository.dart packages/registrar_module/lib/pages/dashboard/class_schedule_view.dart lib/ui/registrar_connected_page.dart test/registrar_repository_class_sections_test.dart
git commit -m "feat: wire Class Schedule tab to real subjects/teachers/class_sections"
```

---

### Task 5: `enroll_section_students` RPC + Enroll Section action

**Files:**
- Create: `supabase/add_enroll_section_rpc.sql`
- Modify: `lib/data/registrar_repository.dart`
- Modify: `packages/registrar_module/lib/pages/dashboard/class_schedule_view.dart`
- Test: `test/registrar_repository_enroll_section_test.dart`

**Interfaces:**
- Produces: `RegistrarRepository.enrollSectionStudents(String classSectionId) -> Future<int>` (returns count of newly-enrolled students).

- [ ] **Step 1: Write the SQL migration**

```sql
-- supabase/add_enroll_section_rpc.sql
--
-- Minimal enrollment tool: bulk-enrolls every currently-active student in
-- a class_sections offering's home section into that offering. Not the
-- full irregular-student enrollment management UI
-- (docs/superpowers/specs/2026-09-04-irregular-students-schema-design.md's
-- deferred "Sub-project 3") — just enough that schedules aren't
-- permanently empty. Idempotent: re-running for the same offering only
-- enrolls students who joined the section since the last run, via the
-- existing enrollments(student_id, class_section_id) unique constraint.
--
-- Run in Supabase SQL Editor, after add_subjects_enrollments_schema.sql.

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

- [ ] **Step 2: Get user approval, then have them run it in Supabase SQL Editor**

Show the exact SQL above and wait for confirmation it ran successfully before continuing (this repo's established convention).

- [ ] **Step 3: Write the failing signature-guard test**

```dart
// test/registrar_repository_enroll_section_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:capstone_dashboard/data/registrar_repository.dart';

void main() {
  test('enrollSectionStudents has the expected signature', () {
    final repo = RegistrarRepository(
      SupabaseClient('https://example.invalid', 'anon-key'),
    );

    final Future<int> Function(String classSectionId) enrollSectionStudents =
        repo.enrollSectionStudents;
    expect(enrollSectionStudents, isNotNull);
  });
}
```

- [ ] **Step 4: Run it, confirm it fails**

Run: `flutter test test/registrar_repository_enroll_section_test.dart` — expect failure (method doesn't exist).

- [ ] **Step 5: Add the method to `RegistrarRepository`**

```dart
  /// Calls the `enroll_section_students` RPC (see
  /// supabase/add_enroll_section_rpc.sql). Returns how many students were
  /// newly enrolled.
  Future<int> enrollSectionStudents(String classSectionId) async {
    final result = await _client.rpc(
      'enroll_section_students',
      params: {'p_class_section_id': classSectionId},
    );
    return result as int;
  }
```

- [ ] **Step 6: Run the test, confirm it passes**

Run: `flutter test test/registrar_repository_enroll_section_test.dart` — expect PASS.

- [ ] **Step 7: Add the "Enroll Section" action to `_ScheduleRow`**

`ClassScheduleView`'s constructor gains one more parameter, threaded the same way `onSaveChanges` already is:

```dart
    this.onEnrollSection,
  });

  final ValueChanged<String>? onEnrollSection;
```

Its `build` method passes this down to each `_ScheduleRow(entry: entry, onEnrollSection: widget.onEnrollSection)` in the `for (final entry in pageEntries) _ScheduleRow(...)` loop. `_ScheduleRow` itself gains the field and a trailing button, added as one more `Expanded` child at the end of its `Row` (after the existing Time column):

```dart
class _ScheduleRow extends StatelessWidget {
  const _ScheduleRow({required this.entry, this.onEnrollSection});

  final ScheduleEntryModel entry;
  final ValueChanged<String>? onEnrollSection;
```

```dart
          IconButton(
            icon: const Icon(Icons.group_add_outlined, size: 18),
            tooltip: 'Enroll this section\'s students',
            onPressed: onEnrollSection == null
                ? null
                : () => onEnrollSection!(entry.id),
          ),
```

`entry.id` is the `class_sections` row's id — Task 4 Step 6 must populate `ScheduleEntryModel.id` from `RegistrarRepository.createClassSection`'s return value when building each row shown in this table (not a client-generated placeholder id); confirm that's how Task 4 wired it before relying on it here — if Task 4 instead left `id` sourced from something else, fix Task 4's wiring to use the real `class_sections` id rather than working around it here, since `enroll_section_students` requires a real `class_sections.id`.

- [ ] **Step 8: Wire it in `registrar_connected_page.dart`**

```dart
onEnrollSection: (classSectionId) async {
  try {
    final count = await _repo!.enrollSectionStudents(classSectionId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$count student(s) enrolled.')),
      );
    }
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Enrollment failed: $e')),
      );
    }
  }
},
```

(Adjust `_repo!` to match however this file already accesses its `RegistrarRepository` instance — check the existing `onSaveChanges` wiring from Task 4 for the exact pattern and reuse it.)

- [ ] **Step 9: Run the full suite and analyze**

Run: `flutter test` — expect all passing.

Run: `flutter analyze lib/data/registrar_repository.dart packages/registrar_module/lib/pages/dashboard/class_schedule_view.dart lib/ui/registrar_connected_page.dart` — expect no issues.

- [ ] **Step 10: Commit**

```bash
git add supabase/add_enroll_section_rpc.sql lib/data/registrar_repository.dart packages/registrar_module/lib/pages/dashboard/class_schedule_view.dart lib/ui/registrar_connected_page.dart test/registrar_repository_enroll_section_test.dart
git commit -m "feat: add minimal Enroll Section tool for class_sections offerings"
```

---

### Task 6: Student Portal "My Schedule" read side

**Files:**
- Create: `packages/student_portal_module/lib/models/schedule_models.dart`
- Create: `packages/student_portal_module/lib/widgets/my_schedule_card.dart`
- Modify: `packages/student_portal_module/lib/pages/student_portal_home_page.dart`
- Modify: `lib/data/student_portal_repository.dart`
- Modify: `lib/ui/student_portal_connected_page.dart`
- Test: `packages/student_portal_module/test/schedule_models_test.dart`
- Test: `test/student_portal_repository_schedule_test.dart`

**Interfaces:**
- Produces: `StudentScheduleEntryModel` (`{id, subjectTitle, professorName, room, days (List<String>), startTime, endTime}`), `MyScheduleCard({required List<StudentScheduleEntryModel> entries})`, `StudentPortalRepository.fetchSchedule(String studentId) -> Future<List<StudentScheduleEntryModel>>`.
- Consumes: `enrollments`/`class_sections`/`subjects` tables (real, from `add_subjects_enrollments_schema.sql`, already exist).

- [ ] **Step 1: Write the failing model test**

```dart
// packages/student_portal_module/test/schedule_models_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:student_portal_module/models/schedule_models.dart';

void main() {
  test('StudentScheduleEntryModel formats a readable days/time summary', () {
    const entry = StudentScheduleEntryModel(
      id: 'cs_1',
      subjectTitle: 'Data Structures and Algorithms',
      professorName: 'R. Santiago',
      room: 'CL03',
      days: ['Mon', 'Wed', 'Fri'],
      startTime: '08:30',
      endTime: '10:00',
    );

    expect(entry.daysLabel, 'Mon, Wed, Fri');
    expect(entry.timeLabel, '08:30 - 10:00');
  });
}
```

- [ ] **Step 2: Run it, confirm it fails**

Run: `flutter test packages/student_portal_module/test/schedule_models_test.dart` — expect failure (file doesn't exist).

- [ ] **Step 3: Write `schedule_models.dart`**

```dart
/// One active enrollment's class_sections offering, reduced to what the
/// student portal's "My Schedule" card needs. Backed by real
/// enrollments/class_sections/subjects data — see
/// StudentPortalRepository.fetchSchedule.
class StudentScheduleEntryModel {
  const StudentScheduleEntryModel({
    required this.id,
    required this.subjectTitle,
    required this.professorName,
    required this.room,
    required this.days,
    required this.startTime,
    required this.endTime,
  });

  final String id;
  final String subjectTitle;
  final String professorName;
  final String room;
  final List<String> days;

  /// 24-hour "HH:mm" as stored (Postgres `time` column, ISO-ish string
  /// once decoded by the Supabase client).
  final String startTime;
  final String endTime;

  String get daysLabel => days.join(', ');
  String get timeLabel => '$startTime - $endTime';
}
```

- [ ] **Step 4: Run the test, confirm it passes**

Run: `flutter test packages/student_portal_module/test/schedule_models_test.dart` — expect PASS.

- [ ] **Step 5: Write `my_schedule_card.dart`**

Read `packages/student_portal_module/lib/widgets/violations_preview_card.dart` first to match its exact card styling (padding, `StudentPortalColors` usage, `GoogleFonts.inter` sizing) — this widget should look like a sibling of that card, not a new visual style.

```dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/schedule_models.dart';
import '../theme/student_portal_colors.dart';
import 'portal_surface_card.dart';
import 'section_header.dart';

/// A compact list of the student's active class offerings — subject,
/// professor, days, time, room. Not a calendar/timetable redesign; each
/// student typically has 4-8 entries, so a plain list fits without needing
/// pagination or a separate full-page view (unlike Violations' "See All").
class MyScheduleCard extends StatelessWidget {
  const MyScheduleCard({super.key, required this.entries});

  final List<StudentScheduleEntryModel> entries;

  @override
  Widget build(BuildContext context) {
    return PortalSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(title: 'My Schedule'),
          const SizedBox(height: 12),
          if (entries.isEmpty)
            Text(
              'No classes enrolled yet.',
              style: GoogleFonts.inter(
                fontSize: 12.5,
                color: StudentPortalColors.textSecondary(context),
              ),
            )
          else
            for (final entry in entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.subjectTitle,
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: StudentPortalColors.textPrimary(context),
                            ),
                          ),
                          Text(
                            entry.professorName,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: StudentPortalColors.textSecondary(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          entry.daysLabel,
                          style: GoogleFonts.inter(fontSize: 12),
                        ),
                        Text(
                          '${entry.timeLabel} · ${entry.room}',
                          style: GoogleFonts.inter(
                            fontSize: 11.5,
                            color: StudentPortalColors.textSecondary(context),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}
```

If `PortalSurfaceCard`/`SectionHeader` take different required parameters than shown here, adjust the constructor calls to match their actual signatures (check both files before finalizing this step) — don't guess if the read in this step contradicts what's written above.

- [ ] **Step 6: Add `initialSchedule` to `StudentPortalHomePage` and render the card**

Add `this.initialSchedule` (`List<StudentScheduleEntryModel>?`) to the constructor and a matching `late final List<StudentScheduleEntryModel> _schedule = widget.initialSchedule ?? const [];` field (no mock generator needed — an empty list is a reasonable default absent a `StudentPortalMockData.schedule` entry; do not add one, since mock data for this wasn't part of the original mock file and inventing new mock content is out of scope here). Render `MyScheduleCard(entries: _schedule)` in the page body, placed near the Violations preview card (read the current `build` method to find a sensible spot consistent with the existing layout's visual grouping).

- [ ] **Step 7: Add `fetchSchedule` to `StudentPortalRepository`**

```dart
  /// Active enrollments -> class_sections -> subjects, for the "My
  /// Schedule" card. See
  /// docs/superpowers/specs/2026-09-04-irregular-students-schema-design.md
  /// for the schema this reads (built, but populated only via the Enroll
  /// Section tool — see registrar_repository.dart's
  /// enrollSectionStudents).
  Future<List<StudentScheduleEntryModel>> fetchSchedule(String studentId) async {
    final rows = await _client
        .from('enrollments')
        .select('''
          class_sections (
            id, room, schedule_days, start_time, end_time,
            subjects ( title ),
            profiles ( first_name, last_name )
          )
        ''')
        .eq('student_id', studentId)
        .eq('status', 'Active');

    return (rows as List<dynamic>)
        .map((e) => (e as Map<String, dynamic>)['class_sections'] as Map<String, dynamic>?)
        .whereType<Map<String, dynamic>>()
        .map((cs) {
      final subject = cs['subjects'] as Map<String, dynamic>?;
      final professor = cs['profiles'] as Map<String, dynamic>?;
      final first = (professor?['first_name'] as String?) ?? '';
      final last = (professor?['last_name'] as String?) ?? '';
      return StudentScheduleEntryModel(
        id: cs['id'] as String,
        subjectTitle: subject?['title'] as String? ?? 'Subject',
        professorName: '$first $last'.trim(),
        room: cs['room'] as String? ?? '',
        days: ((cs['schedule_days'] as List<dynamic>?) ?? const [])
            .cast<String>(),
        startTime: cs['start_time'] as String? ?? '',
        endTime: cs['end_time'] as String? ?? '',
      );
    }).toList();
  }
```

Add the import: `import 'package:student_portal_module/models/schedule_models.dart';` at the top of `student_portal_repository.dart`.

- [ ] **Step 8: Write the failing signature-guard test, then confirm it passes**

```dart
// test/student_portal_repository_schedule_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:student_portal_module/models/schedule_models.dart';
import 'package:capstone_dashboard/data/student_portal_repository.dart';

void main() {
  test('fetchSchedule has the expected signature', () {
    final repo = StudentPortalRepository(
      SupabaseClient('https://example.invalid', 'anon-key'),
    );

    final Future<List<StudentScheduleEntryModel>> Function(String studentId)
        fetchSchedule = repo.fetchSchedule;
    expect(fetchSchedule, isNotNull);
  });
}
```

Run it first to confirm failure, then confirm it passes after Step 7.

- [ ] **Step 9: Wire `fetchSchedule` into `StudentPortalConnectedPage._load`**

Add to the existing `_load` method (from Task 3), inside the same `studentId != null` guard, alongside the attendance fetch:

```dart
    try {
      final schedule = await repo.fetchSchedule(studentId);
      if (mounted) setState(() => _schedule = schedule);
    } catch (_) {}
```

Add the corresponding `List<StudentScheduleEntryModel>? _schedule;` field and pass `initialSchedule: _schedule` into the `StudentPortalHomePage(...)` call in `build`.

- [ ] **Step 10: Run the full suite and analyze**

Run: `flutter test` — expect all passing.

Run: `flutter analyze packages/student_portal_module lib/data/student_portal_repository.dart lib/ui/student_portal_connected_page.dart` — expect no issues.

- [ ] **Step 11: Commit**

```bash
git add packages/student_portal_module/lib/models/schedule_models.dart packages/student_portal_module/lib/widgets/my_schedule_card.dart packages/student_portal_module/lib/pages/student_portal_home_page.dart packages/student_portal_module/test/schedule_models_test.dart lib/data/student_portal_repository.dart lib/ui/student_portal_connected_page.dart test/student_portal_repository_schedule_test.dart
git commit -m "feat: add My Schedule card, wired to real enrollments data"
```

---

### Task 7: Good Moral Certificate requests — schema + student/parent submit

**Files:**
- Create: `supabase/add_good_moral_status_and_insert_policies.sql`
- Create: `packages/student_portal_module/lib/widgets/request_document_dialog.dart`
- Modify: `packages/student_portal_module/lib/pages/student_portal_home_page.dart`
- Modify: `lib/data/student_portal_repository.dart`
- Modify: `lib/ui/student_portal_connected_page.dart`
- Test: `test/student_portal_repository_good_moral_test.dart`

**Interfaces:**
- Produces: `StudentPortalRepository.submitGoodMoralRequest({required String studentId, required String documentType, required String purpose, required String requestedBy, String? remarks}) -> Future<void>`, `StudentPortalRepository.fetchMyGoodMoralRequests(String studentId) -> Future<List<GoodMoralRequestStatus>>`, `GoodMoralRequestStatus` model, `RequestDocumentDialog` widget.

- [ ] **Step 1: Write the SQL migration**

```sql
-- supabase/add_good_moral_status_and_insert_policies.sql
--
-- Adds the status column add_good_moral_requests_schema.sql deliberately
-- left out ("add one once that workflow is actually built") now that the
-- student/parent request + Discipline Officer fulfill workflow exists, plus
-- INSERT policies so a student/parent can create their own request (the
-- table previously only allowed staff to insert).
--
-- Run in Supabase SQL Editor, after add_good_moral_requests_schema.sql.

alter table public.good_moral_requests
  add column if not exists status text not null default 'Pending';

do $$
begin
  alter table public.good_moral_requests
    add constraint good_moral_requests_status_check
    check (status in ('Pending', 'Fulfilled'));
exception
  when duplicate_object then null;
end $$;

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

- [ ] **Step 2: Get user approval, then have them run it in Supabase SQL Editor**

Show the exact SQL above and wait for confirmation before continuing.

- [ ] **Step 3: Write the failing signature-guard test**

```dart
// test/student_portal_repository_good_moral_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:student_portal_module/models/good_moral_request_status.dart';
import 'package:capstone_dashboard/data/student_portal_repository.dart';

void main() {
  test('submitGoodMoralRequest and fetchMyGoodMoralRequests have expected signatures', () {
    final repo = StudentPortalRepository(
      SupabaseClient('https://example.invalid', 'anon-key'),
    );

    final Future<void> Function({
      required String studentId,
      required String documentType,
      required String purpose,
      required String requestedBy,
      String? remarks,
    }) submitGoodMoralRequest = repo.submitGoodMoralRequest;
    expect(submitGoodMoralRequest, isNotNull);

    final Future<List<GoodMoralRequestStatus>> Function(String studentId)
        fetchMyGoodMoralRequests = repo.fetchMyGoodMoralRequests;
    expect(fetchMyGoodMoralRequests, isNotNull);
  });
}
```

- [ ] **Step 4: Run it, confirm it fails**

Run: `flutter test test/student_portal_repository_good_moral_test.dart` — expect failure (nothing exists yet).

- [ ] **Step 5: Write `good_moral_request_status.dart`**

```dart
// packages/student_portal_module/lib/models/good_moral_request_status.dart

/// One of the requester's own Good Moral (or other document) requests and
/// its current fulfillment status — 'Pending' or 'Fulfilled', matching
/// good_moral_requests.status (see
/// supabase/add_good_moral_status_and_insert_policies.sql).
class GoodMoralRequestStatus {
  const GoodMoralRequestStatus({
    required this.id,
    required this.documentType,
    required this.purpose,
    required this.status,
    required this.requestDate,
  });

  final String id;
  final String documentType;
  final String purpose;
  final String status;
  final DateTime requestDate;

  bool get isFulfilled => status == 'Fulfilled';
}
```

- [ ] **Step 6: Add `submitGoodMoralRequest`/`fetchMyGoodMoralRequests` to `StudentPortalRepository`**

```dart
  Future<void> submitGoodMoralRequest({
    required String studentId,
    required String documentType,
    required String purpose,
    required String requestedBy,
    String? remarks,
  }) async {
    await _client.from('good_moral_requests').insert({
      'student_id': studentId,
      'document_type': documentType,
      'purpose': purpose,
      'requested_by': requestedBy,
      'remarks': remarks,
    });
  }

  Future<List<GoodMoralRequestStatus>> fetchMyGoodMoralRequests(
    String studentId,
  ) async {
    final rows = await _client
        .from('good_moral_requests')
        .select('id, document_type, purpose, status, request_date')
        .eq('student_id', studentId)
        .order('request_date', ascending: false);

    return (rows as List<dynamic>).map((e) {
      final row = e as Map<String, dynamic>;
      return GoodMoralRequestStatus(
        id: row['id'] as String,
        documentType: row['document_type'] as String,
        purpose: row['purpose'] as String,
        status: row['status'] as String? ?? 'Pending',
        requestDate: DateTime.parse(row['request_date'] as String),
      );
    }).toList();
  }
```

Add the import: `import 'package:student_portal_module/models/good_moral_request_status.dart';`.

- [ ] **Step 7: Run the test, confirm it passes**

Run: `flutter test test/student_portal_repository_good_moral_test.dart` — expect PASS.

- [ ] **Step 8: Write `request_document_dialog.dart`**

Read `packages/student_portal_module/lib/widgets/violation_detail_sheet.dart` first for this package's existing dialog/sheet styling conventions before writing this.

```dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/student_portal_colors.dart';

/// "Request a Document" form — document type, purpose, optional remarks.
/// Returns the entered values via [onSubmit], or null if the sheet was
/// dismissed without submitting (caller decides what "submit" means —
/// this widget has no Supabase knowledge of its own).
class RequestDocumentDialog extends StatefulWidget {
  const RequestDocumentDialog({super.key, required this.onSubmit});

  final void Function({
    required String documentType,
    required String purpose,
    String? remarks,
  }) onSubmit;

  @override
  State<RequestDocumentDialog> createState() => _RequestDocumentDialogState();
}

class _RequestDocumentDialogState extends State<RequestDocumentDialog> {
  final _documentTypeController =
      TextEditingController(text: 'Good Moral Certificate');
  final _purposeController = TextEditingController();
  final _remarksController = TextEditingController();

  @override
  void dispose() {
    _documentTypeController.dispose();
    _purposeController.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_purposeController.text.trim().isEmpty) return;
    widget.onSubmit(
      documentType: _documentTypeController.text.trim(),
      purpose: _purposeController.text.trim(),
      remarks: _remarksController.text.trim().isEmpty
          ? null
          : _remarksController.text.trim(),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        'Request a Document',
        style: GoogleFonts.inter(fontWeight: FontWeight.w600),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _documentTypeController,
            decoration: const InputDecoration(labelText: 'Document Type'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _purposeController,
            decoration: const InputDecoration(labelText: 'Purpose'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _remarksController,
            decoration:
                const InputDecoration(labelText: 'Remarks (optional)'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(
            backgroundColor: StudentPortalColors.primary(context),
          ),
          child: const Text('Submit Request'),
        ),
      ],
    );
  }
}
```

If `StudentPortalColors.primary` isn't the actual name of this package's accent-color accessor, check `student_portal_colors.dart` first and use whatever the real one is called.

- [ ] **Step 9: Add a "Request a Document" entry point + status list to `StudentPortalHomePage`**

Add to the constructor (alongside `initialSchedule` from Task 6):

```dart
    this.initialGoodMoralRequests,
    this.onSubmitGoodMoralRequest,
  });

  final List<GoodMoralRequestStatus>? initialGoodMoralRequests;

  /// Called with the submitted form values when RequestDocumentDialog's
  /// "Submit Request" is tapped. Null means demo mode — the dialog still
  /// opens and closes, nothing is persisted.
  final void Function({
    required String documentType,
    required String purpose,
    String? remarks,
  })? onSubmitGoodMoralRequest;
```

And to `_StudentPortalHomePageState`:

```dart
  late List<GoodMoralRequestStatus> _goodMoralRequests =
      widget.initialGoodMoralRequests ?? const [];

  void _openRequestDocumentDialog() {
    showDialog<void>(
      context: context,
      builder: (_) => RequestDocumentDialog(
        onSubmit: ({required documentType, required purpose, remarks}) {
          widget.onSubmitGoodMoralRequest?.call(
            documentType: documentType,
            purpose: purpose,
            remarks: remarks,
          );
        },
      ),
    );
  }
```

Add a button calling `_openRequestDocumentDialog` near the profile/settings area (matching this file's existing `_showEmailMenu`/`_showNotificationsMenu` popover-trigger pattern — read that section of `build` first to match its exact icon-button styling). Below the `MyScheduleCard` added in Task 6, render the status list using `StudentPortalColors`' existing status-badge palette (the same `StatusBadge` widget `status_badge.dart` already defines — read that file first rather than hand-rolling new badge styling):

```dart
              PortalSurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionHeader(title: 'My Document Requests'),
                    const SizedBox(height: 12),
                    if (_goodMoralRequests.isEmpty)
                      Text(
                        'No document requests yet.',
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          color: StudentPortalColors.textSecondary(context),
                        ),
                      )
                    else
                      for (final request in _goodMoralRequests)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${request.documentType} — ${request.purpose}',
                                  style: GoogleFonts.inter(fontSize: 13),
                                ),
                              ),
                              StatusBadge(
                                label: request.status,
                                isPositive: request.isFulfilled,
                              ),
                            ],
                          ),
                        ),
                  ],
                ),
              ),
```

Check `StatusBadge`'s actual constructor in `status_badge.dart` before finalizing this snippet — `isPositive` is this plan's guess at how it distinguishes color (Fulfilled vs. Pending); use whatever parameter that widget really exposes.

- [ ] **Step 10: Wire submission + status refresh in `StudentPortalConnectedPage`**

```dart
  Future<void> _submitGoodMoralRequest({
    required String documentType,
    required String purpose,
    String? remarks,
  }) async {
    final repo = _repo;
    final studentId = _studentId;
    if (repo == null || studentId == null) return;

    await repo.submitGoodMoralRequest(
      studentId: studentId,
      documentType: documentType,
      purpose: purpose,
      requestedBy: widget.currentUser?.displayName ?? 'Student',
      remarks: remarks,
    );

    final requests = await repo.fetchMyGoodMoralRequests(studentId);
    if (mounted) setState(() => _goodMoralRequests = requests);
  }
```

Add the `List<GoodMoralRequestStatus>? _goodMoralRequests;` field, fetch it inside `_load` the same way schedule/attendance already are, pass `initialGoodMoralRequests: _goodMoralRequests` into `StudentPortalHomePage(...)`, and pass `_submitGoodMoralRequest` down as whatever callback `StudentPortalHomePage`'s Step 9 addition expects (match the exact param name chosen there).

- [ ] **Step 11: Run the full suite and analyze**

Run: `flutter test` — expect all passing.

Run: `flutter analyze packages/student_portal_module lib/data/student_portal_repository.dart lib/ui/student_portal_connected_page.dart` — expect no issues.

- [ ] **Step 12: Commit**

```bash
git add supabase/add_good_moral_status_and_insert_policies.sql packages/student_portal_module/lib/models/good_moral_request_status.dart packages/student_portal_module/lib/widgets/request_document_dialog.dart packages/student_portal_module/lib/pages/student_portal_home_page.dart lib/data/student_portal_repository.dart lib/ui/student_portal_connected_page.dart test/student_portal_repository_good_moral_test.dart
git commit -m "feat: let students/parents request a Good Moral Certificate"
```

---

### Task 8: Mark Good Moral requests Fulfilled on certificate generation

**Files:**
- Modify: `lib/data/discipline_repository.dart`
- Modify: `lib/ui/discipline_officer_connected_page.dart`
- Test: `test/discipline_repository_mark_fulfilled_test.dart`

**Interfaces:**
- Produces: `DisciplineRepository.markGoodMoralRequestFulfilled(String requestId) -> Future<void>`.
- Consumes: `GoodMoralSelectedStudent.sourceSubTab`/`sourceId` (`packages/discipline_officer_module/lib/models/good_moral_models.dart`, unmodified, already exists).

- [ ] **Step 1: Write the failing signature-guard test**

```dart
// test/discipline_repository_mark_fulfilled_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:capstone_dashboard/data/discipline_repository.dart';

void main() {
  test('markGoodMoralRequestFulfilled has the expected signature', () {
    final repo = DisciplineRepository(
      SupabaseClient('https://example.invalid', 'anon-key'),
    );

    final Future<void> Function(String requestId) markFulfilled =
        repo.markGoodMoralRequestFulfilled;
    expect(markFulfilled, isNotNull);
  });
}
```

- [ ] **Step 2: Run it, confirm it fails**

Run: `flutter test test/discipline_repository_mark_fulfilled_test.dart` — expect failure (method doesn't exist).

- [ ] **Step 3: Add the method to `DisciplineRepository`**

```dart
  /// Marks a good_moral_requests row Fulfilled — called after a
  /// certificate is successfully generated for a request-sourced selection
  /// (see DisciplineOfficerConnectedPage._generateCertificate). Requires
  /// supabase/add_good_moral_status_and_insert_policies.sql to have been
  /// run (adds the status column this updates).
  Future<void> markGoodMoralRequestFulfilled(String requestId) async {
    await _client
        .from('good_moral_requests')
        .update({'status': 'Fulfilled'})
        .eq('id', requestId);
  }
```

- [ ] **Step 4: Run the test, confirm it passes**

Run: `flutter test test/discipline_repository_mark_fulfilled_test.dart` — expect PASS.

- [ ] **Step 5: Wire it into `_generateCertificate`**

Read `lib/ui/discipline_officer_connected_page.dart`'s `_generateCertificate` method in full (already read once during spec research — re-read now for the exact current end of the method, since the document-building code shown then was truncated). Add, at the very end of the method (after the certificate is successfully built/downloaded, inside the same success path — not inside a catch block), guarded on the selection's source:

```dart
    if (selected.sourceSubTab == GoodMoralSubTab.requests) {
      final repo = _repo;
      if (repo != null) {
        await repo.markGoodMoralRequestFulfilled(selected.sourceId);
        await _loadGoodMoralRequests();
      }
    }
```

`_loadGoodMoralRequests()` should call the same `fetchGoodMoralRequests()` + `controller.setRequests(...)` sequence this page's existing `_load` method already uses for its initial load — extract that into a small private method if it isn't one already, so this step can call it directly rather than duplicating the fetch-and-set logic inline. Match `_repo`'s actual getter name in this file (confirm it during the re-read in this step rather than assuming `_repo`).

- [ ] **Step 6: Run the full suite and analyze**

Run: `flutter test` — expect all passing.

Run: `flutter analyze lib/data/discipline_repository.dart lib/ui/discipline_officer_connected_page.dart` — expect no issues.

- [ ] **Step 7: Commit**

```bash
git add lib/data/discipline_repository.dart lib/ui/discipline_officer_connected_page.dart test/discipline_repository_mark_fulfilled_test.dart
git commit -m "feat: mark Good Moral requests Fulfilled when a certificate is generated"
```
