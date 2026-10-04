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
