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

  test('two concurrent taps are serialised: one outbox entry, second echoes', () async {
    await svc.syncNow();
    remote.pingResult = false;
    await svc.syncNow();
    final a = svc.recordTap('UID-1');
    final b = svc.recordTap('UID-1');
    final results = await Future.wait<TapOutcome>([a, b]);
    expect(results[0].direction, 'in');
    expect(results[1].direction, 'in');
    expect((await svc.currentStatus()).pending, 1);
  });

  test('a rejected tap does not block a later tap', () async {
    await svc.syncNow();
    remote.tapError = RemoteRejected('Reader is deactivated.');
    final f1 = expectLater(svc.recordTap('UID-1'), throwsA(isA<TapRejectedException>()));
    // Queued behind the failing call; must still run (and fail on its own).
    final f2 = expectLater(svc.recordTap('UID-1'), throwsA(isA<TapRejectedException>()));
    await Future.wait([f1, f2]);
    remote.tapError = null;
    final out = await svc.recordTap('UID-1');
    expect(out.direction, 'in');
    expect(remote.taps, hasLength(1));
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
