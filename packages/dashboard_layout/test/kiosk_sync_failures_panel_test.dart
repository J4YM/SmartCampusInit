import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

KioskSyncFailure _f(
  String id, {
  bool open = true,
  String? name = 'Juan Dela Cruz',
  String reason = 'You have already tapped in and out for today.',
  String kind = 'tap',
  String? dismissedBy,
  String? note,
}) =>
    KioskSyncFailure(
      id: id,
      readerUsbSerial: 'KIOSK-MAIN-001',
      kind: kind,
      occurredAt: DateTime.utc(2026, 10, 5, 4, 57),
      reason: reason,
      reportedAt: DateTime.utc(2026, 10, 5, 5, 0),
      isOpen: open,
      rfidUid: '4042243583',
      studentName: name,
      dismissedAt: open ? null : DateTime.utc(2026, 10, 5, 6, 0),
      dismissedBy: dismissedBy,
      dismissNote: note,
    );

void main() {
  _fromJsonTests();
  Future<void> pump(
    WidgetTester tester, {
    required Future<List<KioskSyncFailure>> Function() load,
    Future<void> Function(List<String>, String?)? onDismiss,
  }) async {
    tester.view.physicalSize = const Size(1500, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: KioskSyncFailuresPanel(
            loadFailures: load,
            onDismiss: onDismiss ?? (_, __) async {},
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('shows each open failure with student, kiosk and the real reason',
      (tester) async {
    await pump(tester, load: () async => [_f('a'), _f('b', name: null, reason: 'permission denied', kind: 'slip')]);

    expect(find.text('Juan Dela Cruz'), findsOneWidget);
    expect(find.text('Unknown card'), findsOneWidget);
    expect(find.text('KIOSK-MAIN-001'), findsNWidgets(2));
    expect(find.text('You have already tapped in and out for today.'), findsOneWidget);
    expect(find.text('permission denied'), findsOneWidget);
    expect(find.text('Card tap'), findsOneWidget);
    expect(find.text('Violation report'), findsOneWidget);
    expect(find.text('Open (2)'), findsOneWidget);
  });

  testWidgets('dismissing one item asks for a note and passes only that id',
      (tester) async {
    final calls = <(List<String>, String?)>[];
    var loads = 0;
    await pump(
      tester,
      load: () async {
        loads++;
        return [_f('a'), _f('b')];
      },
      onDismiss: (ids, note) async => calls.add((ids, note)),
    );

    await tester.tap(find.byKey(const Key('dismiss-a')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('dismiss-note')), '  Duplicate tap  ');
    await tester.tap(find.byKey(const Key('dismiss-confirm')));
    await tester.pumpAndSettle();

    expect(calls, hasLength(1));
    expect(calls.single.$1, ['a']);
    expect(calls.single.$2, 'Duplicate tap');
    expect(loads, 2, reason: 'the list reloads after dismissing');
  });

  testWidgets('cancelling the dialog dismisses nothing', (tester) async {
    var dismissed = false;
    await pump(
      tester,
      load: () async => [_f('a')],
      onDismiss: (_, __) async => dismissed = true,
    );

    await tester.tap(find.byKey(const Key('dismiss-a')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(dismissed, isFalse);
  });

  testWidgets('Clear all open dismisses every open id, with no note when blank',
      (tester) async {
    final calls = <(List<String>, String?)>[];
    await pump(
      tester,
      load: () async => [_f('a'), _f('b'), _f('c', open: false, dismissedBy: 'Maria')],
      onDismiss: (ids, note) async => calls.add((ids, note)),
    );

    await tester.tap(find.byKey(const Key('clear-all-failures')));
    await tester.pumpAndSettle();
    expect(find.text('Dismiss 2 failed items?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('dismiss-confirm')));
    await tester.pumpAndSettle();

    expect(calls.single.$1, ['a', 'b'], reason: 'already-dismissed c is excluded');
    expect(calls.single.$2, isNull);
  });

  testWidgets('the Dismissed filter shows history with who dismissed it and why',
      (tester) async {
    await pump(
      tester,
      load: () async => [
        _f('a'),
        _f('c', open: false, dismissedBy: 'Maria Santos', note: 'Duplicate tap'),
      ],
    );

    expect(find.textContaining('Maria Santos'), findsNothing);
    await tester.tap(find.byKey(const Key('filter-dismissed')));
    await tester.pumpAndSettle();

    expect(find.text('Dismissed by Maria Santos'), findsOneWidget);
    expect(find.textContaining('Duplicate tap'), findsOneWidget);
    expect(find.byKey(const Key('dismiss-c')), findsNothing,
        reason: 'a dismissed row has no Dismiss button');
    expect(find.byKey(const Key('clear-all-failures')), findsNothing);
  });

  testWidgets('empty state when nothing has failed', (tester) async {
    await pump(tester, load: () async => const []);
    expect(find.textContaining('No failed kiosk items'), findsOneWidget);
    expect(find.byKey(const Key('clear-all-failures')), findsNothing);
  });

  testWidgets('a load error is shown with a hint and can be retried',
      (tester) async {
    var attempts = 0;
    await pump(
      tester,
      load: () async {
        attempts++;
        if (attempts == 1) throw 'relation "kiosk_sync_failures" does not exist';
        return [_f('a')];
      },
    );

    expect(find.byKey(const Key('failures-error')), findsOneWidget);
    expect(find.textContaining('add_kiosk_sync_failures.sql'), findsOneWidget);

    await tester.tap(find.byKey(const Key('retry-failures')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('failures-error')), findsNothing);
    expect(find.text('Juan Dela Cruz'), findsOneWidget);
  });

  testWidgets('a failing dismiss tells the user and keeps the row', (tester) async {
    await pump(
      tester,
      load: () async => [_f('a')],
      onDismiss: (_, __) async => throw 'Only Admin or IT Technician accounts can dismiss.',
    );

    await tester.tap(find.byKey(const Key('dismiss-a')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dismiss-confirm')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not dismiss'), findsOneWidget);
    expect(find.byKey(const Key('dismiss-a')), findsOneWidget);
  });
}

void _fromJsonTests() {
  group('KioskSyncFailure.fromJson', () {
    test('maps a full open row', () {
      final f = KioskSyncFailure.fromJson({
        'id': 'abc',
        'reader_usb_serial': 'KIOSK-MAIN-001',
        'kind': 'tap',
        'rfid_uid': '4042243583',
        'student_name': ' Juan Dela Cruz ',
        'occurred_at': '2026-10-05T04:57:19.314295+00:00',
        'reason': 'You have already tapped in and out for today.',
        'status': 'open',
        'reported_at': '2026-10-05T05:00:00+00:00',
        'dismissed_at': null,
        'dismissed_by': null,
        'dismiss_note': null,
      });
      expect(f.isOpen, isTrue);
      expect(f.studentName, 'Juan Dela Cruz');
      expect(f.kind, 'tap');
      expect(f.occurredAt.toUtc(), DateTime.utc(2026, 10, 5, 4, 57, 19, 314, 295));
      expect(f.dismissedAt, isNull);
    });

    test('maps a dismissed slip row and tolerates missing optional fields', () {
      final f = KioskSyncFailure.fromJson({
        'id': 'x',
        'kind': 'slip',
        'status': 'dismissed',
        'reported_at': '2026-10-05T05:00:00+00:00',
        'dismissed_at': '2026-10-05T06:00:00+00:00',
        'dismissed_by': 'Maria Santos',
        'dismiss_note': '   ',
      });
      expect(f.isOpen, isFalse);
      expect(f.kind, 'slip');
      expect(f.readerUsbSerial, 'Unknown kiosk');
      expect(f.reason, 'Rejected by the server.');
      expect(f.dismissedBy, 'Maria Santos');
      expect(f.dismissNote, isNull, reason: 'a blank note is treated as none');
      expect(f.occurredAt, f.reportedAt, reason: 'falls back to the report time');
    });

    test('an unexpected kind or status is handled safely', () {
      final f = KioskSyncFailure.fromJson({
        'id': 'y',
        'kind': 'something-new',
        'status': 'weird',
        'reported_at': '2026-10-05T05:00:00+00:00',
      });
      expect(f.kind, 'tap');
      expect(f.isOpen, isTrue, reason: 'only an explicit dismissed status closes it');
    });
  });
}
