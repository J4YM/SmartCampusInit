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
