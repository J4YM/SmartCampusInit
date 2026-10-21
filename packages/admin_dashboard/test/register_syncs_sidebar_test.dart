import 'package:admin_dashboard/admin_dashboard.dart';
import 'package:admin_dashboard/widgets/sidebar/sidebar_accordion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Register Syncs is a top-level sidebar entry, on the same level as System
/// Config, Academic Term and the other standalone items — not a sub-item
/// inside the System Config group.
void main() {
  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: AdminDashboardPage()));
    await tester.pumpAndSettle();
  }

  Finder inAccordion(String text) => find.descendant(
        of: find.byType(SidebarAccordion),
        matching: find.text(text),
      );

  testWidgets('it is not inside any group, unlike the System Config items',
      (tester) async {
    await pump(tester);

    expect(inAccordion('ML Model'), findsOneWidget);
    expect(inAccordion('Notifications'), findsOneWidget);
    expect(inAccordion('Register Syncs'), findsNothing);
    expect(find.text('Register Syncs'), findsOneWidget);
  });

  testWidgets('it sits after the System Config group, before Academic Term',
      (tester) async {
    await pump(tester);

    final notifications = tester.getTopLeft(find.text('Notifications')).dy;
    final registerSyncs = tester.getTopLeft(find.text('Register Syncs')).dy;
    final academicTerm = tester.getTopLeft(find.text('Academic Term')).dy;
    expect(registerSyncs, greaterThan(notifications));
    expect(registerSyncs, lessThan(academicTerm));
  });

  testWidgets('collapsing System Config leaves it in place', (tester) async {
    await pump(tester);
    final before = tester.getTopLeft(find.text('Register Syncs'));

    await tester.tap(find.text('System Config'));
    await tester.pumpAndSettle();

    final after = tester.getTopLeft(find.text('Register Syncs'));
    expect(find.text('Register Syncs').hitTestable(), findsOneWidget);
    // It moved up into the space the group gave back, but is still there.
    expect(after.dx, before.dx);
    expect(after.dy, lessThan(before.dy));
  });

  testWidgets('selecting it opens the Register Syncs page', (tester) async {
    await pump(tester);

    await tester.tap(find.text('Register Syncs'));
    await tester.pumpAndSettle();

    // Sidebar entry + the page's own heading.
    expect(find.text('Register Syncs'), findsNWidgets(2));
    expect(find.text('No registration activity yet.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
