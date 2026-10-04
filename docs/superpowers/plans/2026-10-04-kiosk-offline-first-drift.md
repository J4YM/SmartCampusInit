# Kiosk Offline-First (Drift) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The Windows kiosk keeps identifying cards, recording attendance taps, filing violation reports/slips and listing offenses with no internet, and syncs everything automatically when connectivity returns.

**Architecture:** A new pure-Dart/Drift package `packages/kiosk_offline` holds a SQLite cache of reference data, a Dart port of the `record_rfid_tap` rules, and an ordered outbox that replays writes through a `KioskRemote` interface. The root app implements `KioskRemote` on top of the existing Supabase repositories (`lib/kiosk/supabase_kiosk_remote.dart`) and the kiosk scan host calls the offline service, falling back to today's direct-Supabase code when the service is unavailable (web, DB open failure). Online, taps/slips still go straight to the server first; they only fall back to the local path on a transient failure or an already-non-empty outbox.

**Tech Stack:** Flutter (Windows desktop), Drift + SQLite (`sqlite3_flutter_libs`), `path_provider`, existing `supabase_flutter` repositories, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-10-04-kiosk-offline-first-drift-design.md` (this plan amends three points of it — see "Spec amendments" below).

## Spec amendments (decided while planning; the spec file is updated in Task 10)

1. **Online taps/slips go to the server first** (3 s timeout for taps, 5 s for slips) when the outbox is empty, and mirror the server's answer locally. The spec said "decide locally always"; that would regress today's behaviour whenever a student also tapped at another floor reader, because the kiosk only knows its own taps. The local rules decide only when offline, when the call fails transiently, or when older entries are still queued (so server-side ordering is preserved).
2. **Reference refresh is always a full replace** (not delta + periodic full). It is simpler, handles deletions/reassigned cards, and the tables are hundreds of rows.
3. **Outbox order is the autoincrement `id`**, not `tapped_at` (same order; `tapped_at` lives in the payload).

## Global Constraints

- Windows-only kiosk; the web build (Netlify, Flutter 3.24.5 / Dart 3.5.4) must keep compiling and must not import `dart:ffi`/SQLite: the facade `packages/kiosk_offline/lib/kiosk_offline.dart` uses a conditional export (`if (dart.library.io)`) and the web stub returns `null`.
- Pinned direct dependency versions must have a Dart SDK lower bound of at most 3.5.4 (Task 1 selects them; root `pubspec.yaml` has a history of Netlify resolve breakage).
- `tapOutMinWait` defaults to **1 hour**; dev override via `--dart-define=KIOSK_TAP_OUT_MIN_WAIT_SECONDS=5`. It must match the live `record_rfid_tap`.
- School day = `((tapped_at in Manila UTC+8) + 5 h 30 min).date`, i.e. rollover at 6:30 PM Manila. Manila has no DST, so a fixed +8 h offset is used (no timezone package).
- Debounce is 5 s; one tap-in and one tap-out per school day; unrecognised cards always log `in`.
- Server messages reused verbatim: `Please wait at least 1 hour after tapping in before tapping out.` and `You have already tapped in and out for today.`
- `kiosk_offline` must not depend on `supabase_flutter` or on the root app (the root app depends on it).
- Generated Drift code (`*.g.dart`) is committed; `drift_dev`/`build_runner` are dev-dependencies of `kiosk_offline` only.
- Commit messages end with `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.
- Execute in an isolated worktree (the working tree has unrelated uncommitted changes) — see `superpowers:using-git-worktrees`.

## Review Focus

Inputs/conditions the spec implies but does not spell out, most likely first. Each has a pinning test in the named task.

1. Student tapped at another floor reader while this kiosk was offline: on replay the server's direction differs from the provisional one → local row must be corrected to the server's direction (Task 5).
2. Reference pull fails, or returns zero students while the cache is populated → cache must NOT be wiped (Task 6).
3. App crashes after the server accepted a tap but before the outbox row is deleted → replay of the same tap is harmless and leaves one consistent local direction (Task 5).
4. Kiosk PC clock/timezone is not Manila (e.g. UTC or UTC−5) at the 6:30 PM rollover → school day still computed in Manila time (Task 2).
5. SQLite file cannot be opened/created (locked, read-only profile, corrupt) → host falls back to today's direct-Supabase behaviour instead of a dead kiosk (Task 8).

## File Structure

```
packages/kiosk_offline/
  pubspec.yaml
  analysis_options.yaml
  README.md                         manual offline checklist + sqlite3.dll note
  lib/kiosk_offline.dart            public facade (conditional export)
  lib/src/models.dart               pure DTOs: OfflineStudent/Staff/Offense/Teacher, SlipSubmission, ReferenceData, SyncStatus, OutboxDiagnostic
  lib/src/kiosk_remote.dart         KioskRemote interface, RemoteRejected, RemoteTapResult
  lib/src/kiosk_offline_api.dart    abstract KioskOffline, TapOutcome, TapRejectedException
  lib/src/tap_rules.dart            schoolDayOf, PriorTap, TapDecision, TapRules (pure)
  lib/src/kiosk_database.dart       Drift tables + queries
  lib/src/kiosk_database.g.dart     generated
  lib/src/tap_engine.dart           TapEngine
  lib/src/outbox.dart               Outbox + DrainReport
  lib/src/connectivity_monitor.dart ConnectivityMonitor
  lib/src/reference_sync.dart       ReferenceSync
  lib/src/sync_coordinator.dart     SyncCoordinator
  lib/src/kiosk_offline_impl.dart   KioskOfflineImpl (io only)
  lib/src/open_io.dart              openKioskOffline (io)
  lib/src/open_stub.dart            openKioskOffline (web → null)
  test/support/fake_remote.dart     FakeRemote + helpers
  test/*_test.dart
lib/kiosk/supabase_kiosk_remote.dart   root: KioskRemote over Supabase repos
lib/kiosk/offline_status_chip.dart     root: status chip + diagnostics dialog
lib/kiosk/capstone_kiosk_scan_host.dart  modified
test/supabase_kiosk_remote_test.dart, test/offline_status_chip_test.dart, test/open_offline_or_null_test.dart
pubspec.yaml                             modified (path dep)
```

---

### Task 1: Package scaffold, pinned dependencies, SQLite smoke test (gate)

This is a gate: if SQLite cannot load on this Windows machine or a pin cannot be satisfied, stop and resolve it before any other task.

**Files:**
- Create: `packages/kiosk_offline/pubspec.yaml`, `packages/kiosk_offline/analysis_options.yaml`, `packages/kiosk_offline/lib/kiosk_offline.dart`, `packages/kiosk_offline/test/sqlite_smoke_test.dart`
- Create (scratchpad, not committed): `pick_pins.dart`
- Modify: `pubspec.yaml` (root, dependencies list, after `kiosk:`)

**Interfaces:**
- Produces: package `kiosk_offline` resolvable from the root app; a working `flutter test` in the package on Windows.

- [ ] **Step 1: Pick versions whose SDK floor is ≤ 3.5.4**

Write this to the scratchpad as `pick_pins.dart` and run it:

```dart
import 'dart:convert';
import 'dart:io';

List<int> _v(String s) =>
    s.split('.').map((e) => int.parse(e.split(RegExp(r'[-+]')).first)).toList();

bool _le(List<int> a, List<int> b) {
  for (var i = 0; i < 3; i++) {
    if (a[i] != b[i]) return a[i] < b[i];
  }
  return true;
}

Future<void> main(List<String> pkgs) async {
  final client = HttpClient();
  for (final pkg in pkgs) {
    final req = await client.getUrl(Uri.parse('https://pub.dev/api/packages/$pkg'));
    final body = jsonDecode(await (await req.close()).transform(utf8.decoder).join())
        as Map<String, dynamic>;
    final versions = (body['versions'] as List).cast<Map<String, dynamic>>();
    String? best;
    for (final ver in versions.reversed) {
      final v = ver['version'] as String;
      if (v.contains('-')) continue; // skip pre-releases
      final sdk = ver['pubspec']['environment']['sdk'] as String;
      final m = RegExp(r'(\d+\.\d+\.\d+)').firstMatch(sdk);
      if (m != null && _le(_v(m.group(1)!), [3, 5, 4])) {
        best = v;
        break;
      }
    }
    stdout.writeln('$pkg -> $best');
  }
  client.close();
}
```

Run: `dart run <scratchpad>/pick_pins.dart drift drift_dev sqlite3 sqlite3_flutter_libs build_runner path_provider`
Expected: one line per package with a version (not `null`). Record them as `DRIFT`, `DRIFT_DEV`, `SQLITE3`, `SQLITE3_LIBS`, `BUILD_RUNNER`, `PATH_PROVIDER` for the next step. If `drift` and `drift_dev` come back on different minor lines, use the highest `drift_dev` that lists the chosen `drift` in its changelog as compatible (they are released in lockstep; pick matching minors).

- [ ] **Step 2: Create the package pubspec**

`packages/kiosk_offline/pubspec.yaml` (substitute the recorded versions, using exact pins `x.y.z`):

```yaml
name: kiosk_offline
description: Offline-first cache, tap rules and sync outbox for the Windows kiosk.
publish_to: none
version: 0.1.0

environment:
  sdk: ">=3.3.0 <4.0.0"

dependencies:
  flutter:
    sdk: flutter
  drift: DRIFT
  sqlite3_flutter_libs: SQLITE3_LIBS
  path_provider: PATH_PROVIDER

dev_dependencies:
  flutter_test:
    sdk: flutter
  sqlite3: SQLITE3
  drift_dev: DRIFT_DEV
  build_runner: BUILD_RUNNER
  flutter_lints: ^4.0.0
```

`packages/kiosk_offline/analysis_options.yaml`:

```yaml
include: package:flutter_lints/flutter.yaml
analyzer:
  exclude:
    - "**/*.g.dart"
```

`packages/kiosk_offline/lib/kiosk_offline.dart` (placeholder replaced in Task 7):

```dart
library kiosk_offline;
```

- [ ] **Step 3: Write the smoke test**

`packages/kiosk_offline/test/sqlite_smoke_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('native SQLite loads and runs a query', () {
    final db = sqlite3.openInMemory();
    addTearDown(db.dispose);
    final rows = db.select('select 1 as one');
    expect(rows.single['one'], 1);
  });
}
```

- [ ] **Step 4: Resolve and run**

Run (from `packages/kiosk_offline`): `flutter pub get` then `flutter test test/sqlite_smoke_test.dart`
Expected: PASS.
If it fails with `Failed to load dynamic library 'sqlite3.dll'`: download the 64-bit `sqlite3.dll` from sqlite.org's "Precompiled Binaries for Windows" into `packages/kiosk_offline/`, add `packages/kiosk_offline/sqlite3.dll` to the root `.gitignore`, note it in the README (Task 10), and re-run. (This only affects `flutter test` on the dev machine; the app bundle gets SQLite via `sqlite3_flutter_libs`.)

- [ ] **Step 5: Add the path dependency to the root app and resolve**

In root `pubspec.yaml`, after the `kiosk:` entry add:

```yaml
  kiosk_offline:
    path: packages/kiosk_offline
```

Run (repo root): `flutter pub get`
Expected: resolves with no version-conflict errors.

- [ ] **Step 6: Commit**

```bash
git add packages/kiosk_offline pubspec.yaml pubspec.lock .gitignore
git commit -m "feat(kiosk_offline): scaffold package with pinned drift/sqlite deps" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 2: `TapRules` — pure port of `record_rfid_tap`

**Files:**
- Create: `packages/kiosk_offline/lib/src/tap_rules.dart`
- Test: `packages/kiosk_offline/test/tap_rules_test.dart`

**Interfaces:**
- Produces:
  - `String schoolDayOf(DateTime instant)` → `'YYYY-MM-DD'`
  - `class PriorTap { const PriorTap({required String direction, required DateTime tappedAt}); }`
  - `sealed class TapDecision`; `TapAccepted(direction)`, `TapEchoed(direction)`, `TapDenied(message)`
  - `class TapRules { const TapRules({Duration tapOutMinWait = 1h, Duration debounce = 5s}); TapDecision decide({required DateTime tappedAt, required bool studentKnown, PriorTap? lastTapToday}); }`

- [ ] **Step 1: Write the failing tests**

`packages/kiosk_offline/test/tap_rules_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kiosk_offline/src/tap_rules.dart';

DateTime t(String iso) => DateTime.parse(iso); // offsets in the string make these exact instants

