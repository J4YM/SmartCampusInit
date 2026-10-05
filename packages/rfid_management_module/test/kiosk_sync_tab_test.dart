import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rfid_management_module/rfid_management_module.dart';

void main() {
  Widget page({WidgetBuilder? kioskSync}) => MaterialApp(
        home: ItTechnicianDashboardPage(
          studentRecordsTabBuilder: (_) =>
              const Center(child: Text('Student Records Content')),
          readerDevicesTabBuilder: (_) =>
              const Center(child: Text('Reader Devices Content')),
          technicalIssuesTabBuilder: (_) =>
              const Center(child: Text('Technical Issues Content')),
          rfidRequestsTabBuilder: (_) =>
              const Center(child: Text('RFID Requests Content')),
          idTemplatesTabBuilder: (_) =>
              const Center(child: Text('ID Templates Content')),
          kioskSyncTabBuilder: kioskSync,
        ),
      );

  void desktop(WidgetTester tester) {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  testWidgets('no Kiosk Sync tab when the host supplies no builder (demo mode)',
      (tester) async {
    desktop(tester);
    await tester.pumpWidget(page());
    expect(find.text('Kiosk Sync'), findsNothing);
    // The five existing tabs are untouched.
    for (final t in [
      'Student Records',
      'Reader Devices',
      'Technical Issues',
      'RFID Requests',
      'ID Templates',
    ]) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
  });

  testWidgets('with a builder, a Kiosk Sync tab appears and shows its content',
      (tester) async {
    desktop(tester);
    await tester.pumpWidget(
      page(kioskSync: (_) => const Center(child: Text('Kiosk Sync Content'))),
    );

    expect(find.text('Kiosk Sync'), findsOneWidget);
    expect(find.text('Kiosk Sync Content'), findsNothing,
        reason: 'it is not the default tab');

    await tester.tap(find.text('Kiosk Sync'));
    await tester.pumpAndSettle();
    expect(find.text('Kiosk Sync Content'), findsOneWidget);
    expect(find.text('Student Records Content'), findsNothing);

    // And the other tabs still switch away from it.
    await tester.tap(find.text('Reader Devices'));
    await tester.pumpAndSettle();
    expect(find.text('Reader Devices Content'), findsOneWidget);
    expect(find.text('Kiosk Sync Content'), findsNothing);
  });
}
