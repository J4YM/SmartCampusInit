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

    // A is rejected by the server; B succeeds within the same drain.
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

  test('a malformed JSON payload is parked and later entries still drain', () async {
    await db.enqueue('tap', 'not json {', t0);
    await enqueueTap('B', t0.add(const Duration(minutes: 1)));
    final report = await outbox.drain();
    expect(report.blocked, isFalse);
    expect(report.processed, 2);
    expect(await db.rejectedCount(), 1);
    expect(await db.pendingCount(), 0);
    expect(remote.taps.map((t) => t.uid), ['B']);
    final diag = await db.diagnostics();
    expect(diag.single.lastError, contains('Malformed outbox payload'));
  });

  test('a slip payload missing a key is parked', () async {
    await db.enqueue('slip', jsonEncode({'slipId': 'x'}), t0);
    await enqueueTap('B', t0.add(const Duration(minutes: 1)));
    final report = await outbox.drain();
    expect(report.blocked, isFalse);
    expect(await db.rejectedCount(), 1);
    expect(remote.slips, isEmpty);
    expect(remote.taps.map((t) => t.uid), ['B']);
  });

  test('an unknown type with a bad payload is parked too', () async {
    await db.enqueue('mystery', 'garbage', t0);
    final report = await outbox.drain();
    expect(report.blocked, isFalse);
    expect(await db.rejectedCount(), 1);
  });

  test('a local reconciliation failure does not cause a re-send', () async {
    final failing = _FailingDb(NativeDatabase.memory())..failDirection = true;
    addTearDown(failing.close);
    await failing.enqueue(
      'tap',
      jsonEncode({
        'readerUsbSerial': 'KIOSK-MAIN-001',
        'rfidUid': 'A',
        'tappedAt': t0.toUtc().toIso8601String(),
        'localTapId': 1,
      }),
      t0,
    );
    final o = Outbox(db: failing, remote: remote, now: () => now);
    final report = await o.drain();
    expect(report.blocked, isFalse);
    expect(report.processed, 1);
    expect(remote.taps.length, 1);
    expect(await failing.pendingCount(), 0);
  });

  test('a recordAttempt failure does not escape drain and backoff still applies', () async {
    final failing = _FailingDb(NativeDatabase.memory())..failAttempt = true;
    addTearDown(failing.close);
    await failing.enqueue(
      'tap',
      jsonEncode({
        'readerUsbSerial': 'KIOSK-MAIN-001',
        'rfidUid': 'A',
        'tappedAt': t0.toUtc().toIso8601String(),
        'localTapId': null,
      }),
      t0,
    );
    remote.tapError = const SocketException('down');
    final o = Outbox(db: failing, remote: remote, now: () => now);
    expect((await o.drain()).blocked, isTrue);
    remote.tapError = null;
    final skipped = await o.drain();
    expect(skipped.blocked, isTrue);
    expect(remote.taps, isEmpty);
  });

  test('a markRejected failure does not escape drain and leaves the row pending', () async {
    final failing = _FailingDb(NativeDatabase.memory())..failReject = true;
    addTearDown(failing.close);
    await failing.enqueue('mystery', '{}', t0);
    final o = Outbox(db: failing, remote: remote, now: () => now);
    final report = await o.drain();
    expect(report.blocked, isTrue);
    expect(await failing.pendingCount(), 1);
  });
}

class _FailingDb extends KioskDatabase {
  _FailingDb(super.e);
  bool failDirection = false;
  bool failAttempt = false;
  bool failReject = false;

  @override
  Future<void> setLocalTapDirection(int id, String direction) =>
      failDirection ? Future.error(StateError('db')) : super.setLocalTapDirection(id, direction);

  @override
  Future<void> recordAttempt(int id, String error) =>
      failAttempt ? Future.error(StateError('db')) : super.recordAttempt(id, error);

  @override
  Future<void> markRejected(int id, String message) =>
      failReject ? Future.error(StateError('db')) : super.markRejected(id, message);
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
