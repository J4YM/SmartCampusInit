import 'package:admin_dashboard/admin_dashboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester, {WidgetBuilder? kioskSync}) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      home: AdminDashboardPage(kioskSyncFailuresPageBuilder: kioskSync),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('the sidebar lists Kiosk Sync Failures', (tester) async {
    await pump(tester);
    expect(find.text('Kiosk Sync Failures'), findsOneWidget);
  });

  testWidgets('with a builder, opening it shows the supplied page with a title',
      (tester) async {
    await pump(
      tester,
      kioskSync: (_) => const Text('KIOSK PANEL CONTENT'),
    );

    await tester.tap(find.text('Kiosk Sync Failures'));
    await tester.pumpAndSettle();

    expect(find.text('KIOSK PANEL CONTENT'), findsOneWidget);
    // Sidebar entry + the page's own heading.
    expect(find.text('Kiosk Sync Failures'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('without a builder (demo mode) it falls back to the placeholder',
      (tester) async {
    await pump(tester);

    await tester.tap(find.text('Kiosk Sync Failures'));
    await tester.pumpAndSettle();

    expect(find.text('Kiosk Sync Failures content goes here.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('other routes are unaffected', (tester) async {
    await pump(
      tester,
      kioskSync: (_) => const Text('KIOSK PANEL CONTENT'),
    );

    await tester.tap(find.text('Kiosk Sync Failures'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reports & Exports'));
    await tester.pumpAndSettle();

    expect(find.text('KIOSK PANEL CONTENT'), findsNothing);
  });
}
