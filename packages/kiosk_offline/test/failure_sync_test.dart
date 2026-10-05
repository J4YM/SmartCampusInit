import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiosk_offline/src/failure_sync.dart';
import 'package:kiosk_offline/src/kiosk_database.dart';
import 'package:kiosk_offline/src/models.dart';

import 'support/fake_remote.dart';

void main() {
  const serial = 'KIOSK-MAIN-001';
  late KioskDatabase db;
  late FakeRemote remote;
  late FailureSync sync;
  final tapAt = DateTime.utc(2026, 10, 5, 4, 57, 19);

  Future<int> enqueueTap(String uid, {String reason = 'rejected'}) async {
    final id = await db.enqueue(
      'tap',
      jsonEncode({
        'readerUsbSerial': serial,
        'rfidUid': uid,
        'tappedAt': tapAt.toIso8601String(),
        'localTapId': 1,
      }),
      tapAt,
    );
    await db.markRejected(id, 'You have already tapped in and out for today.');
    return id;
  }

  setUp(() async {
    db = KioskDatabase(NativeDatabase.memory());
    remote = FakeRemote();
    sync = FailureSync(db: db, remote: remote, readerUsbSerial: serial);
    await db.replaceReference(const ReferenceData(
      students: [
        OfflineStudent(
          id: 'stu-1',
          rfidUid: '4042243583',
          fullName: 'Juan Dela Cruz',
          studentNumber: '2024-00123',
          gradeSection: '3rd Year - BSIT 3B',
        ),
      ],
      staff: [],
      offenses: [],
      teachers: [],
    ));
  });

  tearDown(() => db.close());

  test('reports a rejected tap with the student, time and the server reason',
      () async {
    await enqueueTap('4042243583');

    await sync.sync();

    expect(remote.reported, hasLength(1));
    expect(remote.reported.single.serial, serial);
    final r = remote.reported.single.reports.single;
    expect(r.kind, 'tap');
    expect(r.rfidUid, '4042243583');
    expect(r.studentId, 'stu-1');
    expect(r.studentName, 'Juan Dela Cruz');
    expect(r.reason, 'You have already tapped in and out for today.');
    expect(r.occurredAt.isAtSameMomentAs(tapAt), isTrue);
  });

  test('an unknown card is still reported, just without a student', () async {
    await enqueueTap('9999999999');

    await sync.sync();

    final r = remote.reported.single.reports.single;
    expect(r.rfidUid, '9999999999');
    expect(r.studentId, isNull);
    expect(r.studentName, isNull);
  });

  test('a rejected violation slip is reported as a slip with its student',
      () async {
    const slip = SlipSubmission(
      slipId: 'slip-1',
      studentId: 'stu-1',
      reportedBy: 'p1',
      offenseIds: ['o1'],
      isEscalated: false,
    );
    final id = await db.enqueue('slip', jsonEncode(slip.toJson()), tapAt);
    await db.markRejected(id, 'permission denied');

    await sync.sync();

    final r = remote.reported.single.reports.single;
    expect(r.kind, 'slip');
    expect(r.studentName, 'Juan Dela Cruz');
    expect(r.reason, 'permission denied');
  });

  test('pending items are not reported, and nothing is sent when empty',
      () async {
    await db.enqueue('tap', jsonEncode({'rfidUid': 'x'}), tapAt); // pending

    final cleared = await sync.sync();

    expect(cleared, 0);
    expect(remote.reported, isEmpty);
  });

  test('a dismissed failure is removed locally, clearing the failed count',
      () async {
    final id = await enqueueTap('4042243583');
    final row = (await db.rejectedEntries()).single;
    expect(await db.rejectedCount(), 1);

    remote.dismissedKeys = {failureKey(serial, row)};
    final cleared = await sync.sync();

    expect(cleared, 1);
    expect(await db.rejectedCount(), 0);
    expect((await db.diagnostics()).where((d) => d.id == id), isEmpty);
  });

  test('only the dismissed failure is cleared; others stay for review',
      () async {
    await enqueueTap('4042243583');
    await enqueueTap('9999999999');
    final rows = await db.rejectedEntries();

    remote.dismissedKeys = {failureKey(serial, rows.first)};
    await sync.sync();

    final left = await db.rejectedEntries();
    expect(left, hasLength(1));
    expect(left.single.id, rows.last.id);
  });

  test('a key dismissed for a different kiosk never clears this one', () async {
    await enqueueTap('4042243583');
    final row = (await db.rejectedEntries()).single;

    remote.dismissedKeys = {failureKey('OTHER-KIOSK', row)};
    await sync.sync();

    expect(await db.rejectedCount(), 1);
  });

  test('keys are stable across syncs and differ per row', () async {
    await enqueueTap('A');
    await enqueueTap('B');
    await sync.sync();
    await sync.sync();

    final firstRun = remote.reported.first.reports.map((r) => r.clientKey).toList();
    final secondRun = remote.reported.last.reports.map((r) => r.clientKey).toList();
    expect(firstRun, secondRun);
    expect(firstRun.toSet(), hasLength(2));
  });

  test('if reporting fails the rows are kept and nothing throws', () async {
    await enqueueTap('4042243583');
    remote.reportError = Exception('relation "kiosk_sync_failures" does not exist');

    final cleared = await sync.sync();

    expect(cleared, 0);
    expect(await db.rejectedCount(), 1);
  });

  test('if checking dismissals fails the rows are kept and nothing throws',
      () async {
    await enqueueTap('4042243583');
    remote.dismissedFetchError = Exception('offline');

    final cleared = await sync.sync();

    expect(cleared, 0);
    expect(await db.rejectedCount(), 1);
  });
}