void main() {
  group('schoolDayOf', () {
    test('18:29 Manila stays on the same school day', () {
      expect(schoolDayOf(t('2026-10-05T18:29:00+08:00')), '2026-10-05');
    });

    test('18:30 Manila rolls over to the next school day', () {
      expect(schoolDayOf(t('2026-10-05T18:30:00+08:00')), '2026-10-06');
    });

    test('is independent of the machine timezone (UTC-5 clock at rollover)', () {
      // Same instants as above, expressed on a UTC-5 wall clock.
      expect(schoolDayOf(t('2026-10-05T05:29:00-05:00')), '2026-10-05');
      expect(schoolDayOf(t('2026-10-05T05:30:00-05:00')), '2026-10-06');
    });

    test('early-morning Manila tap belongs to that calendar day', () {
      expect(schoolDayOf(t('2026-10-05T07:00:00+08:00')), '2026-10-05');
    });
  });

  group('TapRules.decide', () {
    const rules = TapRules();
    final base = t('2026-10-05T08:00:00+08:00');

    test('first tap of the day is in', () {
      final d = rules.decide(tappedAt: base, studentKnown: true);
      expect(d, isA<TapAccepted>().having((a) => a.direction, 'direction', 'in'));
    });

    test('unrecognised card always logs in, ignoring history', () {
      final d = rules.decide(
        tappedAt: base,
        studentKnown: false,
        lastTapToday: PriorTap(direction: 'out', tappedAt: base),
      );
      expect(d, isA<TapAccepted>().having((a) => a.direction, 'direction', 'in'));
    });

    test('double tap within 5 s echoes the previous tap', () {
      final d = rules.decide(
        tappedAt: base.add(const Duration(seconds: 3)),
        studentKnown: true,
        lastTapToday: PriorTap(direction: 'in', tappedAt: base),
      );
      expect(d, isA<TapEchoed>().having((e) => e.direction, 'direction', 'in'));
    });

    test('tap-out before the minimum wait is denied with the server message', () {
      final d = rules.decide(
        tappedAt: base.add(const Duration(minutes: 59)),
        studentKnown: true,
        lastTapToday: PriorTap(direction: 'in', tappedAt: base),
      );
      expect(
        d,
        isA<TapDenied>().having(
          (x) => x.message,
          'message',
          'Please wait at least 1 hour after tapping in before tapping out.',
        ),
      );
    });

    test('tap-out at exactly the minimum wait is accepted', () {
      final d = rules.decide(
        tappedAt: base.add(const Duration(hours: 1)),
        studentKnown: true,
        lastTapToday: PriorTap(direction: 'in', tappedAt: base),
      );
      expect(d, isA<TapAccepted>().having((a) => a.direction, 'direction', 'out'));
    });

    test('third tap of the day is denied', () {
      final d = rules.decide(
        tappedAt: base.add(const Duration(hours: 3)),
        studentKnown: true,
        lastTapToday: PriorTap(
          direction: 'out',
          tappedAt: base.add(const Duration(hours: 2)),
        ),
      );
      expect(
        d,
        isA<TapDenied>().having(
          (x) => x.message,
          'message',
          'You have already tapped in and out for today.',
        ),
      );
    });

    test('dev wait of 5 s is honoured and worded in seconds', () {
      const dev = TapRules(tapOutMinWait: Duration(seconds: 10));
      final denied = dev.decide(
        tappedAt: base.add(const Duration(seconds: 6)),
        studentKnown: true,
        lastTapToday: PriorTap(direction: 'in', tappedAt: base),
      );
      expect(
        denied,
        isA<TapDenied>().having((x) => x.message, 'message',
            'Please wait at least 10 seconds after tapping in before tapping out.'),
      );
      final ok = dev.decide(
        tappedAt: base.add(const Duration(seconds: 10)),
        studentKnown: true,
        lastTapToday: PriorTap(direction: 'in', tappedAt: base),
      );
      expect(ok, isA<TapAccepted>());
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run (in `packages/kiosk_offline`): `flutter test test/tap_rules_test.dart`
Expected: FAIL — `tap_rules.dart` not found.

- [ ] **Step 3: Implement**

`packages/kiosk_offline/lib/src/tap_rules.dart`:

```dart
/// Pure-Dart port of the decision rules in `public.record_rfid_tap`
/// (supabase/fix_rfid_school_day_timezone.sql). Keep in lock-step with that
/// function: a SQL rule change needs a matching change here and in the
/// shared vectors in test/tap_rules_test.dart.
const Duration _manilaOffset = Duration(hours: 8); // Asia/Manila, no DST
const Duration _schoolDayShift = Duration(hours: 5, minutes: 30);

/// The school day a tap belongs to: Manila wall-clock shifted by 5 h 30 min,
/// so the day rolls over at 6:30 PM Manila, not midnight. Independent of the
/// machine's own timezone.
String schoolDayOf(DateTime instant) {
  final s = instant.toUtc().add(_manilaOffset + _schoolDayShift);
  String two(int n) => n.toString().padLeft(2, '0');
  return '${s.year.toString().padLeft(4, '0')}-${two(s.month)}-${two(s.day)}';
}

/// The student's latest tap on the same school day.
class PriorTap {
  const PriorTap({required this.direction, required this.tappedAt});

  /// `'in'` or `'out'`.
  final String direction;
  final DateTime tappedAt;
}

sealed class TapDecision {
  const TapDecision();
}

/// Record a new tap with this direction.
final class TapAccepted extends TapDecision {
  const TapAccepted(this.direction);
  final String direction;
}

/// Accidental double tap: echo the previous tap, record nothing new.
final class TapEchoed extends TapDecision {
  const TapEchoed(this.direction);
  final String direction;
}

/// Refused by a business rule; [message] is a complete student-facing sentence.
final class TapDenied extends TapDecision {
  const TapDenied(this.message);
  final String message;
}

class TapRules {
  const TapRules({
    this.tapOutMinWait = const Duration(hours: 1),
    this.debounce = const Duration(seconds: 5),
  });

  /// Minimum time between tap-in and tap-out. Must match the live SQL.
  final Duration tapOutMinWait;
  final Duration debounce;

  String get _waitLabel {
    final secs = tapOutMinWait.inSeconds;
    if (secs % 3600 == 0) {
      final h = secs ~/ 3600;
      return h == 1 ? '1 hour' : '$h hours';
    }
    return '$secs seconds';
  }

  TapDecision decide({
    required DateTime tappedAt,
    required bool studentKnown,
    PriorTap? lastTapToday,
  }) {
    // Unrecognised card: the rules only apply to a resolved student.
    if (!studentKnown) return const TapAccepted('in');

    final last = lastTapToday;
    if (last == null) return const TapAccepted('in');

    final elapsed = tappedAt.difference(last.tappedAt);
    if (elapsed < debounce) return TapEchoed(last.direction);

    if (last.direction == 'in') {
      if (elapsed < tapOutMinWait) {
        return TapDenied(
          'Please wait at least $_waitLabel after tapping in before tapping out.',
        );
      }
      return const TapAccepted('out');
    }
    return const TapDenied('You have already tapped in and out for today.');
  }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/tap_rules_test.dart`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/kiosk_offline/lib/src/tap_rules.dart packages/kiosk_offline/test/tap_rules_test.dart
git commit -m "feat(kiosk_offline): TapRules port of record_rfid_tap with shared vectors" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Shared models, `KioskRemote` interface and `KioskDatabase`

**Files:**
- Create: `lib/src/models.dart`, `lib/src/kiosk_remote.dart`, `lib/src/kiosk_database.dart` (+ generated `kiosk_database.g.dart`) under `packages/kiosk_offline/`
- Test: `packages/kiosk_offline/test/kiosk_database_test.dart`

**Interfaces:**
- Consumes: `schoolDayOf` from Task 2.
- Produces (all in `package:kiosk_offline/src/...`):
  - `models.dart`:
    - `OfflineStudent({id, rfidUid, fullName, studentNumber, gradeSection, course?})`
    - `OfflineStaff({id, rfidCardId, fullName, role})`
    - `OfflineOffense({id, label, category?})`
    - `OfflineTeacher({id, fullName})`
    - `ReferenceData({students, staff, offenses, teachers})`
    - `SlipSubmission({slipId, studentId, reportedBy, offenseIds, isEscalated=false, notes?, professorId?})` with `toJson()` / `SlipSubmission.fromJson(Map<String,dynamic>)`
    - `SyncStatus({online, pending, rejected})` (value equality)
    - `OutboxDiagnostic({id, type, status, attempts, createdAt, lastError?})`
  - `kiosk_remote.dart`:
    - `class RemoteRejected implements Exception { RemoteRejected(String message); final String message; }`
    - `class RemoteTapResult({tapId, studentId?, direction, tappedAt})`
    - `abstract class KioskRemote { Future<RemoteTapResult> recordTap({required String readerUsbSerial, required String rfidUid, required DateTime tappedAt}); Future<void> submitSlip(SlipSubmission slip); Future<ReferenceData> fetchReferenceData(); Future<bool> ping(); }`
  - `kiosk_database.dart`: `class KioskDatabase extends _$KioskDatabase` with
    - `Future<OfflineStudent?> studentByRfid(String uid)`, `studentById(String id)`, `Future<List<OfflineStudent>> searchStudents(String numberPrefix, {int limit = 8})`
    - `Future<OfflineStaff?> staffByCard(String cardId)`
    - `Future<List<OfflineOffense>> offenses()`, `Future<List<OfflineTeacher>> teachers()`
    - `Future<void> replaceReference(ReferenceData data)`, `Future<int> cachedStudentCount()`
    - `Future<String?> getMeta(String key)`, `Future<void> setMeta(String key, String value)`
    - `Future<int> insertLocalTap({required String studentId, required String direction, required DateTime tappedAt})`, `Future<LocalTapRow?> lastTapOnDay(String studentId, String schoolDay)`, `Future<void> setLocalTapDirection(int id, String direction)`, `Future<void> deleteLocalTap(int id)`
    - `Future<int> enqueue(String type, String payloadJson, DateTime now)`, `Future<OutboxRow?> nextPending()`, `Future<void> deleteOutbox(int id)`, `Future<void> recordAttempt(int id, String error)`, `Future<void> markRejected(int id, String message)`, `Future<int> pendingCount()`, `Future<int> rejectedCount()`, `Future<List<OutboxDiagnostic>> diagnostics()`
    - row types `LocalTapRow(id, studentId, direction, tappedAt, schoolDay)`, `OutboxRow(id, type, payload, createdAt, attempts, status, lastError)`

- [ ] **Step 1: Write the pure model and interface files**

`packages/kiosk_offline/lib/src/models.dart`:

```dart
class OfflineStudent {
  const OfflineStudent({
    required this.id,
    required this.rfidUid,
    required this.fullName,
    required this.studentNumber,
    required this.gradeSection,
    this.course,
  });

  /// `students.id`.
  final String id;

  /// `students.rfid_uid`; empty when the student has no card assigned.
  final String rfidUid;
  final String fullName;
  final String studentNumber;
  final String gradeSection;
  final String? course;
}

class OfflineStaff {
  const OfflineStaff({
    required this.id,
    required this.rfidCardId,
    required this.fullName,
    required this.role,
  });

  final String id;
  final String rfidCardId;
  final String fullName;
  final String role;
}

class OfflineOffense {
  const OfflineOffense({required this.id, required this.label, this.category});
  final String id;
  final String label;
  final String? category;
}

class OfflineTeacher {
  const OfflineTeacher({required this.id, required this.fullName});
  final String id;
  final String fullName;
}

class ReferenceData {
  const ReferenceData({
    required this.students,
    required this.staff,
    required this.offenses,
    required this.teachers,
  });

  final List<OfflineStudent> students;
  final List<OfflineStaff> staff;
  final List<OfflineOffense> offenses;
  final List<OfflineTeacher> teachers;
}

/// Everything `submit_admission_slip` needs; stored as JSON in the outbox.
class SlipSubmission {
  const SlipSubmission({
    required this.slipId,
    required this.studentId,
    required this.reportedBy,
    required this.offenseIds,
    this.isEscalated = false,
    this.notes,
    this.professorId,
  });

  final String slipId;
  final String studentId;
  final String reportedBy;
  final List<String> offenseIds;
  final bool isEscalated;
  final String? notes;
  final String? professorId;

  Map<String, dynamic> toJson() => {
        'slipId': slipId,
        'studentId': studentId,
        'reportedBy': reportedBy,
        'offenseIds': offenseIds,
        'isEscalated': isEscalated,
        'notes': notes,
        'professorId': professorId,
      };

  factory SlipSubmission.fromJson(Map<String, dynamic> j) => SlipSubmission(
        slipId: j['slipId'] as String,
        studentId: j['studentId'] as String,
        reportedBy: j['reportedBy'] as String,
        offenseIds: (j['offenseIds'] as List<dynamic>).cast<String>(),
        isEscalated: j['isEscalated'] as bool? ?? false,
        notes: j['notes'] as String?,
        professorId: j['professorId'] as String?,
      );
}

class SyncStatus {
  const SyncStatus({
    required this.online,
    required this.pending,
    required this.rejected,
  });

  final bool online;
  final int pending;
  final int rejected;

  @override
  bool operator ==(Object other) =>
      other is SyncStatus &&
      other.online == online &&
      other.pending == pending &&
      other.rejected == rejected;

  @override
  int get hashCode => Object.hash(online, pending, rejected);
}

/// One outbox row as shown in the kiosk diagnostics dialog.
class OutboxDiagnostic {
  const OutboxDiagnostic({
    required this.id,
    required this.type,
    required this.status,
    required this.attempts,
    required this.createdAt,
    this.lastError,
  });

  final int id;

  /// `'tap'` or `'slip'`.
  final String type;

  /// `'pending'` or `'rejected'`.
  final String status;
  final int attempts;
  final DateTime createdAt;
  final String? lastError;
}
```

`packages/kiosk_offline/lib/src/kiosk_remote.dart`:

```dart
import 'models.dart';

/// The server refused this write for a business/permanent reason (rule
/// violation, unknown or deactivated reader, permission). Retrying will not
/// help. Anything else a [KioskRemote] throws is treated as transient.
class RemoteRejected implements Exception {
  RemoteRejected(this.message);
  final String message;

  @override
  String toString() => message;
}

class RemoteTapResult {
  const RemoteTapResult({
    required this.tapId,
    required this.studentId,
    required this.direction,
    required this.tappedAt,
  });

  final String tapId;

  /// Null when the card matches no student (the tap is still logged).
  final String? studentId;

  /// `'in'` or `'out'`, as decided by the server.
  final String direction;
  final DateTime tappedAt;
}

/// Everything the kiosk needs from the server. Implemented in the root app
/// over Supabase; faked in tests.
abstract class KioskRemote {
  /// `record_rfid_tap` with the original [tappedAt].
  Future<RemoteTapResult> recordTap({
    required String readerUsbSerial,
    required String rfidUid,
    required DateTime tappedAt,
  });

  /// `submit_admission_slip`. A duplicate slip id must return normally.
  Future<void> submitSlip(SlipSubmission slip);

  Future<ReferenceData> fetchReferenceData();

  /// True when the server is reachable.
  Future<bool> ping();
}
```

- [ ] **Step 2: Write the failing database tests**

`packages/kiosk_offline/test/kiosk_database_test.dart`:

```dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiosk_offline/src/kiosk_database.dart';
import 'package:kiosk_offline/src/models.dart';

ReferenceData ref({List<OfflineStudent>? students}) => ReferenceData(
      students: students ??
          const [
            OfflineStudent(
              id: 's1',
              rfidUid: 'UID-1',
              fullName: 'Ana Cruz',
              studentNumber: '2024-0001',
              gradeSection: '1st Year - BSIT-1A',
              course: 'BS Information Technology',
            ),
            OfflineStudent(
              id: 's2',
              rfidUid: '',
              fullName: 'Ben Diaz',
              studentNumber: '2024-0002',
              gradeSection: '1st Year - BSIT-1A',
            ),
          ],
      staff: const [
        OfflineStaff(id: 'p1', rfidCardId: 'CARD-1', fullName: 'Sam Guard', role: 'Security'),
      ],
      offenses: const [OfflineOffense(id: 'o1', label: 'Late', category: 'Minor')],
      teachers: const [OfflineTeacher(id: 't1', fullName: 'Tess Lim')],
    );

void main() {
  late KioskDatabase db;
  setUp(() => db = KioskDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('reference data round-trips and lookups trim the uid', () async {
    await db.replaceReference(ref());
    expect((await db.studentByRfid('  UID-1 '))?.fullName, 'Ana Cruz');
    expect(await db.studentByRfid(''), isNull);
    expect(await db.studentByRfid('nope'), isNull);
    expect((await db.studentById('s2'))?.studentNumber, '2024-0002');
    expect((await db.staffByCard('CARD-1'))?.role, 'Security');
    expect((await db.offenses()).single.label, 'Late');
    expect((await db.teachers()).single.fullName, 'Tess Lim');
  });

  test('a student with no card is never matched by an empty uid', () async {
    await db.replaceReference(ref());
    expect(await db.studentByRfid(''), isNull);
  });

  test('replaceReference drops rows that are no longer on the server', () async {
    await db.replaceReference(ref());
    await db.replaceReference(ref(students: const [
      OfflineStudent(
        id: 's3',
        rfidUid: 'UID-3',
        fullName: 'Cy Eve',
        studentNumber: '2024-0003',
        gradeSection: '2nd Year - BSIT-2A',
      ),
    ]));
    expect(await db.studentByRfid('UID-1'), isNull);
    expect((await db.studentByRfid('UID-3'))?.fullName, 'Cy Eve');
    expect(await db.cachedStudentCount(), 1);
  });

  test('searchStudents matches the student-number prefix and honours limit', () async {
    await db.replaceReference(ref());
    final hits = await db.searchStudents('2024-000');
    expect(hits.map((s) => s.id), ['s1', 's2']);
    expect(await db.searchStudents('2024-000', limit: 1), hasLength(1));
    expect(await db.searchStudents('   '), isEmpty);
  });

  test('lastTapOnDay returns the latest tap for that student and day only', () async {
    final at = DateTime.parse('2026-10-05T08:00:00+08:00');
    await db.insertLocalTap(studentId: 's1', direction: 'in', tappedAt: at);
    await db.insertLocalTap(
      studentId: 's1',
      direction: 'out',
      tappedAt: at.add(const Duration(hours: 2)),
    );
    await db.insertLocalTap(
      studentId: 's2',
      direction: 'in',
      tappedAt: at.add(const Duration(hours: 3)),
    );
    final last = await db.lastTapOnDay('s1', '2026-10-05');
    expect(last?.direction, 'out');
    expect(await db.lastTapOnDay('s1', '2026-10-06'), isNull);
  });

  test('setLocalTapDirection and deleteLocalTap', () async {
    final at = DateTime.parse('2026-10-05T08:00:00+08:00');
    final id = await db.insertLocalTap(studentId: 's1', direction: 'in', tappedAt: at);
    await db.setLocalTapDirection(id, 'out');
    expect((await db.lastTapOnDay('s1', '2026-10-05'))?.direction, 'out');
    await db.deleteLocalTap(id);
    expect(await db.lastTapOnDay('s1', '2026-10-05'), isNull);
  });

  test('outbox returns pending rows oldest-first and skips rejected', () async {
    final now = DateTime.utc(2026, 10, 5);
    final a = await db.enqueue('tap', '{"n":1}', now);
    final b = await db.enqueue('tap', '{"n":2}', now);
    expect((await db.nextPending())?.id, a);
    await db.markRejected(a, 'nope');
    expect((await db.nextPending())?.id, b);
    expect(await db.pendingCount(), 1);
    expect(await db.rejectedCount(), 1);
    await db.recordAttempt(b, 'boom');
    final row = await db.nextPending();
    expect(row?.attempts, 1);
    expect(row?.lastError, 'boom');
    await db.deleteOutbox(b);
    expect(await db.nextPending(), isNull);
  });

  test('diagnostics lists pending and rejected rows with their errors', () async {
    final now = DateTime.utc(2026, 10, 5);
    final a = await db.enqueue('slip', '{}', now);
    await db.markRejected(a, 'bad slip');
    final b = await db.enqueue('tap', '{}', now);
    await db.recordAttempt(b, 'offline');
    final d = await db.diagnostics();
    expect(d.map((e) => (e.type, e.status, e.lastError)), [
      ('slip', 'rejected', 'bad slip'),
      ('tap', 'pending', 'offline'),
    ]);
  });

  test('meta get/set overwrites', () async {
    expect(await db.getMeta('k'), isNull);
    await db.setMeta('k', 'a');
    await db.setMeta('k', 'b');
    expect(await db.getMeta('k'), 'b');
  });
}
```

- [ ] **Step 3: Run to verify it fails**

Run: `flutter test test/kiosk_database_test.dart`
Expected: FAIL — `kiosk_database.dart` not found.

- [ ] **Step 4: Implement the database**

`packages/kiosk_offline/lib/src/kiosk_database.dart`:

```dart
import 'package:drift/drift.dart';

import 'models.dart';
import 'tap_rules.dart';

part 'kiosk_database.g.dart';

@DataClassName('CachedStudentRow')
class CachedStudents extends Table {
  TextColumn get id => text()();
  TextColumn get rfidUid => text()();
  TextColumn get fullName => text()();
  TextColumn get studentNumber => text()();
  TextColumn get gradeSection => text()();
  TextColumn get course => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('CachedStaffRow')
class CachedStaff extends Table {
  TextColumn get id => text()();
  TextColumn get rfidCardId => text()();
  TextColumn get fullName => text()();
  TextColumn get role => text()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('CachedOffenseRow')
class CachedOffenses extends Table {
  TextColumn get id => text()();
  TextColumn get label => text()();
  TextColumn get category => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('CachedTeacherRow')
class CachedTeachers extends Table {
  TextColumn get id => text()();
  TextColumn get fullName => text()();

  @override
  Set<Column> get primaryKey => {id};
}

/// This kiosk's own taps for known students — the input to the offline rules.
@DataClassName('LocalTapRow')
class LocalTaps extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get studentId => text()();
  TextColumn get direction => text()();
  DateTimeColumn get tappedAt => dateTime()();
  TextColumn get schoolDay => text()();
}

/// Writes waiting to reach the server. Drained in `id` order.
@DataClassName('OutboxRow')
class OutboxEntries extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// `'tap'` or `'slip'`.
  TextColumn get type => text()();
  TextColumn get payload => text()();
  DateTimeColumn get createdAt => dateTime()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();

  /// `'pending'` or `'rejected'`.
  TextColumn get status => text().withDefault(const Constant('pending'))();
  TextColumn get lastError => text().nullable()();
}

@DataClassName('SyncMetaRow')
class SyncMeta extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(tables: [
  CachedStudents,
  CachedStaff,
  CachedOffenses,
  CachedTeachers,
  LocalTaps,
  OutboxEntries,
  SyncMeta,
])
class KioskDatabase extends _$KioskDatabase {
  KioskDatabase(super.e);

  @override
  int get schemaVersion => 1;

  // ---- reference cache ----------------------------------------------------

  OfflineStudent _student(CachedStudentRow r) => OfflineStudent(
        id: r.id,
        rfidUid: r.rfidUid,
        fullName: r.fullName,
        studentNumber: r.studentNumber,
        gradeSection: r.gradeSection,
        course: r.course,
      );

  Future<OfflineStudent?> studentByRfid(String uid) async {
    final key = uid.trim();
    if (key.isEmpty) return null;
    final row = await (select(cachedStudents)
          ..where((t) => t.rfidUid.equals(key))
          ..limit(1))
        .getSingleOrNull();
    return row == null ? null : _student(row);
  }

  Future<OfflineStudent?> studentById(String id) async {
    final row = await (select(cachedStudents)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    return row == null ? null : _student(row);
  }

  Future<List<OfflineStudent>> searchStudents(
    String numberPrefix, {
    int limit = 8,
  }) async {
    final q = numberPrefix.trim();
    if (q.isEmpty) return const [];
    final rows = await (select(cachedStudents)
          ..where((t) => t.studentNumber.like('$q%'))
          ..orderBy([(t) => OrderingTerm.asc(t.studentNumber)])
          ..limit(limit))
        .get();
    return rows.map(_student).toList();
  }

  Future<OfflineStaff?> staffByCard(String cardId) async {
    final key = cardId.trim();
    if (key.isEmpty) return null;
    final row = await (select(cachedStaff)
          ..where((t) => t.rfidCardId.equals(key))
          ..limit(1))
        .getSingleOrNull();
    return row == null
        ? null
        : OfflineStaff(
            id: row.id,
            rfidCardId: row.rfidCardId,
            fullName: row.fullName,
            role: row.role,
          );
  }

  Future<List<OfflineOffense>> offenses() async {
    final rows = await (select(cachedOffenses)
          ..orderBy([(t) => OrderingTerm.asc(t.label)]))
        .get();
    return [
      for (final r in rows)
        OfflineOffense(id: r.id, label: r.label, category: r.category),
    ];
  }

  Future<List<OfflineTeacher>> teachers() async {
    final rows = await select(cachedTeachers).get();
    return [for (final r in rows) OfflineTeacher(id: r.id, fullName: r.fullName)];
  }

  Future<int> cachedStudentCount() async {
    final c = cachedStudents.id.count();
    final q = selectOnly(cachedStudents)..addColumns([c]);
    return (await q.getSingle()).read(c) ?? 0;
  }

  /// Atomically replaces every cache table with [data].
  Future<void> replaceReference(ReferenceData data) async {
    await transaction(() async {
      await delete(cachedStudents).go();
      await delete(cachedStaff).go();
      await delete(cachedOffenses).go();
      await delete(cachedTeachers).go();
      await batch((b) {
        b.insertAll(cachedStudents, [
          for (final s in data.students)
            CachedStudentRowCompanion.insert(
              id: s.id,
              rfidUid: s.rfidUid.trim(),
              fullName: s.fullName,
              studentNumber: s.studentNumber,
              gradeSection: s.gradeSection,
              course: Value(s.course),
            ),
        ]);
        b.insertAll(cachedStaff, [
          for (final s in data.staff)
            CachedStaffRowCompanion.insert(
              id: s.id,
              rfidCardId: s.rfidCardId.trim(),
              fullName: s.fullName,
              role: s.role,
            ),
        ]);
        b.insertAll(cachedOffenses, [
          for (final o in data.offenses)
            CachedOffenseRowCompanion.insert(
              id: o.id,
              label: o.label,
              category: Value(o.category),
            ),
        ]);
        b.insertAll(cachedTeachers, [
          for (final t in data.teachers)
            CachedTeacherRowCompanion.insert(id: t.id, fullName: t.fullName),
        ]);
      });
    });
  }

  // ---- meta ---------------------------------------------------------------

  Future<String?> getMeta(String key) async {
    final row = await (select(syncMeta)..where((t) => t.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  Future<void> setMeta(String key, String value) => into(syncMeta)
      .insertOnConflictUpdate(SyncMetaRowCompanion.insert(key: key, value: value));

  // ---- local taps ---------------------------------------------------------

  Future<int> insertLocalTap({
    required String studentId,
    required String direction,
    required DateTime tappedAt,
  }) =>
      into(localTaps).insert(LocalTapRowCompanion.insert(
        studentId: studentId,
        direction: direction,
        tappedAt: tappedAt,
        schoolDay: schoolDayOf(tappedAt),
      ));

  Future<LocalTapRow?> lastTapOnDay(String studentId, String schoolDay) =>
      (select(localTaps)
            ..where((t) =>
                t.studentId.equals(studentId) & t.schoolDay.equals(schoolDay))
            ..orderBy([(t) => OrderingTerm.desc(t.tappedAt)])
            ..limit(1))
          .getSingleOrNull();

  Future<void> setLocalTapDirection(int id, String direction) =>
      (update(localTaps)..where((t) => t.id.equals(id)))
          .write(LocalTapRowCompanion(direction: Value(direction)));

  Future<void> deleteLocalTap(int id) =>
      (delete(localTaps)..where((t) => t.id.equals(id))).go();

  // ---- outbox -------------------------------------------------------------

  Future<int> enqueue(String type, String payloadJson, DateTime now) =>
      into(outboxEntries).insert(OutboxRowCompanion.insert(
        type: type,
        payload: payloadJson,
        createdAt: now,
      ));

  Future<OutboxRow?> nextPending() => (select(outboxEntries)
        ..where((t) => t.status.equals('pending'))
        ..orderBy([(t) => OrderingTerm.asc(t.id)])
        ..limit(1))
      .getSingleOrNull();

  Future<void> deleteOutbox(int id) =>
      (delete(outboxEntries)..where((t) => t.id.equals(id))).go();

  Future<void> recordAttempt(int id, String error) async {
    final row = await (select(outboxEntries)..where((t) => t.id.equals(id)))
        .getSingle();
    await (update(outboxEntries)..where((t) => t.id.equals(id))).write(
      OutboxRowCompanion(
        attempts: Value(row.attempts + 1),
        lastError: Value(error),
      ),
    );
  }

  Future<void> markRejected(int id, String message) =>
      (update(outboxEntries)..where((t) => t.id.equals(id))).write(
        OutboxRowCompanion(
          status: const Value('rejected'),
          lastError: Value(message),
        ),
      );

  Future<int> _count(String status) async {
    final c = outboxEntries.id.count();
    final q = selectOnly(outboxEntries)
      ..addColumns([c])
      ..where(outboxEntries.status.equals(status));
    return (await q.getSingle()).read(c) ?? 0;
  }

  Future<int> pendingCount() => _count('pending');
  Future<int> rejectedCount() => _count('rejected');

  Future<List<OutboxDiagnostic>> diagnostics() async {
    final rows = await (select(outboxEntries)
          ..orderBy([(t) => OrderingTerm.asc(t.id)]))
        .get();
    return [
      for (final r in rows)
        OutboxDiagnostic(
          id: r.id,
          type: r.type,
          status: r.status,
          attempts: r.attempts,
          createdAt: r.createdAt,
          lastError: r.lastError,
        ),
    ];
  }
}
```

- [ ] **Step 5: Generate the Drift code**

Run (in `packages/kiosk_offline`): `dart run build_runner build --delete-conflicting-outputs`
Expected: `lib/src/kiosk_database.g.dart` created. If the generator names a companion differently from `<RowName>Companion` (e.g. `CachedStudentsCompanion`), rename the references in `kiosk_database.dart` to match the generated file — the row class names set by `@DataClassName` are authoritative.

- [ ] **Step 6: Run to verify it passes**

Run: `flutter test test/kiosk_database_test.dart`
Expected: all PASS.

- [ ] **Step 7: Commit**

```bash
git add packages/kiosk_offline/lib/src/models.dart packages/kiosk_offline/lib/src/kiosk_remote.dart packages/kiosk_offline/lib/src/kiosk_database.dart packages/kiosk_offline/lib/src/kiosk_database.g.dart packages/kiosk_offline/test/kiosk_database_test.dart
git commit -m "feat(kiosk_offline): Drift database, DTOs and KioskRemote interface" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Test fake and `TapEngine`

**Files:**
- Create: `packages/kiosk_offline/test/support/fake_remote.dart`, `packages/kiosk_offline/lib/src/kiosk_offline_api.dart`, `packages/kiosk_offline/lib/src/tap_engine.dart`
- Test: `packages/kiosk_offline/test/tap_engine_test.dart`

**Interfaces:**
- Consumes: `KioskDatabase` methods, `TapRules`, `schoolDayOf`, `KioskRemote`, `RemoteRejected`, `RemoteTapResult` (Tasks 2–3).
- Produces:
  - `kiosk_offline_api.dart`: `class TapRejectedException implements Exception { TapRejectedException(String message); final String message; }`; `class TapOutcome({required String direction, required String? studentId, required OfflineStudent? student})`
  - `TapEngine({required KioskDatabase db, required KioskRemote remote, required TapRules rules, required String readerUsbSerial, required bool Function() isOnline, void Function()? onTransientFailure, DateTime Function()? now, Duration remoteTimeout = const Duration(seconds: 3)})` with `Future<TapOutcome> recordTap(String rfidUid)`.
  - Outbox `tap` payload JSON: `{"readerUsbSerial": String, "rfidUid": String, "tappedAt": ISO-8601 UTC String, "localTapId": int?}`.
  - `FakeRemote implements KioskRemote` (test support) with public fields: `List<({String serial, String uid, DateTime at})> taps`, `List<SlipSubmission> slips`, `Object? tapError`, `Object? slipError`, `Object? referenceError`, `ReferenceData? reference`, `bool pingResult`, `int referenceFetches`, `String Function(String uid, DateTime at)? directionFor`, `String? Function(String uid)? studentIdFor`.

- [ ] **Step 1: Write the fake remote**

`packages/kiosk_offline/test/support/fake_remote.dart`:

```dart
import 'package:kiosk_offline/src/kiosk_remote.dart';
import 'package:kiosk_offline/src/models.dart';

class FakeRemote implements KioskRemote {
  final taps = <({String serial, String uid, DateTime at})>[];
  final slips = <SlipSubmission>[];
  Object? tapError;
  Object? slipError;
  Object? referenceError;
  ReferenceData? reference;
  bool pingResult = true;
  int referenceFetches = 0;
  String Function(String uid, DateTime at)? directionFor;
  String? Function(String uid)? studentIdFor;

  @override
  Future<RemoteTapResult> recordTap({
    required String readerUsbSerial,
    required String rfidUid,
    required DateTime tappedAt,
  }) async {
    final err = tapError;
    if (err != null) throw err;
    taps.add((serial: readerUsbSerial, uid: rfidUid, at: tappedAt));
    return RemoteTapResult(
      tapId: 'tap-${taps.length}',
      studentId: studentIdFor?.call(rfidUid),
      direction: directionFor?.call(rfidUid, tappedAt) ?? 'in',
      tappedAt: tappedAt,
    );
  }

  @override
  Future<void> submitSlip(SlipSubmission slip) async {
    final err = slipError;
    if (err != null) throw err;
    slips.add(slip);
  }

  @override
  Future<ReferenceData> fetchReferenceData() async {
    referenceFetches++;
    final err = referenceError;
    if (err != null) throw err;
    return reference ??
        const ReferenceData(students: [], staff: [], offenses: [], teachers: []);
  }

  @override
  Future<bool> ping() async => pingResult;
}
```

- [ ] **Step 2: Write the API types**

`packages/kiosk_offline/lib/src/kiosk_offline_api.dart` (the `KioskOffline` interface is added in Task 7; define only the tap types now):

```dart
import 'models.dart';

/// A tap refused by a business rule — locally (offline rules) or by the
/// server. [message] is a complete, student-facing sentence.
class TapRejectedException implements Exception {
  TapRejectedException(this.message);
  final String message;

  @override
  String toString() => message;
}

class TapOutcome {
  const TapOutcome({
    required this.direction,
    required this.studentId,
    required this.student,
  });

  /// `'in'` or `'out'`.
  final String direction;

  /// Set when the card belongs to a student the server (or cache) recognised.
  final String? studentId;

  /// Cached details, or null when the card is unrecognised or the student is
  /// not in the cache yet (even though [studentId] may be set).
  final OfflineStudent? student;
}
```

- [ ] **Step 3: Write the failing engine tests**

`packages/kiosk_offline/test/tap_engine_test.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiosk_offline/src/kiosk_database.dart';
import 'package:kiosk_offline/src/kiosk_offline_api.dart';
import 'package:kiosk_offline/src/kiosk_remote.dart';
import 'package:kiosk_offline/src/models.dart';
import 'package:kiosk_offline/src/tap_engine.dart';
import 'package:kiosk_offline/src/tap_rules.dart';

import 'support/fake_remote.dart';

void main() {
  late KioskDatabase db;
  late FakeRemote remote;
  late DateTime now;
  late bool online;
  late int transientFailures;
  late TapEngine engine;

  setUp(() async {
    db = KioskDatabase(NativeDatabase.memory());
    await db.replaceReference(const ReferenceData(
      students: [
        OfflineStudent(
          id: 's1',
          rfidUid: 'UID-1',
          fullName: 'Ana Cruz',
          studentNumber: '2024-0001',
          gradeSection: '1st Year - BSIT-1A',
        ),
      ],
      staff: [],
      offenses: [],
      teachers: [],
    ));
    remote = FakeRemote();
    now = DateTime.parse('2026-10-05T08:00:00+08:00');
    online = false;
    transientFailures = 0;
    engine = TapEngine(
      db: db,
      remote: remote,
      rules: const TapRules(),
      readerUsbSerial: 'KIOSK-MAIN-001',
      isOnline: () => online,
      onTransientFailure: () => transientFailures++,
      now: () => now,
    );
  });

  tearDown(() => db.close());

  group('offline', () {
    test('first tap is in, queued with its true timestamp and a local tap', () async {
      final out = await engine.recordTap('UID-1');
      expect(out.direction, 'in');
      expect(out.student?.fullName, 'Ana Cruz');
      final entry = (await db.nextPending())!;
      expect(entry.type, 'tap');
      final p = jsonDecode(entry.payload) as Map<String, dynamic>;
      expect(p['readerUsbSerial'], 'KIOSK-MAIN-001');
      expect(p['rfidUid'], 'UID-1');
      expect(DateTime.parse(p['tappedAt'] as String).isAtSameMomentAs(now), isTrue);
      expect(p['localTapId'], isA<int>());
      expect(remote.taps, isEmpty);
    });

    test('double tap within 5 s echoes and queues nothing new', () async {
      await engine.recordTap('UID-1');
      now = now.add(const Duration(seconds: 2));
      final out = await engine.recordTap('UID-1');
      expect(out.direction, 'in');
      expect(await db.pendingCount(), 1);
    });

    test('in, then out after the wait, then the third tap is denied', () async {
      await engine.recordTap('UID-1');
      now = now.add(const Duration(hours: 1));
      expect((await engine.recordTap('UID-1')).direction, 'out');
      now = now.add(const Duration(hours: 1));
      await expectLater(
        engine.recordTap('UID-1'),
        throwsA(isA<TapRejectedException>().having(
          (e) => e.message,
          'message',
          'You have already tapped in and out for today.',
        )),
      );
      expect(await db.pendingCount(), 2);
    });

    test('tap-out too soon is denied and queues nothing', () async {
      await engine.recordTap('UID-1');
      now = now.add(const Duration(minutes: 30));
      await expectLater(
        engine.recordTap('UID-1'),
        throwsA(isA<TapRejectedException>()),
      );
      expect(await db.pendingCount(), 1);
    });

    test('unrecognised card logs in, is queued, and has no student', () async {
      final out = await engine.recordTap('mystery');
      expect(out.direction, 'in');
      expect(out.student, isNull);
      expect(out.studentId, isNull);
      final p = jsonDecode((await db.nextPending())!.payload) as Map<String, dynamic>;
      expect(p['localTapId'], isNull);
    });

    test('uid is trimmed before lookup and queueing', () async {
      final out = await engine.recordTap('  UID-1\n');
      expect(out.student?.id, 's1');
      final p = jsonDecode((await db.nextPending())!.payload) as Map<String, dynamic>;
      expect(p['rfidUid'], 'UID-1');
    });
  });

  group('online', () {
    test('uses the server result, queues nothing, mirrors it locally', () async {
      online = true;
      remote.studentIdFor = (_) => 's1';
      remote.directionFor = (_, __) => 'out';
      final out = await engine.recordTap('UID-1');
      expect(out.direction, 'out');
      expect(out.student?.id, 's1');
      expect(remote.taps, hasLength(1));
      expect(await db.pendingCount(), 0);
      expect((await db.lastTapOnDay('s1', '2026-10-05'))?.direction, 'out');
    });

    test('a server rule rejection surfaces and queues nothing', () async {
      online = true;
      remote.tapError = RemoteRejected('You have already tapped in and out for today.');
      await expectLater(
        engine.recordTap('UID-1'),
        throwsA(isA<TapRejectedException>().having(
          (e) => e.message,
          'message',
          'You have already tapped in and out for today.',
        )),
      );
      expect(await db.pendingCount(), 0);
    });

    test('a network failure falls back to the local path and flags offline', () async {
      online = true;
      remote.tapError = const SocketException('down');
      final out = await engine.recordTap('UID-1');
      expect(out.direction, 'in');
      expect(await db.pendingCount(), 1);
      expect(transientFailures, 1);
    });

    test('a hung server times out and falls back', () async {
      online = true;
      final slow = _HangingRemote();
      final e = TapEngine(
        db: db,
        remote: slow,
        rules: const TapRules(),
        readerUsbSerial: 'KIOSK-MAIN-001',
        isOnline: () => true,
        onTransientFailure: () => transientFailures++,
        now: () => now,
        remoteTimeout: const Duration(milliseconds: 50),
      );
      final out = await e.recordTap('UID-1');
      expect(out.direction, 'in');
      expect(await db.pendingCount(), 1);
      expect(transientFailures, 1);
    });

    test('older queued entries force the local path to keep server order', () async {
      await db.enqueue('tap', '{}', now);
      online = true;
      await engine.recordTap('UID-1');
      expect(remote.taps, isEmpty);
      expect(await db.pendingCount(), 2);
    });
  });
}

class _HangingRemote extends FakeRemote {
  @override
  Future<RemoteTapResult> recordTap({
    required String readerUsbSerial,
    required String rfidUid,
    required DateTime tappedAt,
  }) =>
      Completer<RemoteTapResult>().future;
}
```

- [ ] **Step 4: Run to verify it fails**

Run: `flutter test test/tap_engine_test.dart`
Expected: FAIL — `tap_engine.dart` not found.

- [ ] **Step 5: Implement**

`packages/kiosk_offline/lib/src/tap_engine.dart`:

```dart
import 'dart:convert';

import 'kiosk_database.dart';
import 'kiosk_offline_api.dart';
import 'kiosk_remote.dart';
import 'models.dart';
import 'tap_rules.dart';

/// Records attendance taps.
///
/// Online with an empty outbox: ask the server (authoritative — it also knows
/// taps from other readers) and mirror its answer locally. Offline, on a
/// transient failure, or when older entries are still queued (so the server
/// sees taps in order): decide locally with [TapRules] and queue the tap for
/// replay with its true timestamp.
class TapEngine {
  TapEngine({
    required KioskDatabase db,
    required KioskRemote remote,
    required TapRules rules,
    required String readerUsbSerial,
    required bool Function() isOnline,
    void Function()? onTransientFailure,
    DateTime Function()? now,
    Duration remoteTimeout = const Duration(seconds: 3),
  })  : _db = db,
        _remote = remote,
        _rules = rules,
        _serial = readerUsbSerial,
        _isOnline = isOnline,
        _onTransientFailure = onTransientFailure,
        _now = now ?? DateTime.now,
        _remoteTimeout = remoteTimeout;

  final KioskDatabase _db;
  final KioskRemote _remote;
  final TapRules _rules;
  final String _serial;
  final bool Function() _isOnline;
  final void Function()? _onTransientFailure;
  final DateTime Function() _now;
  final Duration _remoteTimeout;

  Future<TapOutcome> recordTap(String rfidUid) async {
    final uid = rfidUid.trim();
    final tappedAt = _now().toUtc();

    if (_isOnline() && await _db.pendingCount() == 0) {
      try {
        final r = await _remote
            .recordTap(readerUsbSerial: _serial, rfidUid: uid, tappedAt: tappedAt)
            .timeout(_remoteTimeout);
        final studentId = r.studentId;
        if (studentId != null) {
          await _db.insertLocalTap(
            studentId: studentId,
            direction: r.direction,
            tappedAt: r.tappedAt,
          );
        }
        return TapOutcome(
          direction: r.direction,
          studentId: studentId,
          student: studentId == null ? null : await _db.studentById(studentId),
        );
      } on RemoteRejected catch (e) {
        throw TapRejectedException(e.message);
      } on Object {
        // Network failure, timeout, 5xx: fall through to the local path.
        _onTransientFailure?.call();
      }
    }

    return _recordLocally(uid, tappedAt);
  }

  Future<TapOutcome> _recordLocally(String uid, DateTime tappedAt) async {
    final student = await _db.studentByRfid(uid);

    if (student == null) {
      await _db.enqueue('tap', _payload(uid, tappedAt, null), tappedAt);
      return const TapOutcome(direction: 'in', studentId: null, student: null);
    }

    final last = await _db.lastTapOnDay(student.id, schoolDayOf(tappedAt));
    final decision = _rules.decide(
      tappedAt: tappedAt,
      studentKnown: true,
      lastTapToday: last == null
          ? null
          : PriorTap(direction: last.direction, tappedAt: last.tappedAt),
    );

    switch (decision) {
      case TapDenied(:final message):
        throw TapRejectedException(message);
      case TapEchoed(:final direction):
        return TapOutcome(
            direction: direction, studentId: student.id, student: student);
      case TapAccepted(:final direction):
        await _db.transaction(() async {
          final localId = await _db.insertLocalTap(
            studentId: student.id,
            direction: direction,
            tappedAt: tappedAt,
          );
          await _db.enqueue('tap', _payload(uid, tappedAt, localId), tappedAt);
        });
        return TapOutcome(
            direction: direction, studentId: student.id, student: student);
    }
  }

  String _payload(String uid, DateTime tappedAt, int? localTapId) => jsonEncode({
        'readerUsbSerial': _serial,
        'rfidUid': uid,
        'tappedAt': tappedAt.toUtc().toIso8601String(),
        'localTapId': localTapId,
      });
}
```

- [ ] **Step 6: Run to verify it passes**

Run: `flutter test test/tap_engine_test.dart`
Expected: all PASS.

- [ ] **Step 7: Commit**

```bash
git add packages/kiosk_offline/lib/src/kiosk_offline_api.dart packages/kiosk_offline/lib/src/tap_engine.dart packages/kiosk_offline/test/tap_engine_test.dart packages/kiosk_offline/test/support/fake_remote.dart
git commit -m "feat(kiosk_offline): TapEngine with server-first online path and local offline rules" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 5: `Outbox` — ordered drain, backoff, rejection and reconciliation

**Files:**
- Create: `packages/kiosk_offline/lib/src/outbox.dart`
- Test: `packages/kiosk_offline/test/outbox_test.dart`

**Interfaces:**
- Consumes: `KioskDatabase`, `KioskRemote`, `RemoteRejected`, `SlipSubmission`, and the tap payload format from Task 4.
- Produces: `Outbox({required KioskDatabase db, required KioskRemote remote, DateTime Function()? now, Duration baseBackoff = const Duration(seconds: 2), Duration maxBackoff = const Duration(seconds: 60)})`; `Future<DrainReport> drain({bool force = false})`; `class DrainReport({required int processed, required bool blocked})`.

- [ ] **Step 1: Write the failing tests**

`packages/kiosk_offline/test/outbox_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiosk_offline/src/kiosk_database.dart';
import 'package:kiosk_offline/src/kiosk_remote.dart';
import 'package:kiosk_offline/src/models.dart';
import 'package:kiosk_offline/src/outbox.dart';

import 'support/fake_remote.dart';

void main() {
  late KioskDatabase db;
  late FakeRemote remote;
  late DateTime now;
  late Outbox outbox;
  final t0 = DateTime.parse('2026-10-05T08:00:00+08:00');

  Future<int> enqueueTap(String uid, DateTime at, {int? localTapId}) => db.enqueue(
        'tap',
        jsonEncode({
          'readerUsbSerial': 'KIOSK-MAIN-001',
          'rfidUid': uid,
          'tappedAt': at.toUtc().toIso8601String(),
          'localTapId': localTapId,
        }),
        at,
      );

  setUp(() {
    db = KioskDatabase(NativeDatabase.memory());
    remote = FakeRemote();
    now = DateTime.utc(2026, 10, 5, 0, 0);
    outbox = Outbox(db: db, remote: remote, now: () => now);
  });

  tearDown(() => db.close());

  test('drains in order, replays the true timestamp, and empties the queue', () async {
    await enqueueTap('A', t0);
    await enqueueTap('B', t0.add(const Duration(minutes: 1)));
    final report = await outbox.drain();
    expect(report.processed, 2);
    expect(report.blocked, isFalse);
    expect(remote.taps.map((t) => t.uid), ['A', 'B']);
    expect(remote.taps.first.at.isAtSameMomentAs(t0), isTrue);
    expect(remote.taps.first.serial, 'KIOSK-MAIN-001');
    expect(await db.pendingCount(), 0);
  });

  test('slips are replayed through submitSlip', () async {
    const slip = SlipSubmission(
      slipId: 'slip-1',
      studentId: 's1',
      reportedBy: 'p1',
      offenseIds: ['o1', 'o2'],
      isEscalated: true,
      notes: 'n',
      professorId: 't1',
    );
    await db.enqueue('slip', jsonEncode(slip.toJson()), t0);
    await outbox.drain();
    expect(remote.slips.single.slipId, 'slip-1');
    expect(remote.slips.single.offenseIds, ['o1', 'o2']);
    expect(remote.slips.single.professorId, 't1');
    expect(await db.pendingCount(), 0);
  });

  test('a network error keeps the entry, blocks the queue and backs off', () async {
    await enqueueTap('A', t0);
    await enqueueTap('B', t0.add(const Duration(minutes: 1)));
    remote.tapError = const SocketException('down');

    final first = await outbox.drain();
    expect(first.blocked, isTrue);
    expect(await db.pendingCount(), 2);
    expect((await db.nextPending())?.attempts, 1);

    // Still inside the 2 s backoff: nothing is attempted.
    remote.tapError = null;
    now = now.add(const Duration(seconds: 1));
    final skipped = await outbox.drain();
    expect(skipped.processed, 0);
    expect(skipped.blocked, isTrue);
    expect(remote.taps, isEmpty);

    // After the backoff the queue drains, still in order.
    now = now.add(const Duration(seconds: 2));
    await outbox.drain();
    expect(remote.taps.map((t) => t.uid), ['A', 'B']);
    expect(await db.pendingCount(), 0);
  });

  test('force ignores the backoff window', () async {
    await enqueueTap('A', t0);
    remote.tapError = const SocketException('down');
    await outbox.drain();
    remote.tapError = null;
    final report = await outbox.drain(force: true);
    expect(report.processed, 1);
  });

  test('backoff doubles and is capped', () async {
    await enqueueTap('A', t0);
    remote.tapError = const SocketException('down');
    for (var i = 0; i < 8; i++) {
      await outbox.drain(force: true);
    }
    // 2,4,8,16,32,60,60,60 -> the next attempt is 60 s out, not 256 s.
    remote.tapError = null;
    now = now.add(const Duration(seconds: 59));
    expect((await outbox.drain()).processed, 0);
    now = now.add(const Duration(seconds: 2));
    expect((await outbox.drain()).processed, 1);
  });

  test('a rejected entry is parked, does not block later ones, and drops its local tap', () async {
    final local = await db.insertLocalTap(studentId: 's1', direction: 'in', tappedAt: t0);
    await enqueueTap('A', t0, localTapId: local);
    await enqueueTap('B', t0.add(const Duration(minutes: 1)));
    remote.tapError = RemoteRejected('You have already tapped in and out for today.');

    // First call rejects A; swap to success for B within the same drain.
    final calls = <String>[];
    final rejecting = _RejectFirstRemote(calls);
    outbox = Outbox(db: db, remote: rejecting, now: () => now);
    final report = await outbox.drain();

    expect(report.blocked, isFalse);
    expect(calls, ['A', 'B']);
    expect(await db.rejectedCount(), 1);
    expect(await db.pendingCount(), 0);
    expect(await db.lastTapOnDay('s1', '2026-10-05'), isNull);
    final diag = await db.diagnostics();
    expect(diag.single.status, 'rejected');
    expect(diag.single.lastError, 'rejected A');
  });

  test('Review Focus 1: server direction replaces the provisional local direction', () async {
    final local = await db.insertLocalTap(studentId: 's1', direction: 'in', tappedAt: t0);
    await enqueueTap('A', t0, localTapId: local);
    // Another floor reader already tapped this student in: server says out.
    remote.directionFor = (_, __) => 'out';
    await outbox.drain();
    expect((await db.lastTapOnDay('s1', '2026-10-05'))?.direction, 'out');
  });

  test('Review Focus 3: replaying the same tap twice is harmless and consistent', () async {
    final local = await db.insertLocalTap(studentId: 's1', direction: 'in', tappedAt: t0);
    // Simulates "server accepted, app died before deleting the row": the same
    // payload is still in the queue after restart. The server echoes the
    // existing tap (5 s debounce on an identical timestamp).
    await enqueueTap('A', t0, localTapId: local);
    await enqueueTap('A', t0, localTapId: local);
    remote.directionFor = (_, __) => 'in';
    final report = await outbox.drain();
    expect(report.processed, 2);
    expect(await db.pendingCount(), 0);
    expect((await db.lastTapOnDay('s1', '2026-10-05'))?.direction, 'in');
  });

  test('an unknown entry type is rejected rather than retried forever', () async {
    await db.enqueue('mystery', '{}', t0);
    await outbox.drain();
    expect(await db.rejectedCount(), 1);
    expect(await db.pendingCount(), 0);
  });
}

class _RejectFirstRemote extends FakeRemote {
  _RejectFirstRemote(this.calls);
  final List<String> calls;

  @override
  Future<RemoteTapResult> recordTap({
    required String readerUsbSerial,
    required String rfidUid,
    required DateTime tappedAt,
  }) async {
    calls.add(rfidUid);
    if (rfidUid == 'A') throw RemoteRejected('rejected A');
    return RemoteTapResult(
      tapId: 't',
      studentId: null,
      direction: 'in',
      tappedAt: tappedAt,
    );
  }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/outbox_test.dart`
Expected: FAIL — `outbox.dart` not found.

- [ ] **Step 3: Implement**

`packages/kiosk_offline/lib/src/outbox.dart`:

```dart
import 'dart:convert';

import 'kiosk_database.dart';
import 'kiosk_remote.dart';
import 'models.dart';

class DrainReport {
  const DrainReport({required this.processed, required this.blocked});

  /// Entries removed from the pending queue this call (sent or parked).
  final int processed;

  /// True when a transient failure (or an active backoff) stopped the drain.
  final bool blocked;
}

/// Replays queued writes to the server in strict queue order.
///
/// - success: the row is deleted;
/// - [RemoteRejected]: the row is parked as `rejected` (never retried) and
///   the queue moves on;
/// - anything else (network, timeout, 5xx): the row stays, the drain stops,
///   and the next attempt waits an exponentially growing backoff.
class Outbox {
  Outbox({
    required KioskDatabase db,
    required KioskRemote remote,
    DateTime Function()? now,
    this.baseBackoff = const Duration(seconds: 2),
    this.maxBackoff = const Duration(seconds: 60),
  })  : _db = db,
        _remote = remote,
        _now = now ?? DateTime.now;

  final KioskDatabase _db;
  final KioskRemote _remote;
  final DateTime Function() _now;
  final Duration baseBackoff;
  final Duration maxBackoff;

  bool _draining = false;
  int _failures = 0;
  DateTime? _nextAttemptAt;

  Future<DrainReport> drain({bool force = false}) async {
    if (_draining) return const DrainReport(processed: 0, blocked: false);
    final next = _nextAttemptAt;
    if (!force && next != null && _now().isBefore(next)) {
      return const DrainReport(processed: 0, blocked: true);
    }

    _draining = true;
    var processed = 0;
    try {
      while (true) {
        final entry = await _db.nextPending();
        if (entry == null) break;
        try {
          await _send(entry);
          await _db.deleteOutbox(entry.id);
          processed++;
          _failures = 0;
          _nextAttemptAt = null;
        } on RemoteRejected catch (e) {
          await _db.markRejected(entry.id, e.message);
          await _dropLocalTap(entry);
          processed++;
        } catch (e) {
          await _db.recordAttempt(entry.id, e.toString());
          _failures++;
          final scaled = baseBackoff * (1 << (_failures - 1).clamp(0, 10));
          final delay = scaled > maxBackoff ? maxBackoff : scaled;
          _nextAttemptAt = _now().add(delay);
          return DrainReport(processed: processed, blocked: true);
        }
      }
      return DrainReport(processed: processed, blocked: false);
    } finally {
      _draining = false;
    }
  }

  Future<void> _send(OutboxRow entry) async {
    final json = jsonDecode(entry.payload) as Map<String, dynamic>;
    switch (entry.type) {
      case 'tap':
        final r = await _remote.recordTap(
          readerUsbSerial: json['readerUsbSerial'] as String,
          rfidUid: json['rfidUid'] as String,
          tappedAt: DateTime.parse(json['tappedAt'] as String),
        );
        final localId = json['localTapId'] as int?;
        if (localId != null) {
          // The server is authoritative (it also sees other readers' taps).
          await _db.setLocalTapDirection(localId, r.direction);
        }
      case 'slip':
        await _remote.submitSlip(SlipSubmission.fromJson(json));
      default:
        throw RemoteRejected('Unknown outbox entry type "${entry.type}".');
    }
  }

  /// A refused tap must not keep influencing the offline rules.
  Future<void> _dropLocalTap(OutboxRow entry) async {
    if (entry.type != 'tap') return;
    try {
      final json = jsonDecode(entry.payload) as Map<String, dynamic>;
      final localId = json['localTapId'] as int?;
      if (localId != null) await _db.deleteLocalTap(localId);
    } on FormatException {
      // Unparseable payload: nothing to clean up.
    }
  }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/outbox_test.dart`
Expected: all PASS. (Backoff check: failures 1–5 give 2,4,8,16,32 s, then 60 s capped, so after the 8th failure the next window is exactly 60 s.)

- [ ] **Step 5: Commit**

```bash
git add packages/kiosk_offline/lib/src/outbox.dart packages/kiosk_offline/test/outbox_test.dart
git commit -m "feat(kiosk_offline): ordered outbox with backoff, parking and reconciliation" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 6: `ConnectivityMonitor`, `ReferenceSync`, `SyncCoordinator`

**Files:**
- Create: `lib/src/connectivity_monitor.dart`, `lib/src/reference_sync.dart`, `lib/src/sync_coordinator.dart` under `packages/kiosk_offline/`
- Test: `packages/kiosk_offline/test/sync_test.dart`

**Interfaces:**
- Consumes: `KioskDatabase`, `KioskRemote`, `Outbox` (Tasks 3, 5).
- Produces:
  - `ConnectivityMonitor({required Future<bool> Function() ping})`: `bool get isOnline` (starts `false`), `Stream<bool> get changes` (broadcast, emits on change only), `Future<bool> check()`, `void markOffline()`, `void dispose()`.
  - `ReferenceSync({required KioskDatabase db, required KioskRemote remote, DateTime Function()? now, Duration interval = const Duration(minutes: 5)})`: `Future<bool> refreshIfDue({bool force = false})`, `Future<bool> refresh()`.
  - `SyncCoordinator({required ConnectivityMonitor monitor, required Outbox outbox, required ReferenceSync reference, required Future<int> Function() pendingCount, void Function()? onChanged, Duration idleInterval = const Duration(seconds: 60), Duration busyInterval = const Duration(seconds: 15)})`: `void start()`, `Future<void> tick()`, `void requestDrain()`, `void stop()`.

- [ ] **Step 1: Write the failing tests**

`packages/kiosk_offline/test/sync_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiosk_offline/src/connectivity_monitor.dart';
import 'package:kiosk_offline/src/kiosk_database.dart';
import 'package:kiosk_offline/src/models.dart';
import 'package:kiosk_offline/src/outbox.dart';
import 'package:kiosk_offline/src/reference_sync.dart';
import 'package:kiosk_offline/src/sync_coordinator.dart';

import 'support/fake_remote.dart';

const _ana = OfflineStudent(
  id: 's1',
  rfidUid: 'UID-1',
  fullName: 'Ana Cruz',
  studentNumber: '2024-0001',
  gradeSection: '1st Year - BSIT-1A',
);

ReferenceData _data(List<OfflineStudent> students) => ReferenceData(
      students: students,
      staff: const [],
      offenses: const [OfflineOffense(id: 'o1', label: 'Late', category: 'Minor')],
      teachers: const [],
    );

void main() {
  late KioskDatabase db;
  late FakeRemote remote;
  late DateTime now;

  setUp(() {
    db = KioskDatabase(NativeDatabase.memory());
    remote = FakeRemote();
    now = DateTime.utc(2026, 10, 5, 0, 0);
  });
  tearDown(() => db.close());

  group('ConnectivityMonitor', () {
    test('starts offline, flips on a successful ping, emits only on change', () async {
      var ok = true;
      final m = ConnectivityMonitor(ping: () async => ok);
      final seen = <bool>[];
      m.changes.listen(seen.add);
      expect(m.isOnline, isFalse);
      await m.check();
      await m.check();
      ok = false;
      await m.check();
      await Future<void>.delayed(Duration.zero);
      expect(seen, [true, false]);
      m.dispose();
    });

    test('a throwing ping counts as offline; markOffline forces it', () async {
      final m = ConnectivityMonitor(ping: () async => throw const SocketException('x'));
      expect(await m.check(), isFalse);
      var ok = true;
      final m2 = ConnectivityMonitor(ping: () async => ok);
      await m2.check();
      expect(m2.isOnline, isTrue);
      m2.markOffline();
      expect(m2.isOnline, isFalse);
      m.dispose();
      m2.dispose();
    });
  });

  group('ReferenceSync', () {
    test('refresh replaces the cache and stamps the sync time', () async {
      remote.reference = _data([_ana]);
      final sync = ReferenceSync(db: db, remote: remote, now: () => now);
      expect(await sync.refresh(), isTrue);
      expect((await db.studentByRfid('UID-1'))?.fullName, 'Ana Cruz');
      expect(await db.getMeta('reference_synced_at'), isNotNull);
    });

    test('Review Focus 2a: a failed pull leaves the cache untouched', () async {
      remote.reference = _data([_ana]);
      final sync = ReferenceSync(db: db, remote: remote, now: () => now);
      await sync.refresh();
      remote.referenceError = const SocketException('down');
      expect(await sync.refresh(), isFalse);
      expect((await db.studentByRfid('UID-1'))?.fullName, 'Ana Cruz');
    });

    test('Review Focus 2b: an empty student list never wipes a populated cache', () async {
      remote.reference = _data([_ana]);
      final sync = ReferenceSync(db: db, remote: remote, now: () => now);
      await sync.refresh();
      remote.reference = _data(const []);
      expect(await sync.refresh(), isFalse);
      expect(await db.cachedStudentCount(), 1);
    });

    test('an empty list is accepted when the cache is empty (first run)', () async {
      remote.reference = _data(const []);
      final sync = ReferenceSync(db: db, remote: remote, now: () => now);
      expect(await sync.refresh(), isTrue);
    });

    test('refreshIfDue respects the interval unless forced', () async {
      remote.reference = _data([_ana]);
      final sync = ReferenceSync(db: db, remote: remote, now: () => now);
      await sync.refreshIfDue();
      await sync.refreshIfDue();
      expect(remote.referenceFetches, 1);
      now = now.add(const Duration(minutes: 6));
      await sync.refreshIfDue();
      expect(remote.referenceFetches, 2);
      await sync.refreshIfDue(force: true);
      expect(remote.referenceFetches, 3);
    });
  });

  group('SyncCoordinator.tick', () {
    late ConnectivityMonitor monitor;
    late SyncCoordinator coordinator;

    Future<void> queueTap() => db.enqueue(
          'tap',
          jsonEncode({
            'readerUsbSerial': 'KIOSK-MAIN-001',
            'rfidUid': 'UID-1',
            'tappedAt': now.toIso8601String(),
            'localTapId': null,
          }),
          now,
        );

    setUp(() {
      monitor = ConnectivityMonitor(ping: () => remote.ping());
      coordinator = SyncCoordinator(
        monitor: monitor,
        outbox: Outbox(db: db, remote: remote, now: () => now),
        reference: ReferenceSync(db: db, remote: remote, now: () => now),
        pendingCount: db.pendingCount,
      );
      remote.reference = _data([_ana]);
    });
    tearDown(() {
      coordinator.stop();
      monitor.dispose();
    });

    test('offline: nothing is sent or fetched', () async {
      remote.pingResult = false;
      await queueTap();
      await coordinator.tick();
      expect(remote.taps, isEmpty);
      expect(remote.referenceFetches, 0);
      expect(await db.pendingCount(), 1);
    });

    test('online: drains the queue and refreshes reference data', () async {
      await queueTap();
      await coordinator.tick();
      expect(remote.taps, hasLength(1));
      expect(remote.referenceFetches, 1);
      expect(await db.pendingCount(), 0);
    });

    test('coming back online forces a refresh even if one was recent', () async {
      await coordinator.tick(); // online, refreshes
      remote.pingResult = false;
      await coordinator.tick(); // offline
      remote.pingResult = true;
      await coordinator.tick(); // reconnect -> forced refresh
      expect(remote.referenceFetches, 2);
    });

    test('a staying-online tick inside the interval does not refetch', () async {
      await coordinator.tick();
      await coordinator.tick();
      expect(remote.referenceFetches, 1);
    });

    test('a failing drain does not throw out of tick', () async {
      await queueTap();
      remote.tapError = const SocketException('flaky');
      await coordinator.tick();
      expect(await db.pendingCount(), 1);
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/sync_test.dart`
Expected: FAIL — the three source files do not exist.

- [ ] **Step 3: Implement**

`packages/kiosk_offline/lib/src/connectivity_monitor.dart`:

```dart
import 'dart:async';

/// Tracks whether the server is actually reachable. [ping] should be a cheap
/// request to the real backend (adapter state is not enough: "connected, no
/// internet" is the common failure).
class ConnectivityMonitor {
  ConnectivityMonitor({required Future<bool> Function() ping}) : _ping = ping;

  final Future<bool> Function() _ping;
  final _controller = StreamController<bool>.broadcast();
  bool _online = false;

  bool get isOnline => _online;

  /// Emits only when the state changes.
  Stream<bool> get changes => _controller.stream;

  Future<bool> check() async {
    bool ok;
    try {
      ok = await _ping();
    } catch (_) {
      ok = false;
    }
    _set(ok);
    return ok;
  }

  /// A real request just failed transiently — stop trusting "online" until
  /// the next successful probe.
  void markOffline() => _set(false);

  void _set(bool value) {
    if (value == _online) return;
    _online = value;
    if (!_controller.isClosed) _controller.add(value);
  }

  void dispose() => _controller.close();
}
```

`packages/kiosk_offline/lib/src/reference_sync.dart`:

```dart
import 'kiosk_database.dart';
import 'kiosk_remote.dart';

/// Keeps the local reference cache (students, staff, offenses, teachers)
/// fresh. Always a full, atomic replace so deletions and reassigned cards
/// disappear too.
class ReferenceSync {
  ReferenceSync({
    required KioskDatabase db,
    required KioskRemote remote,
    DateTime Function()? now,
    this.interval = const Duration(minutes: 5),
  })  : _db = db,
        _remote = remote,
        _now = now ?? DateTime.now;

  static const _metaKey = 'reference_synced_at';

  final KioskDatabase _db;
  final KioskRemote _remote;
  final DateTime Function() _now;
  final Duration interval;

  Future<bool> refreshIfDue({bool force = false}) async {
    if (!force) {
      final raw = await _db.getMeta(_metaKey);
      final last = raw == null ? null : DateTime.tryParse(raw);
      if (last != null && _now().difference(last) < interval) return false;
    }
    return refresh();
  }

  /// Returns true when the cache was replaced. Never throws; on any failure
  /// (or a suspicious empty result) the existing cache is kept.
  Future<bool> refresh() async {
    try {
      final data = await _remote.fetchReferenceData();
      if (data.students.isEmpty && await _db.cachedStudentCount() > 0) {
        return false;
      }
      await _db.replaceReference(data);
      await _db.setMeta(_metaKey, _now().toUtc().toIso8601String());
      return true;
    } catch (_) {
      return false;
    }
  }
}
```

`packages/kiosk_offline/lib/src/sync_coordinator.dart`:

```dart
import 'dart:async';

import 'connectivity_monitor.dart';
import 'outbox.dart';
import 'reference_sync.dart';

/// Owns the timers: probe connectivity, drain the outbox, refresh reference
/// data. Probes every [busyInterval] while offline or while writes are
/// pending, every [idleInterval] otherwise.
class SyncCoordinator {
  SyncCoordinator({
    required ConnectivityMonitor monitor,
    required Outbox outbox,
    required ReferenceSync reference,
    required Future<int> Function() pendingCount,
    void Function()? onChanged,
    this.idleInterval = const Duration(seconds: 60),
    this.busyInterval = const Duration(seconds: 15),
  })  : _monitor = monitor,
        _outbox = outbox,
        _reference = reference,
        _pendingCount = pendingCount,
        _onChanged = onChanged;

  final ConnectivityMonitor _monitor;
  final Outbox _outbox;
  final ReferenceSync _reference;
  final Future<int> Function() _pendingCount;
  final void Function()? _onChanged;
  final Duration idleInterval;
  final Duration busyInterval;

  Timer? _timer;
  bool _stopped = false;

  void start() {
    _stopped = false;
    _schedule(Duration.zero);
  }

  void stop() {
    _stopped = true;
    _timer?.cancel();
  }

  /// One probe/drain/refresh cycle. Never throws.
  Future<void> tick() async {
    try {
      final wasOnline = _monitor.isOnline;
      final online = await _monitor.check();
      if (online) {
        await _outbox.drain(force: !wasOnline);
        await _reference.refreshIfDue(force: !wasOnline);
      }
    } catch (_) {
      // A cycle failing must not kill the timer; the next one retries.
    }
    _onChanged?.call();
  }

  /// Called right after a write is queued while online.
  void requestDrain() {
    unawaited(() async {
      try {
        await _outbox.drain(force: true);
      } catch (_) {}
      _onChanged?.call();
    }());
  }

  void _schedule(Duration delay) {
    _timer?.cancel();
    _timer = Timer(delay, () async {
      await tick();
      if (_stopped) return;
      final busy = !_monitor.isOnline || await _pendingCount() > 0;
      if (!_stopped) _schedule(busy ? busyInterval : idleInterval);
    });
  }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/sync_test.dart`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/kiosk_offline/lib/src/connectivity_monitor.dart packages/kiosk_offline/lib/src/reference_sync.dart packages/kiosk_offline/lib/src/sync_coordinator.dart packages/kiosk_offline/test/sync_test.dart
git commit -m "feat(kiosk_offline): connectivity probe, reference sync and sync coordinator" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 7: `KioskOffline` service and the conditional-export facade

**Files:**
- Modify: `packages/kiosk_offline/lib/src/kiosk_offline_api.dart` (add the `KioskOffline` interface)
- Create: `lib/src/kiosk_offline_impl.dart`, `lib/src/open_io.dart`, `lib/src/open_stub.dart`; replace `lib/kiosk_offline.dart`
- Test: `packages/kiosk_offline/test/kiosk_offline_impl_test.dart`

**Interfaces:**
- Consumes: everything from Tasks 2–6.
- Produces (public via `package:kiosk_offline/kiosk_offline.dart`):
  - `abstract class KioskOffline` with:
    - `Future<OfflineStudent?> identifyStudent(String rfidUid)`
    - `Future<OfflineStaff?> identifyStaff(String rfidCardId)`
    - `Future<List<OfflineStudent>> searchStudents(String numberPrefix, {int limit = 8})`
    - `Future<List<OfflineOffense>> offenses()`
    - `Future<List<OfflineTeacher>> teachers()`
    - `Future<TapOutcome> recordTap(String rfidUid)` (throws `TapRejectedException`)
    - `Future<void> submitSlip(SlipSubmission slip)` (throws `RemoteRejected` on a server refusal)
    - `Future<SyncStatus> currentStatus()`, `Stream<SyncStatus> get status`
    - `Future<List<OutboxDiagnostic>> diagnostics()`
    - `Future<void> dispose()`
  - `Future<KioskOffline?> openKioskOffline({required KioskRemote remote, required String readerUsbSerial, Duration tapOutMinWait = const Duration(hours: 1)})` — real service on `dart:io` platforms, `null` on web.
  - Package exports: `models.dart`, `kiosk_remote.dart`, `kiosk_offline_api.dart` (so `TapOutcome`, `TapRejectedException`, `RemoteRejected`, DTOs, `SlipSubmission`, `SyncStatus`, `OutboxDiagnostic`, `KioskRemote` are importable).
  - `KioskOfflineImpl` (not exported; tests import `package:kiosk_offline/src/kiosk_offline_impl.dart`): `KioskOfflineImpl({required KioskDatabase db, required KioskRemote remote, required String readerUsbSerial, TapRules rules = const TapRules(), DateTime Function()? now})`, plus `Future<void> start()` and `Future<void> syncNow()`.

- [ ] **Step 1: Add the interface**

Append to `packages/kiosk_offline/lib/src/kiosk_offline_api.dart`:

```dart
/// What the kiosk UI talks to. Implemented on top of SQLite for desktop
/// ([openKioskOffline]); web gets `null` and keeps using Supabase directly.
abstract class KioskOffline {
  Future<OfflineStudent?> identifyStudent(String rfidUid);
  Future<OfflineStaff?> identifyStaff(String rfidCardId);
  Future<List<OfflineStudent>> searchStudents(String numberPrefix, {int limit = 8});
  Future<List<OfflineOffense>> offenses();
  Future<List<OfflineTeacher>> teachers();

  /// Throws [TapRejectedException] when a rule (local or server) refuses it.
  Future<TapOutcome> recordTap(String rfidUid);

  /// Sends now when online, otherwise queues. Throws `RemoteRejected` when
  /// the server refuses it.
  Future<void> submitSlip(SlipSubmission slip);

  Future<SyncStatus> currentStatus();
  Stream<SyncStatus> get status;
  Future<List<OutboxDiagnostic>> diagnostics();
  Future<void> dispose();
}
```

- [ ] **Step 2: Write the failing service tests**

`packages/kiosk_offline/test/kiosk_offline_impl_test.dart`:

```dart
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiosk_offline/src/kiosk_database.dart';
import 'package:kiosk_offline/src/kiosk_offline_api.dart';
import 'package:kiosk_offline/src/kiosk_offline_impl.dart';
import 'package:kiosk_offline/src/kiosk_remote.dart';
import 'package:kiosk_offline/src/models.dart';

import 'support/fake_remote.dart';

const _ana = OfflineStudent(
  id: 's1',
  rfidUid: 'UID-1',
  fullName: 'Ana Cruz',
  studentNumber: '2024-0001',
  gradeSection: '1st Year - BSIT-1A',
);

void main() {
  late KioskDatabase db;
  late FakeRemote remote;
  late DateTime now;
  late KioskOfflineImpl svc;

  setUp(() async {
    db = KioskDatabase(NativeDatabase.memory());
    remote = FakeRemote()
      ..reference = const ReferenceData(
        students: [_ana],
        staff: [OfflineStaff(id: 'p1', rfidCardId: 'CARD-1', fullName: 'Sam Guard', role: 'Security')],
        offenses: [OfflineOffense(id: 'o1', label: 'Late', category: 'Minor')],
        teachers: [OfflineTeacher(id: 't1', fullName: 'Tess Lim')],
      )
      ..studentIdFor = ((uid) => uid == 'UID-1' ? 's1' : null);
    now = DateTime.parse('2026-10-05T08:00:00+08:00');
    svc = KioskOfflineImpl(
      db: db,
      remote: remote,
      readerUsbSerial: 'KIOSK-MAIN-001',
      now: () => now,
    );
  });

  tearDown(() => svc.dispose());

  test('start primes the cache so lookups work', () async {
    await svc.syncNow();
    expect((await svc.identifyStudent('UID-1'))?.fullName, 'Ana Cruz');
    expect((await svc.identifyStaff('CARD-1'))?.role, 'Security');
    expect((await svc.offenses()).single.label, 'Late');
    expect((await svc.teachers()).single.fullName, 'Tess Lim');
    expect((await svc.searchStudents('2024')).single.id, 's1');
  });

  test('an offline tap is queued, then replayed with its true time after reconnect', () async {
    // Cache primed while online, then the network drops.
    await svc.syncNow();
    remote.pingResult = false;
    await svc.syncNow();
    expect((await svc.currentStatus()).online, isFalse);

    final out = await svc.recordTap('UID-1');
    expect(out.direction, 'in');
    expect(out.student?.fullName, 'Ana Cruz');
    expect(remote.taps, isEmpty);
    expect((await svc.currentStatus()).pending, 1);

    // Time passes while offline, then connectivity returns.
    now = now.add(const Duration(minutes: 30));
    remote.pingResult = true;
    await svc.syncNow();

    expect(remote.taps, hasLength(1));
    expect(remote.taps.single.at.isAtSameMomentAs(DateTime.parse('2026-10-05T08:00:00+08:00')), isTrue);
    expect((await svc.currentStatus()).pending, 0);
  });

  test('an offline rule denial reaches the caller as TapRejectedException', () async {
    await svc.syncNow();
    remote.pingResult = false;
    await svc.syncNow();
    await svc.recordTap('UID-1');
    now = now.add(const Duration(minutes: 5));
    await expectLater(svc.recordTap('UID-1'), throwsA(isA<TapRejectedException>()));
  });

  test('online slip goes straight to the server', () async {
    await svc.syncNow();
    const slip = SlipSubmission(
      slipId: 'slip-1', studentId: 's1', reportedBy: 'p1', offenseIds: ['o1']);
    await svc.submitSlip(slip);
    expect(remote.slips.single.slipId, 'slip-1');
    expect((await svc.currentStatus()).pending, 0);
  });

  test('offline slip is queued and delivered after reconnect', () async {
    await svc.syncNow();
    remote.pingResult = false;
    await svc.syncNow();
    const slip = SlipSubmission(
      slipId: 'slip-2', studentId: 's1', reportedBy: 'p1', offenseIds: ['o1']);
    await svc.submitSlip(slip);
    expect(remote.slips, isEmpty);
    expect((await svc.currentStatus()).pending, 1);
    remote.pingResult = true;
    await svc.syncNow();
    expect(remote.slips.single.slipId, 'slip-2');
  });

  test('a slip that fails transiently while "online" is queued, not lost', () async {
    await svc.syncNow();
    remote.slipError = const SocketException('flaky');
    const slip = SlipSubmission(
      slipId: 'slip-3', studentId: 's1', reportedBy: 'p1', offenseIds: ['o1']);
    await svc.submitSlip(slip);
    expect((await svc.currentStatus()).pending, 1);
    expect((await svc.currentStatus()).online, isFalse);
  });

  test('a server-refused slip throws so the dialog can show the message', () async {
    await svc.syncNow();
    remote.slipError = RemoteRejected('Offense not found.');
    const slip = SlipSubmission(
      slipId: 'slip-4', studentId: 's1', reportedBy: 'p1', offenseIds: ['bad']);
    await expectLater(svc.submitSlip(slip), throwsA(isA<RemoteRejected>()));
    expect((await svc.currentStatus()).pending, 0);
  });

  test('rejected replays show up in status and diagnostics', () async {
    await svc.syncNow();
    remote.pingResult = false;
    await svc.syncNow();
    await svc.recordTap('UID-1');
    remote.pingResult = true;
    remote.tapError = RemoteRejected('Reader KIOSK-MAIN-001 is deactivated and cannot record taps.');
    await svc.syncNow();
    final status = await svc.currentStatus();
    expect(status.rejected, 1);
    expect(status.pending, 0);
    final diag = await svc.diagnostics();
    expect(diag.single.status, 'rejected');
    expect(diag.single.lastError, contains('deactivated'));
  });

  test('status stream emits after a write', () async {
    await svc.syncNow();
    final events = <SyncStatus>[];
    final sub = svc.status.listen(events.add);
    remote.pingResult = false;
    await svc.syncNow();
    await svc.recordTap('UID-1');
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    expect(events.last.pending, 1);
    expect(events.last.online, isFalse);
  });
}
```

- [ ] **Step 3: Run to verify it fails**

Run: `flutter test test/kiosk_offline_impl_test.dart`
Expected: FAIL — `kiosk_offline_impl.dart` not found.

- [ ] **Step 4: Implement the service**

`packages/kiosk_offline/lib/src/kiosk_offline_impl.dart`:

```dart
import 'dart:async';
import 'dart:convert';

import 'connectivity_monitor.dart';
import 'kiosk_database.dart';
import 'kiosk_offline_api.dart';
import 'kiosk_remote.dart';
import 'models.dart';
import 'outbox.dart';
import 'reference_sync.dart';
import 'sync_coordinator.dart';
import 'tap_engine.dart';
import 'tap_rules.dart';

class KioskOfflineImpl implements KioskOffline {
  KioskOfflineImpl({
    required KioskDatabase db,
    required KioskRemote remote,
    required String readerUsbSerial,
    TapRules rules = const TapRules(),
    DateTime Function()? now,
  })  : _db = db,
        _remote = remote,
        _now = now ?? DateTime.now {
    _monitor = ConnectivityMonitor(ping: remote.ping);
    _outbox = Outbox(db: db, remote: remote, now: _now);
    _reference = ReferenceSync(db: db, remote: remote, now: _now);
    _engine = TapEngine(
      db: db,
      remote: remote,
      rules: rules,
      readerUsbSerial: readerUsbSerial,
      isOnline: () => _monitor.isOnline,
      onTransientFailure: _monitor.markOffline,
      now: _now,
    );
    _coordinator = SyncCoordinator(
      monitor: _monitor,
      outbox: _outbox,
      reference: _reference,
      pendingCount: db.pendingCount,
      onChanged: () => unawaited(_emit()),
    );
  }

  final KioskDatabase _db;
  final KioskRemote _remote;
  final DateTime Function() _now;
  late final ConnectivityMonitor _monitor;
  late final Outbox _outbox;
  late final ReferenceSync _reference;
  late final TapEngine _engine;
  late final SyncCoordinator _coordinator;
  final _status = StreamController<SyncStatus>.broadcast();
  bool _disposed = false;

  /// Begins the background probe/drain/refresh loop.
  Future<void> start() async => _coordinator.start();

  /// One immediate probe + drain + refresh cycle (used by tests and startup).
  Future<void> syncNow() => _coordinator.tick();

  @override
  Future<OfflineStudent?> identifyStudent(String rfidUid) =>
      _db.studentByRfid(rfidUid);

  @override
  Future<OfflineStaff?> identifyStaff(String rfidCardId) =>
      _db.staffByCard(rfidCardId);

  @override
  Future<List<OfflineStudent>> searchStudents(String numberPrefix, {int limit = 8}) =>
      _db.searchStudents(numberPrefix, limit: limit);

  @override
  Future<List<OfflineOffense>> offenses() => _db.offenses();

  @override
  Future<List<OfflineTeacher>> teachers() => _db.teachers();

  @override
  Future<TapOutcome> recordTap(String rfidUid) async {
    try {
      return await _engine.recordTap(rfidUid);
    } finally {
      await _afterWrite();
    }
  }

  @override
  Future<void> submitSlip(SlipSubmission slip) async {
    if (_monitor.isOnline && await _db.pendingCount() == 0) {
      try {
        await _remote.submitSlip(slip).timeout(const Duration(seconds: 5));
        return;
      } on RemoteRejected {
        rethrow;
      } on Object {
        _monitor.markOffline();
      }
    }
    await _db.enqueue('slip', jsonEncode(slip.toJson()), _now());
    await _afterWrite();
  }

  Future<void> _afterWrite() async {
    await _emit();
    if (_monitor.isOnline && await _db.pendingCount() > 0) {
      _coordinator.requestDrain();
    }
  }

  Future<void> _emit() async {
    if (_disposed || _status.isClosed) return;
    _status.add(await currentStatus());
  }

  @override
  Future<SyncStatus> currentStatus() async => SyncStatus(
        online: _monitor.isOnline,
        pending: await _db.pendingCount(),
        rejected: await _db.rejectedCount(),
      );

  @override
  Stream<SyncStatus> get status => _status.stream;

  @override
  Future<List<OutboxDiagnostic>> diagnostics() => _db.diagnostics();

  @override
  Future<void> dispose() async {
    _disposed = true;
    _coordinator.stop();
    _monitor.dispose();
    await _status.close();
    await _db.close();
  }
}
```

- [ ] **Step 5: Implement opening, the stub and the facade**

`packages/kiosk_offline/lib/src/open_io.dart`:

```dart
import 'dart:io';

import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';

import 'kiosk_database.dart';
import 'kiosk_offline_api.dart';
import 'kiosk_offline_impl.dart';
import 'kiosk_remote.dart';
import 'tap_rules.dart';

/// Opens (creating if needed) the on-disk database and starts background
/// sync. Throws if the database file cannot be opened — callers fall back to
/// online-only behaviour.
Future<KioskOffline?> openKioskOffline({
  required KioskRemote remote,
  required String readerUsbSerial,
  Duration tapOutMinWait = const Duration(hours: 1),
}) async {
  final dir = await getApplicationSupportDirectory();
  final file = File('${dir.path}${Platform.pathSeparator}kiosk_offline.sqlite');
  final db = KioskDatabase(NativeDatabase(file));
  final svc = KioskOfflineImpl(
    db: db,
    remote: remote,
    readerUsbSerial: readerUsbSerial,
    rules: TapRules(tapOutMinWait: tapOutMinWait),
  );
  await svc.start();
  return svc;
}
```

`packages/kiosk_offline/lib/src/open_stub.dart`:

```dart
import 'kiosk_offline_api.dart';
import 'kiosk_remote.dart';

/// Web (and any platform without `dart:io`): no local database, so the
/// caller keeps its existing online-only behaviour.
Future<KioskOffline?> openKioskOffline({
  required KioskRemote remote,
  required String readerUsbSerial,
  Duration tapOutMinWait = const Duration(hours: 1),
}) async =>
    null;
```

`packages/kiosk_offline/lib/kiosk_offline.dart`:

```dart
/// Offline-first cache, tap rules and sync outbox for the Windows kiosk.
///
/// `openKioskOffline` is a conditional export: the real SQLite-backed
/// implementation on `dart:io` platforms, a `null`-returning stub on web, so
/// the web build never pulls in `dart:ffi`.
library kiosk_offline;

export 'src/kiosk_offline_api.dart';
export 'src/kiosk_remote.dart';
export 'src/models.dart';
export 'src/open_stub.dart' if (dart.library.io) 'src/open_io.dart';
```

- [ ] **Step 6: Run the service tests, then the whole package**

Run: `flutter test test/kiosk_offline_impl_test.dart` then `flutter test` then `flutter analyze`
Expected: all PASS; analyzer clean (generated files excluded).

- [ ] **Step 7: Commit**

```bash
git add packages/kiosk_offline/lib packages/kiosk_offline/test/kiosk_offline_impl_test.dart
git commit -m "feat(kiosk_offline): KioskOffline service and web-safe conditional facade" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Root app — `SupabaseKioskRemote` and kiosk host wiring

**Files:**
- Create: `lib/kiosk/supabase_kiosk_remote.dart`, `test/supabase_kiosk_remote_test.dart`, `test/open_offline_or_null_test.dart`
- Modify: `lib/kiosk/capstone_kiosk_scan_host.dart`, `supabase_dart_defines.json.example`

**Interfaces:**
- Consumes: `KioskRemote`, `RemoteRejected`, `RemoteTapResult`, `SlipSubmission`, `ReferenceData` + DTOs, `KioskOffline`, `TapOutcome`, `TapRejectedException`, `openKioskOffline` (Task 7); existing `StudentsRepository.fetchAll()`, `DisciplineRepository.fetchOffenseOptions()`, `RegistrarRepository.fetchTeachers()`, `AppEnv.supabaseUrl/supabaseAnonKey`.
- Produces:
  - `class SupabaseKioskRemote implements KioskRemote { SupabaseKioskRemote(SupabaseClient client); static bool isPermanentPostgrestError(PostgrestException e); }`
  - `Future<KioskOffline?> openOfflineOrNull(Future<KioskOffline?> Function() opener, {void Function(Object error)? onError})` in `capstone_kiosk_scan_host.dart` — returns null and reports instead of throwing (Review Focus 5).

- [ ] **Step 1: Write the failing tests**

`test/supabase_kiosk_remote_test.dart`:

```dart
import 'package:capstone_dashboard/kiosk/supabase_kiosk_remote.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  bool permanent(String? code) => SupabaseKioskRemote.isPermanentPostgrestError(
        PostgrestException(message: 'm', code: code),
      );

  test('raise exception from record_rfid_tap (P0001) is a permanent rejection', () {
    expect(permanent('P0001'), isTrue);
  });

  test('permission and data errors are permanent', () {
    expect(permanent('42501'), isTrue);
    expect(permanent('22P02'), isTrue);
    expect(permanent('23503'), isTrue);
  });

  test('server/gateway errors are transient', () {
    expect(permanent('500'), isFalse);
    expect(permanent('502'), isFalse);
    expect(permanent('503'), isFalse);
    expect(permanent('504'), isFalse);
    expect(permanent(null), isFalse);
  });

  test('PostgREST connection errors are transient, request errors permanent', () {
    expect(permanent('PGRST000'), isFalse);
    expect(permanent('PGRST002'), isFalse);
    expect(permanent('PGRST202'), isTrue);
  });
}
```

`test/open_offline_or_null_test.dart`:

```dart
import 'package:capstone_dashboard/kiosk/capstone_kiosk_scan_host.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiosk_offline/kiosk_offline.dart';

void main() {
  test('Review Focus 5: a database that cannot open yields null, not a crash', () async {
    Object? reported;
    final result = await openOfflineOrNull(
      () async => throw StateError('database is locked'),
      onError: (e) => reported = e,
    );
    expect(result, isNull);
    expect(reported, isA<StateError>());
  });

  test('a null opener result (web) passes through', () async {
    expect(await openOfflineOrNull(() async => null), isNull);
  });

  test('a successful opener result is returned', () async {
    final fake = _NoopOffline();
    expect(await openOfflineOrNull(() async => fake), same(fake));
  });
}

class _NoopOffline implements KioskOffline {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
```

(The package name in the imports is `capstone_dashboard`, from the root `pubspec.yaml`.)

- [ ] **Step 2: Run to verify they fail**

Run (repo root): `flutter test test/supabase_kiosk_remote_test.dart test/open_offline_or_null_test.dart`
Expected: FAIL — files/symbols not found.

- [ ] **Step 3: Implement `SupabaseKioskRemote`**

`lib/kiosk/supabase_kiosk_remote.dart`:

```dart
import 'package:http/http.dart' as http;
import 'package:kiosk_offline/kiosk_offline.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/discipline_repository.dart';
import '../data/registrar_repository.dart';
import '../data/students_repository.dart';
import '../env.dart';

/// [KioskRemote] over the existing Supabase RPCs and repositories.
///
/// Error contract with the outbox: a [PostgrestException] that is a business
/// or permission failure becomes [RemoteRejected] (never retried); everything
/// else — socket errors, timeouts, 5xx, PostgREST connection errors — is
/// rethrown as-is and treated as transient.
class SupabaseKioskRemote implements KioskRemote {
  SupabaseKioskRemote(this._client);

  final SupabaseClient _client;

  /// `raise exception` inside `record_rfid_tap` surfaces as `P0001`.
  static bool isPermanentPostgrestError(PostgrestException e) {
    final code = e.code ?? '';
    if (code == 'P0001' || code == '42501') return true;
    if (code.startsWith('22') || code.startsWith('23')) return true;
    if (code.startsWith('PGRST')) {
      const connection = {'PGRST000', 'PGRST001', 'PGRST002', 'PGRST003'};
      return !connection.contains(code);
    }
    return false;
  }

  @override
  Future<RemoteTapResult> recordTap({
    required String readerUsbSerial,
    required String rfidUid,
    required DateTime tappedAt,
  }) async {
    try {
      final rows = await _client.rpc('record_rfid_tap', params: {
        'p_reader_usb_serial': readerUsbSerial,
        'p_rfid_uid': rfidUid,
        'p_tapped_at': tappedAt.toUtc().toIso8601String(),
      });
      final row = (rows as List<dynamic>).first as Map<String, dynamic>;
      return RemoteTapResult(
        tapId: row['tap_id'] as String,
        studentId: row['student_id'] as String?,
        direction: row['tap_direction'] as String,
        tappedAt: DateTime.parse(row['tapped_at'] as String),
      );
    } on PostgrestException catch (e) {
      if (isPermanentPostgrestError(e)) throw RemoteRejected(e.message);
      rethrow;
    }
  }

  @override
  Future<void> submitSlip(SlipSubmission slip) async {
    try {
      await _client.rpc('submit_admission_slip', params: {
        'p_slip_id': slip.slipId,
        'p_student_id': slip.studentId,
        'p_reported_by': slip.reportedBy,
        'p_offense_ids': slip.offenseIds,
        'p_is_escalated': slip.isEscalated,
        if (slip.notes != null && slip.notes!.isNotEmpty)
          'p_incident_notes': slip.notes,
        if (slip.professorId != null && slip.professorId!.isNotEmpty)
          'p_professor_id': slip.professorId,
      });
    } on PostgrestException catch (e) {
      // Duplicate slip id: an earlier attempt already landed (e.g. the app
      // died before the outbox row was deleted). Treat as delivered.
      if (e.code == '23505') return;
      if (isPermanentPostgrestError(e)) throw RemoteRejected(e.message);
      rethrow;
    }
  }

  @override
  Future<ReferenceData> fetchReferenceData() async {
    final students = await StudentsRepository(_client).fetchAll();
    final offenses = await DisciplineRepository(_client).fetchOffenseOptions();
    final teachers = await RegistrarRepository(_client).fetchTeachers();
    final staffRows = await _client
        .from('profiles')
        .select('id, first_name, last_name, role, status, rfid_card_id')
        .not('rfid_card_id', 'is', null)
        .eq('status', 'approved');

    final staff = <OfflineStaff>[];
    for (final raw in staffRows as List<dynamic>) {
      final row = raw as Map<String, dynamic>;
      final role = row['role'] as String?;
      final card = (row['rfid_card_id'] as String?)?.trim() ?? '';
      // Same exclusions as StudentsRepository.fetchStaffByRfidCardId.
      if (role == null ||
          card.isEmpty ||
          role == AppEnv.profileRoleStudent ||
          role == 'Parent') {
        continue;
      }
      final first = (row['first_name'] as String?) ?? '';
      final last = (row['last_name'] as String?) ?? '';
      staff.add(OfflineStaff(
        id: row['id'] as String,
        rfidCardId: card,
        fullName: '${first.trim()} ${last.trim()}'.trim(),
        role: role,
      ));
    }

    return ReferenceData(
      students: [
        for (final s in students)
          OfflineStudent(
            id: s.id,
            rfidUid: s.rfidUid.trim(),
            fullName: s.fullName,
            studentNumber: s.studentNumber,
            gradeSection: '${s.yearLevel} - ${s.section}',
            course: s.course,
          ),
      ],
      staff: staff,
      offenses: [
        for (final o in offenses)
          OfflineOffense(id: o.id, label: o.label, category: o.category),
      ],
      teachers: [
        for (final t in teachers)
          OfflineTeacher(id: t.id, fullName: t.fullName),
      ],
    );
  }

  /// Any HTTP response from the REST endpoint (even 401) proves the server
  /// is reachable; a socket error or timeout does not.
  @override
  Future<bool> ping() async {
    try {
      final res = await http
          .get(
            Uri.parse('${AppEnv.supabaseUrl}/rest/v1/'),
            headers: {'apikey': AppEnv.supabaseAnonKey},
          )
          .timeout(const Duration(seconds: 3));
      return res.statusCode < 500;
    } catch (_) {
      return false;
    }
  }
}
```

- [ ] **Step 4: Wire the host — imports, constants, helper, state**

In `lib/kiosk/capstone_kiosk_scan_host.dart`:

Add imports (alphabetical with the existing ones):

```dart
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:kiosk_offline/kiosk_offline.dart';
```

and, after the `../env.dart` import, `import 'supabase_kiosk_remote.dart';`. If `package:flutter/foundation.dart` is already re-exported through `material.dart` the first import is unnecessary — drop it if the analyzer reports `unnecessary_import`.

After the `_kioskReaderUsbSerial` constant add:

```dart
/// Minimum wait between tap-in and tap-out for the *offline* rules. Must match
/// the live `record_rfid_tap` (1 hour in production). Dev builds can shorten
/// it with `--dart-define=KIOSK_TAP_OUT_MIN_WAIT_SECONDS=5`.
const int _tapOutMinWaitSeconds =
    int.fromEnvironment('KIOSK_TAP_OUT_MIN_WAIT_SECONDS', defaultValue: 3600);

/// Opens the offline service without ever throwing: a locked/corrupt/
/// read-only database must leave the kiosk working online, not dead.
Future<KioskOffline?> openOfflineOrNull(
  Future<KioskOffline?> Function() opener, {
  void Function(Object error)? onError,
}) async {
  try {
    return await opener();
  } catch (e) {
    onError?.call(e);
    return null;
  }
}

KioskStudentPayload _payloadFor(OfflineStudent s) => KioskStudentPayload(
      id: s.id,
      displayName: s.fullName,
      studentNumber: s.studentNumber,
      gradeSection: s.gradeSection,
      course: s.course,
    );
```

In `_CapstoneKioskScanHostState`, after `_idleScreenResetCount`:

```dart
  /// Null until opened, and stays null on web or if the local database could
  /// not be opened — every call site below falls back to direct Supabase.
  KioskOffline? _offline;

  @override
  void initState() {
    super.initState();
    if (AppEnv.supabaseConfigured) _openOffline();
  }

  Future<void> _openOffline() async {
    final svc = await openOfflineOrNull(
      () => openKioskOffline(
        remote: SupabaseKioskRemote(Supabase.instance.client),
        readerUsbSerial: _kioskReaderUsbSerial,
        tapOutMinWait: Duration(seconds: _tapOutMinWaitSeconds),
      ),
      onError: (e) => debugPrint('Kiosk offline store unavailable, staying online-only: $e'),
    );
    if (!mounted) {
      await svc?.dispose();
      return;
    }
    setState(() => _offline = svc);
  }

  @override
  void dispose() {
    _offline?.dispose();
    super.dispose();
  }
```

- [ ] **Step 5: Wire the host — offenses, teachers, slip submit**

Replace the bodies of `_loadOffenseOptions` and `_loadTeacherOptions` so the offline path is consulted first (the in-memory memo is skipped there because the DB read is cheap and always current):

```dart
  Future<List<OffenseOption>> _loadOffenseOptions() async {
    final offline = _offline;
    if (offline != null) {
      final rows = await offline.offenses();
      if (rows.isNotEmpty) {
        return [
          for (final o in rows)
            OffenseOption(id: o.id, label: o.label, category: o.category),
        ];
      }
    }
    final cached = _offenseOptionsCache;
    if (cached != null) return cached;
    final repo = _disciplineRepo;
    if (repo == null) return const [];
    try {
      final options = await repo.fetchOffenseOptions();
      _offenseOptionsCache = options;
      return options;
    } catch (_) {
      return const [];
    }
  }

  Future<List<TeacherOptionData>> _loadTeacherOptions() async {
    final offline = _offline;
    if (offline != null) {
      final rows = await offline.teachers();
      if (rows.isNotEmpty) {
        return [for (final t in rows) TeacherOptionData(id: t.id, fullName: t.fullName)];
      }
    }
    final cached = _teacherOptionsCache;
    if (cached != null) return cached;
    final repo = _registrarRepo;
    if (repo == null) return const [];
    try {
      final teachers = await repo.fetchTeachers();
      final options = [
        for (final t in teachers) TeacherOptionData(id: t.id, fullName: t.fullName),
      ];
      _teacherOptionsCache = options;
      return options;
    } catch (_) {
      return const [];
    }
  }
```

In `_openSlipPreview`, replace the local `submit()` function with:

```dart
    Future<void> submit() async {
      final offline = _offline;
      if (offline != null) {
        try {
          await offline.submitSlip(
            SlipSubmission(
              slipId: slipId,
              studentId: studentId,
              reportedBy: reportedBy,
              offenseIds: selectedOffenseIds,
              isEscalated: isEscalated,
              notes: notes,
              professorId: professorId,
            ),
          );
        } on RemoteRejected catch (e) {
          throw AdmissionSlipRepositoryException(e.message);
        }
        return;
      }
      final repo = _slipRepo;
      if (repo == null) {
        throw Exception('Supabase is not configured.');
      }
      await repo.submit(
        AdmissionSlipSubmission(
          slipId: slipId,
          studentId: studentId,
          reportedBy: reportedBy,
          offenseIds: selectedOffenseIds,
          isEscalated: isEscalated,
          notes: notes,
          professorId: professorId,
        ),
      );
    }
```

- [ ] **Step 6: Wire the host — taps, identification, student search**

Replace the `recordAttendanceTap`, `identifyStudent` and `identifyStaff` arguments and the `onSearchStudents` closure body so each checks `_offline` first and otherwise runs the existing code unchanged.

`recordAttendanceTap`: insert at the top of the closure, before `if (!AppEnv.supabaseConfigured)`:

```dart
        final offline = _offline;
        if (offline != null) return _recordTapOffline(offline, uid);
```

`identifyStudent`: insert at the top:

```dart
        final offline = _offline;
        if (offline != null) {
          final s = await offline.identifyStudent(uid);
          return s == null ? null : _payloadFor(s);
        }
```

`identifyStaff`: insert at the top:

```dart
        final offline = _offline;
        if (offline != null) {
          final s = await offline.identifyStaff(uid);
          return s == null
              ? null
              : KioskStaffPayload(id: s.id, displayName: s.fullName, roleLabel: s.role);
        }
```

`onSearchStudents`: insert at the top of the closure:

```dart
                final offline = _offline;
                if (offline != null) {
                  final hits = await offline.searchStudents(query);
                  return [
                    for (final s in hits)
                      SecurityReportStudentOption(
                        id: s.id,
                        displayName: s.fullName,
                        studentNumber: s.studentNumber,
                        gradeSection: s.gradeSection,
                      ),
                  ];
                }
```

Add this method to `_CapstoneKioskScanHostState` (next to `_openSlipPreview`):

```dart
  Future<KioskAttendanceTapResult> _recordTapOffline(
    KioskOffline offline,
    String uid,
  ) async {
    final TapOutcome outcome;
    try {
      outcome = await offline.recordTap(uid);
    } on TapRejectedException catch (e) {
      throw AttendanceTapRejected(e.message);
    }

    var payload = outcome.student == null ? null : _payloadFor(outcome.student!);
    if (payload == null && outcome.studentId != null) {
      // The server recognised the card but the cache has not seen this
      // student yet (e.g. registered since the last refresh).
      try {
        final s = await StudentsRepository(Supabase.instance.client)
            .fetchStudentByRfidUid(uid);
        if (s != null) {
          payload = KioskStudentPayload(
            id: s.id,
            displayName: s.fullName,
            studentNumber: s.studentNumber,
            gradeSection: '${s.yearLevel} - ${s.section}',
            course: s.course,
          );
        }
      } catch (_) {
        // Connection dropped between the tap and this lookup; show "not
        // recognised" rather than fail a tap that was already recorded.
      }
    }
    return KioskAttendanceTapResult(student: payload, direction: outcome.direction);
  }
```

- [ ] **Step 7: Add the dev define to the example file and run checks**

Add `"KIOSK_TAP_OUT_MIN_WAIT_SECONDS": "3600"` to `supabase_dart_defines.json.example` (keep the JSON valid — mind the comma on the previous line).

Run (repo root): `flutter pub get`, `flutter analyze lib/kiosk test/supabase_kiosk_remote_test.dart test/open_offline_or_null_test.dart`, `flutter test test/supabase_kiosk_remote_test.dart test/open_offline_or_null_test.dart`
Expected: analyzer clean for those paths; tests PASS.

Then confirm the existing kiosk widget test still passes: `cd packages/kiosk_home && flutter test`
Expected: PASS.

- [ ] **Step 8: Prove the web build still compiles without SQLite**

Run (repo root): `flutter build web --release -t lib/main.dart`
Expected: build succeeds (the conditional export means `open_io.dart` is not compiled for web). If it fails with a `dart:ffi`/`dart:io` import trace, the conditional export in `kiosk_offline.dart` is wrong — fix it before continuing.

- [ ] **Step 9: Commit**

```bash
git add lib/kiosk/supabase_kiosk_remote.dart lib/kiosk/capstone_kiosk_scan_host.dart test/supabase_kiosk_remote_test.dart test/open_offline_or_null_test.dart supabase_dart_defines.json.example
git commit -m "feat(kiosk): route taps, lookups and slips through the offline service" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 9: Status chip and diagnostics dialog

**Files:**
- Create: `lib/kiosk/offline_status_chip.dart`, `test/offline_status_chip_test.dart`
- Modify: `lib/kiosk/capstone_kiosk_scan_host.dart` (overlay the chip)

**Interfaces:**
- Consumes: `KioskOffline.currentStatus()/status/diagnostics()`, `SyncStatus`, `OutboxDiagnostic`.
- Produces: `class OfflineStatusChip extends StatefulWidget { const OfflineStatusChip({super.key, required KioskOffline offline}); }`; `String describeSyncStatus(SyncStatus s)` (top-level, pure).

Label rules: `rejected > 0` → `"N failed"`; else offline → `"Offline · N pending"`; else pending > 0 → `"Syncing · N pending"`; else `"Online"`.

- [ ] **Step 1: Write the failing tests**

`test/offline_status_chip_test.dart`:

```dart
import 'dart:async';

import 'package:capstone_dashboard/kiosk/offline_status_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiosk_offline/kiosk_offline.dart';

class _FakeOffline implements KioskOffline {
  _FakeOffline(this._current);
  SyncStatus _current;
  List<OutboxDiagnostic> rows = const [];
  final _ctrl = StreamController<SyncStatus>.broadcast();

  void push(SyncStatus s) {
    _current = s;
    _ctrl.add(s);
  }

  @override
  Future<SyncStatus> currentStatus() async => _current;
  @override
  Stream<SyncStatus> get status => _ctrl.stream;
  @override
  Future<List<OutboxDiagnostic>> diagnostics() async => rows;
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Widget _host(KioskOffline offline) => MaterialApp(
      home: Scaffold(body: Center(child: OfflineStatusChip(offline: offline))),
    );

void main() {
  test('describeSyncStatus covers every state', () {
    expect(describeSyncStatus(const SyncStatus(online: true, pending: 0, rejected: 0)), 'Online');
    expect(describeSyncStatus(const SyncStatus(online: true, pending: 2, rejected: 0)), 'Syncing · 2 pending');
    expect(describeSyncStatus(const SyncStatus(online: false, pending: 3, rejected: 0)), 'Offline · 3 pending');
    expect(describeSyncStatus(const SyncStatus(online: false, pending: 0, rejected: 0)), 'Offline · 0 pending');
    expect(describeSyncStatus(const SyncStatus(online: true, pending: 1, rejected: 2)), '2 failed');
  });

  testWidgets('shows the current status and follows the stream', (tester) async {
    final offline = _FakeOffline(const SyncStatus(online: true, pending: 0, rejected: 0));
    await tester.pumpWidget(_host(offline));
    await tester.pump();
    expect(find.text('Online'), findsOneWidget);

    offline.push(const SyncStatus(online: false, pending: 4, rejected: 0));
    await tester.pump();
    expect(find.text('Offline · 4 pending'), findsOneWidget);
  });

  testWidgets('tapping opens diagnostics listing each entry and its error', (tester) async {
    final offline = _FakeOffline(const SyncStatus(online: true, pending: 1, rejected: 1))
      ..rows = [
        OutboxDiagnostic(
          id: 1,
          type: 'tap',
          status: 'rejected',
          attempts: 0,
          createdAt: DateTime.utc(2026, 10, 5, 0, 0),
          lastError: 'You have already tapped in and out for today.',
        ),
        OutboxDiagnostic(
          id: 2,
          type: 'slip',
          status: 'pending',
          attempts: 3,
          createdAt: DateTime.utc(2026, 10, 5, 0, 5),
          lastError: 'SocketException',
        ),
      ];
    await tester.pumpWidget(_host(offline));
    await tester.pump();
    await tester.tap(find.text('1 failed'));
    await tester.pumpAndSettle();
    expect(find.text('Sync details'), findsOneWidget);
    expect(find.textContaining('You have already tapped in and out for today.'), findsOneWidget);
    expect(find.textContaining('SocketException'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Sync details'), findsNothing);
  });

  testWidgets('empty diagnostics says so', (tester) async {
    final offline = _FakeOffline(const SyncStatus(online: true, pending: 0, rejected: 0));
    await tester.pumpWidget(_host(offline));
    await tester.pump();
    await tester.tap(find.text('Online'));
    await tester.pumpAndSettle();
    expect(find.text('Nothing waiting to sync.'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/offline_status_chip_test.dart`
Expected: FAIL — `offline_status_chip.dart` not found.

- [ ] **Step 3: Implement**

`lib/kiosk/offline_status_chip.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kiosk_offline/kiosk_offline.dart';

String describeSyncStatus(SyncStatus s) {
  if (s.rejected > 0) return '${s.rejected} failed';
  if (!s.online) return 'Offline · ${s.pending} pending';
  if (s.pending > 0) return 'Syncing · ${s.pending} pending';
  return 'Online';
}

Color _colorFor(SyncStatus s) {
  if (s.rejected > 0) return const Color(0xFFB91C1C);
  if (!s.online) return const Color(0xFFB45309);
  if (s.pending > 0) return const Color(0xFF1D4ED8);
  return const Color(0xFF15803D);
}

/// Small corner chip showing connectivity and sync backlog; tap for details.
class OfflineStatusChip extends StatefulWidget {
  const OfflineStatusChip({super.key, required this.offline});

  final KioskOffline offline;

  @override
  State<OfflineStatusChip> createState() => _OfflineStatusChipState();
}

class _OfflineStatusChipState extends State<OfflineStatusChip> {
  SyncStatus _status = const SyncStatus(online: false, pending: 0, rejected: 0);
  StreamSubscription<SyncStatus>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.offline.status.listen((s) {
      if (mounted) setState(() => _status = s);
    });
    widget.offline.currentStatus().then((s) {
      if (mounted) setState(() => _status = s);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _showDetails() async {
    final rows = await widget.offline.diagnostics();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sync details'),
        content: SizedBox(
          width: 420,
          child: rows.isEmpty
              ? const Text('Nothing waiting to sync.')
              : ListView(
                  shrinkWrap: true,
                  children: [
                    for (final r in rows)
                      ListTile(
                        dense: true,
                        title: Text('${r.type} · ${r.status} · ${r.attempts} tries'),
                        subtitle: Text(
                          [
                            r.createdAt.toLocal().toString(),
                            if (r.lastError != null) r.lastError!,
                          ].join('\n'),
                        ),
                      ),
                  ],
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = _colorFor(_status);
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: _showDetails,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            describeSyncStatus(_status),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/offline_status_chip_test.dart`
Expected: all PASS.

- [ ] **Step 5: Overlay the chip in the host**

In `lib/kiosk/capstone_kiosk_scan_host.dart` add `import 'offline_status_chip.dart';`. In `build`, immediately after `body` is assigned and before the `if (!widget.embedFromHub)` check, add:

```dart
    final offline = _offline;
    final bodyWithStatus = offline == null
        ? body
        : Stack(
            fit: StackFit.expand,
            children: [
              body,
              SafeArea(
                child: Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: OfflineStatusChip(offline: offline),
                  ),
                ),
              ),
            ],
          );
```

Then use `bodyWithStatus` in place of `body` in the two remaining return paths (`return bodyWithStatus;` and as the first child of the embed `Stack`).

- [ ] **Step 6: Analyze and commit**

Run: `flutter analyze lib/kiosk test/offline_status_chip_test.dart`
Expected: clean.

```bash
git add lib/kiosk/offline_status_chip.dart lib/kiosk/capstone_kiosk_scan_host.dart test/offline_status_chip_test.dart
git commit -m "feat(kiosk): offline status chip with sync diagnostics dialog" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 10: Windows verification, docs, spec update

**Files:**
- Create: `packages/kiosk_offline/README.md`
- Modify: `docs/superpowers/specs/2026-10-04-kiosk-offline-first-drift-design.md`

- [ ] **Step 1: Run every automated check**

Run (repo root): `flutter analyze` then `flutter test` then `cd packages/kiosk_offline && flutter test && flutter analyze` then `cd ../kiosk_home && flutter test`
Expected: no new analyzer issues vs. `main` (record any pre-existing ones and leave them), all tests PASS.

- [ ] **Step 2: Windows build bundles SQLite**

Run (repo root): `flutter build windows --debug -t lib/main_kiosk.dart`
Expected: build succeeds. Confirm the output folder contains `sqlite3.dll` (from `sqlite3_flutter_libs`): `ls build/windows/x64/runner/Debug/*.dll`. If it is missing, copy the same `sqlite3.dll` used in Task 1 into the Windows runner via the `windows/CMakeLists.txt` `install(FILES ... DESTINATION "${INSTALL_BUNDLE_LIB_DIR}")` block, and rebuild.

- [ ] **Step 3: Manual offline walkthrough on the Windows kiosk**

Run: `flutter run -d windows -t lib/main_kiosk.dart --dart-define-from-file=supabase_dart_defines.json --dart-define=KIOSK_TAP_OUT_MIN_WAIT_SECONDS=10` and walk the checklist below. Record pass/fail per line in the PR description.

1. Online: chip shows **Online**; tap a known card → welcome popup with in/out matching the server's `rfid_tap_events`.
2. Disconnect the network (disable the adapter). Within ~15 s the chip turns **Offline · 0 pending**.
3. Tap a known student card → welcome popup appears instantly, chip shows **Offline · 1 pending**.
4. Tap the same card again within 5 s → same direction, pending stays 1.
5. Wait 10 s, tap again → the opposite direction, pending 2. Tap a third time → "You have already tapped in and out for today."
6. Tap an unknown card → "not recognised" state, pending increments.
7. Tap a Security staff card → report screen opens; search a student number prefix; pick offenses; confirm → slip preview prints; chip pending increments.
8. Reconnect. Within ~15 s the chip shows **Syncing** then **Online**; in Supabase `rfid_tap_events` shows the offline taps with their **original `tapped_at`**, and `admission_slips`/`student_violations` contain the slip.
9. Force a rejection (deactivate `KIOSK-MAIN-001` in `rfid_readers`, tap offline, reconnect, then reactivate): chip shows **1 failed**, the dialog lists the "deactivated" message.
10. Restart the app while offline with a populated cache: identification still works.

- [ ] **Step 4: Write the package README**

`packages/kiosk_offline/README.md` — sections: what the package does (one paragraph), the architecture table from the spec, "Keeping the rules in sync" (a SQL change in `record_rfid_tap` requires matching `tap_rules.dart` + `tap_rules_test.dart`), the `KIOSK_TAP_OUT_MIN_WAIT_SECONDS` define, the `sqlite3.dll` note for `flutter test` on Windows, and the manual checklist from Step 3.

- [ ] **Step 5: Update the spec with the three amendments**

In the spec file: (a) in "Tap flow" replace "(online or offline)" framing with the server-first-when-online, local-when-offline description from this plan's Amendment 1; (b) in "Reference data sync" replace the delta/daily-full wording with "full atomic replace every 5 minutes and on reconnect"; (c) in the schema line for `outbox` drop `tapped_at` and say "ordered by `id`". Add a final section "Amendments (2026-10-04, from planning)" listing the three points.

- [ ] **Step 6: Confirm the Netlify (Dart 3.5.4) constraint**

Re-run the Task 1 `pick_pins.dart` against `drift`, `sqlite3`, `sqlite3_flutter_libs`, `path_provider` and confirm the pinned versions in `packages/kiosk_offline/pubspec.yaml` still match its output. After merging to a branch, check the Netlify deploy preview resolves and builds; if `flutter pub get` there reports an SDK mismatch for a transitive package, add an exact pin for it in `packages/kiosk_offline/pubspec.yaml` (not a root `dependency_overrides`).

- [ ] **Step 7: Commit**

```bash
git add packages/kiosk_offline/README.md docs/superpowers/specs/2026-10-04-kiosk-offline-first-drift-design.md
git commit -m "docs(kiosk_offline): README, manual checklist and spec amendments" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage**

| Spec requirement | Task |
|---|---|
| New package `packages/kiosk_offline`, host calls it | 1, 7, 8 |
| Local DB: caches, `local_taps`, `outbox`, `sync_meta` | 3 |
| Reference sync (startup, every 5 min, on reconnect), local-first lookups | 6, 8 |
| `TapRules` port incl. Manila 6:30 PM rollover, debounce, one in/out, unknown card | 2 |
| Tap flow with provisional local decision, true `tappedAt` | 4 |
| Outbox: order, backoff cap 60 s, rejection parking, slip duplicate = success | 5 (`Outbox`), 8 (`23505`) |
| Drain triggers: after enqueue, 15 s/60 s timer, startup | 6 (`requestDrain`, `start`/`tick`), 7 (`_afterWrite`, `start`) |
| Slips/violations offline | 7, 8 |
| Status chip + diagnostics (read-only) | 9 |
| Connectivity = HTTPS probe, not adapter state | 8 (`ping`) |
| `tapOutMinWait` single configurable constant | 2, 8 |
| Testing: rule vectors, outbox, reference sync, manual checklist | 2, 5, 6, 10 |
| Risk: Drift/Dart 3.5.4 compatibility | 1 (pins), 10 (verify) |
| Risk: unencrypted DB, unknown card until next pull | documented, not mitigated (out of scope per spec) |

Gaps found and fixed in the plan: the web build embedding the kiosk host (conditional export, Task 7/8 step 8); other-reader divergence (amendment 1, Review Focus 1); wipe-on-empty-pull (Task 6).

**Placeholder scan:** the only substituted values are the version pins in Task 1, whose source of truth is the script in Step 1. No TBD/TODO.

**Type consistency:** `KioskRemote.recordTap` named parameters (`readerUsbSerial`, `rfidUid`, `tappedAt`) match `FakeRemote`, `SupabaseKioskRemote`, `TapEngine` and `Outbox`. Outbox tap payload keys (`readerUsbSerial`, `rfidUid`, `tappedAt`, `localTapId`) match between `TapEngine._payload` and `Outbox._send`. `SlipSubmission.toJson/fromJson` keys match. `TapOutcome` fields (`direction`, `studentId`, `student`) are used identically in `TapEngine`, the host and tests. `SyncStatus(online, pending, rejected)` is used identically in `KioskOfflineImpl`, the chip and tests. Drift companion names (`<RowName>Companion`) are flagged to verify against the generated file in Task 3 Step 5.

**Review Focus coverage:** 1 → Task 5 test "server direction replaces…"; 2 → Task 6 two tests; 3 → Task 5 replay test; 4 → Task 2 UTC-5 rollover test; 5 → Task 8 `openOfflineOrNull` test.
