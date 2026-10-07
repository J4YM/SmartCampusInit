import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester, double width,
      {List<KioskSyncFailure> items = const []}) async {
    tester.view.physicalSize = Size(width, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      key: UniqueKey(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: KioskSyncFailuresPanel(
            loadFailures: () async => items,
            onDismiss: (_, __) async {},
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    tester.takeException();
  }

  final open = Finder0.key('filter-open');
  final dismissed = Finder0.key('filter-dismissed');
  final refresh = Finder0.key('refresh-failures');

  testWidgets('Open, Dismissed and Refresh are compact buttons on ONE row',
      (tester) async {
    await pump(tester, 1500);
    final panel = tester.getRect(find.byType(KioskSyncFailuresPanel));
    final o = tester.getRect(open);
    final d = tester.getRect(dismissed);
    final r = tester.getRect(refresh);

    // They hug their labels instead of spanning the card.
    for (final rect in [o, d, r]) {
      expect(rect.width, lessThan(220));
      expect(rect.width, lessThan(panel.width / 4));
    }
    // One row: same vertical center, side by side, in this order.
    expect(d.center.dy, closeTo(o.center.dy, 2));
    expect(r.center.dy, closeTo(o.center.dy, 2));
    expect(o.right, lessThan(d.left));
    expect(d.right, lessThan(r.left));
    // The chips are the same size as the Refresh pill's height.
    expect(o.height, closeTo(r.height, 2));
  });

  testWidgets('still compact on a phone, and nothing overflows',
      (tester) async {
    await pump(tester, 390);
    final panel = tester.getRect(find.byType(KioskSyncFailuresPanel));
    for (final f in [open, dismissed, refresh]) {
      expect(tester.getRect(f).width, lessThan(panel.width * 0.6));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('with open failures, Clear all joins the same row',
      (tester) async {
    await pump(tester, 1500, items: [
      KioskSyncFailure(
        id: 'a',
        readerUsbSerial: 'KIOSK-1',
        kind: 'tap',
        occurredAt: DateTime.utc(2026, 10, 5, 4, 57),
        reason: 'refused',
        reportedAt: DateTime.utc(2026, 10, 5, 5),
        isOpen: true,
        rfidUid: '1',
        studentName: 'Juan',
      ),
    ]);
    final o = tester.getRect(open);
    final clear = tester.getRect(Finder0.key('clear-all-failures'));
    expect(clear.center.dy, closeTo(o.center.dy, 2));
  });

  testWidgets('tapping the chips still switches between Open and Dismissed',
      (tester) async {
    await pump(tester, 1500);
    expect(find.text('Open (0)'), findsOneWidget);
    await tester.tap(dismissed);
    await tester.pumpAndSettle();
    expect(find.text('No dismissed items yet.'), findsOneWidget);
  });
}

/// `find.byKey(const Key(...))` with a runtime string.
class Finder0 {
  static Finder key(String k) => find.byKey(Key(k));
}
