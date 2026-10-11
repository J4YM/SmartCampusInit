import 'package:dashboard_layout/dashboard_layout.dart'
    show KioskSyncFailure, KioskSyncFailuresPanel;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rfid_management_module/rfid_management_module.dart';

/// Kiosk sync failures and the RFID reader devices are one tab, "Kiosk &
/// Readers": the (wide) kiosk table with the readers as a side card, stacked
/// on a narrow window.
void main() {
  _realWidgetTests();

  Widget page({WidgetBuilder? kioskSync}) => MaterialApp(
        home: ItTechnicianDashboardPage(
          studentRecordsTabBuilder: (_) =>
              const Center(child: Text('Student Records Content')),
          readerDevicesTabBuilder: (_) => Container(
            key: const Key('readers'),
            height: 120,
            alignment: Alignment.center,
            child: const Text('Reader Devices Content'),
          ),
          technicalIssuesTabBuilder: (_) =>
              const Center(child: Text('Technical Issues Content')),
          rfidRequestsTabBuilder: (_) =>
              const Center(child: Text('RFID Requests Content')),
          idTemplatesTabBuilder: (_) =>
              const Center(child: Text('ID Templates Content')),
          kioskSyncTabBuilder: kioskSync,
        ),
      );

  Widget kioskTable(BuildContext _) => Container(
        key: const Key('kiosk'),
        height: 200,
        alignment: Alignment.center,
        child: const Text('Kiosk Sync Content'),
      );

  void window(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  testWidgets('without kiosk data the tab is just Reader Devices',
      (tester) async {
    window(tester, const Size(1600, 900));
    await tester.pumpWidget(page());
    expect(find.text('Kiosk Sync'), findsNothing);
    expect(find.text('Kiosk & Readers'), findsNothing);
    for (final t in [
      'Student Records',
      'Reader Devices',
      'Technical Issues',
      'RFID Requests',
      'ID Templates',
    ]) {
      expect(find.text(t), findsOneWidget, reason: t);
    }

    await tester.tap(find.text('Reader Devices'));
    await tester.pumpAndSettle();
    expect(find.text('Reader Devices Content'), findsOneWidget);
  });

  testWidgets('with kiosk data they are one tab, not two', (tester) async {
    window(tester, const Size(1600, 900));
    await tester.pumpWidget(page(kioskSync: kioskTable));

    expect(find.text('Kiosk & Readers'), findsOneWidget);
    expect(find.text('Kiosk Sync'), findsNothing);
    expect(find.text('Reader Devices'), findsNothing,
        reason: 'no separate Reader Devices tab any more');
    // Five tabs: Student Records, Kiosk & Readers, Technical Issues,
    // RFID Requests, ID Templates.
    expect(find.text('Technical Issues'), findsOneWidget);
    expect(find.text('Kiosk Sync Content'), findsNothing,
        reason: 'not the default tab');

    await tester.tap(find.text('Kiosk & Readers'));
    await tester.pumpAndSettle();
    // Both are on screen together.
    expect(find.text('Kiosk Sync Content'), findsOneWidget);
    expect(find.text('Reader Devices Content'), findsOneWidget);
    expect(find.text('Student Records Content'), findsNothing);

    // And the other tabs still switch away from it.
    await tester.tap(find.text('Technical Issues'));
    await tester.pumpAndSettle();
    expect(find.text('Technical Issues Content'), findsOneWidget);
    expect(find.text('Kiosk Sync Content'), findsNothing);
    expect(find.text('Reader Devices Content'), findsNothing);
  });

  testWidgets('wide: the kiosk table is the main area, readers a side card',
      (tester) async {
    window(tester, const Size(1600, 900));
    await tester.pumpWidget(page(kioskSync: kioskTable));
    await tester.tap(find.text('Kiosk & Readers'));
    await tester.pumpAndSettle();

    final kiosk = tester.getRect(find.byKey(const Key('kiosk')));
    final readers = tester.getRect(find.byKey(const Key('readers')));
    expect(readers.left, greaterThan(kiosk.right - 1),
        reason: 'readers sit to the right of the kiosk table');
    expect(readers.width, 380);
    expect(kiosk.width, greaterThan(readers.width * 2),
        reason: 'the kiosk table is much wider');
    // Beside each other, tops aligned.
    expect(readers.top, closeTo(kiosk.top, 0.5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow: the readers stack under the kiosk table',
      (tester) async {
    window(tester, const Size(800, 1000));
    await tester.pumpWidget(page(kioskSync: kioskTable));
    await tester.tap(find.text('Kiosk & Readers'));
    await tester.pumpAndSettle();

    final kiosk = tester.getRect(find.byKey(const Key('kiosk')));
    final readers = tester.getRect(find.byKey(const Key('readers')));
    expect(readers.top, greaterThanOrEqualTo(kiosk.bottom));
    expect(readers.width, closeTo(kiosk.width, 0.5));
    expect(tester.takeException(), isNull);
  });
}

/// The real Kiosk Sync panel and the real Reader Devices card, together.
void _realWidgetTests() {
  Widget real() {
    final failures = [
      for (var i = 0; i < 3; i++)
        KioskSyncFailure(
          id: 'f$i',
          readerUsbSerial: 'USB-KIOSK-$i',
          kind: 'tap',
          occurredAt: DateTime(2026, 10, 11, 8, i),
          reason: 'Rejected by the server: student $i is not enrolled.',
          reportedAt: DateTime(2026, 10, 11, 9, i),
          isOpen: true,
          studentName: 'Student $i',
          rfidUid: 'AB12CD$i',
        ),
    ];
    final readers = [
      for (var i = 0; i < 4; i++)
        RfidReaderRowModel(
          id: 'r$i',
          label: 'Floor $i Reader',
          usbSerial: 'USB-$i',
          location: 'Floor $i — Hallway',
          isKioskReader: i == 0,
          isActive: true,
          isOnline: i.isEven,
          lastSeenLabel: '${i}m ago',
        ),
    ];
    return MaterialApp(
      home: ItTechnicianDashboardPage(
        studentRecordsTabBuilder: (_) => const SizedBox.shrink(),
        readerDevicesTabBuilder: (_) => RfidReaderManagementPage(
          embedded: true,
          readers: readers,
          isBusy: false,
          onAddReader: ({required label, required usbSerial, location}) async {},
          onUpdateReader: (
                  {required id,
                  required label,
                  required usbSerial,
                  location}) async {},
          onSetActive: (_, __) async {},
        ),
        technicalIssuesTabBuilder: (_) => const SizedBox.shrink(),
        rfidRequestsTabBuilder: (_) => const SizedBox.shrink(),
        idTemplatesTabBuilder: (_) => const SizedBox.shrink(),
        kioskSyncTabBuilder: (_) => KioskSyncFailuresPanel(
          loadFailures: () async => failures,
          onDismiss: (_, __) async {},
        ),
      ),
    );
  }

  for (final width in [1600.0, 1100.0, 940.0, 800.0, 600.0]) {
    testWidgets('renders both together at ${width.toInt()}px with no overflow',
        (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(real());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kiosk & Readers'));
      await tester.pumpAndSettle();

      expect(find.text('Floor 1 Reader'), findsOneWidget);
      expect(find.textContaining('USB-KIOSK-0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
