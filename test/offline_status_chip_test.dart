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

  Completer<SyncStatus>? gate;
  @override
  Future<SyncStatus> currentStatus() => gate?.future ?? Future.value(_current);
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
    await tester.pump(); // deliver the stream event (microtask)
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

  testWidgets('a stream event is not overwritten by a slower initial status', (tester) async {
    final offline = _FakeOffline(const SyncStatus(online: true, pending: 0, rejected: 0))
      ..gate = Completer<SyncStatus>();
    await tester.pumpWidget(_host(offline));
    offline.push(const SyncStatus(online: false, pending: 2, rejected: 0));
    await tester.pump();
    offline.gate!.complete(const SyncStatus(online: true, pending: 0, rejected: 0));
    await tester.pump();
    await tester.pump();
    expect(find.text('Offline · 2 pending'), findsOneWidget);
  });

  testWidgets('the chip never takes focus from the RFID text field', (tester) async {
    final offline = _FakeOffline(const SyncStatus(online: true, pending: 0, rejected: 0));
    await tester.pumpWidget(_host(offline));
    await tester.pump();
    final ink = tester.widget<InkWell>(find.byType(InkWell));
    expect(ink.canRequestFocus, isFalse);
  });

  test('formatDiagnosticTime is a 12-hour local time without seconds', () {
    expect(formatDiagnosticTime(DateTime(2026, 10, 5, 8, 0)), '2026-10-05 8:00 AM');
    expect(formatDiagnosticTime(DateTime(2026, 10, 5, 0, 5, 33, 123, 456)), '2026-10-05 12:05 AM');
    expect(formatDiagnosticTime(DateTime(2026, 10, 5, 13, 7)), '2026-10-05 1:07 PM');
    expect(formatDiagnosticTime(DateTime(2026, 10, 5, 12, 0)), '2026-10-05 12:00 PM');
  });

  testWidgets('diagnostics tells staff where failed items get cleared', (tester) async {
    final offline = _FakeOffline(const SyncStatus(online: true, pending: 0, rejected: 1))
      ..rows = [
        OutboxDiagnostic(
          id: 1,
          type: 'tap',
          status: 'rejected',
          attempts: 0,
          createdAt: DateTime.utc(2026, 10, 5, 0, 0),
          lastError: 'You have already tapped in and out for today.',
        ),
      ];
    await tester.pumpWidget(_host(offline));
    await tester.pump();
    await tester.tap(find.text('1 failed'));
    await tester.pumpAndSettle();

    expect(find.textContaining('IT Technician and Admin dashboards'), findsOneWidget);
    // The kiosk itself offers no way to clear them.
    expect(find.textContaining('Clear'), findsNothing);
    expect(find.textContaining('Dismiss'), findsNothing);
  });

  testWidgets('no failed-items hint when everything is merely pending', (tester) async {
    final offline = _FakeOffline(const SyncStatus(online: false, pending: 1, rejected: 0))
      ..rows = [
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
    await tester.tap(find.text('Offline · 1 pending'));
    await tester.pumpAndSettle();

    expect(find.text('Sync details'), findsOneWidget);
    expect(find.textContaining('IT Technician and Admin dashboards'), findsNothing);
  });

}
