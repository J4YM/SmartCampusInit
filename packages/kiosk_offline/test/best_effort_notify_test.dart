import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiosk_offline/src/kiosk_database.dart';
import 'package:kiosk_offline/src/kiosk_offline_api.dart';
import 'package:kiosk_offline/src/kiosk_offline_impl.dart';
import 'package:kiosk_offline/src/models.dart';

import 'support/fake_remote.dart';

const _ana = OfflineStudent(
  id: 's1',
  rfidUid: 'UID-1',
  fullName: 'Ana Cruz',
  studentNumber: '2024-0001',
  gradeSection: '1st Year - BSIT-1A',
);

/// Status queries fail (transient SQLite trouble) while writes still work.
class _StatusFailingDb extends KioskDatabase {
  _StatusFailingDb(super.e);
  bool failRejected = false;
  bool failPendingAfterEnqueue = false;
  bool _enqueued = false;

  @override
  Future<int> rejectedCount() =>
      failRejected ? Future.error(StateError('db busy')) : super.rejectedCount();

  @override
  Future<int> pendingCount() => failPendingAfterEnqueue && _enqueued
      ? Future.error(StateError('db busy'))
      : super.pendingCount();

  @override
  Future<int> enqueue(String type, String payloadJson, DateTime now) async {
    final id = await super.enqueue(type, payloadJson, now);
    _enqueued = true;
    return id;
  }
}

void main() {
  late _StatusFailingDb db;
  late FakeRemote remote;
  late DateTime now;
  late KioskOfflineImpl svc;

  setUp(() async {
    db = _StatusFailingDb(NativeDatabase.memory());
    remote = FakeRemote()
      ..reference = const ReferenceData(
        students: [_ana],
        staff: [],
        offenses: [],
        teachers: [],
      )
      ..studentIdFor = ((uid) => uid == 'UID-1' ? 's1' : null);
    now = DateTime.parse('2026-10-05T08:00:00+08:00');
    svc = KioskOfflineImpl(
      db: db,
      remote: remote,
      readerUsbSerial: 'KIOSK-MAIN-001',
      now: () => now,
    );
    await svc.syncNow();
    remote.pingResult = false;
    await svc.syncNow();
  });

  tearDown(() => svc.dispose());

  test('I5: a failing status query after the write does not replace the tap result', () async {
    db.failRejected = true;
    final out = await svc.recordTap('UID-1');
    expect(out.direction, 'in');
  });

  test('I5: a failing status query does not mask TapRejectedException', () async {
    await svc.recordTap('UID-1');
    db.failRejected = true;
    now = now.add(const Duration(minutes: 5));
    await expectLater(svc.recordTap('UID-1'), throwsA(isA<TapRejectedException>()));
  });

  test('I5: submitSlip with a failing status after enqueue does not throw', () async {
    db.failPendingAfterEnqueue = true;
    db.failRejected = true;
    const slip = SlipSubmission(
        slipId: 'slip-x', studentId: 's1', reportedBy: 'p1', offenseIds: ['o1']);
    await svc.submitSlip(slip);
  });
}
