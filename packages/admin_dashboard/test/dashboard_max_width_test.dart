import 'package:admin_dashboard/admin_dashboard.dart';
import 'package:admin_dashboard/pages/main_content_area.dart';
import 'package:admin_dashboard/widgets/sidebar/sidebar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Main content is capped at 1440px on ultra-wide viewports', (tester) async {
    await tester.binding.setSurfaceSize(const Size(2000, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MaterialApp(home: AdminDashboardPage()));
    await tester.pumpAndSettle();

    // MainContentArea fills whatever width DashboardPageWrapper hands it
    // (the Sidebar itself is fixed-width and untouched), so its rendered
    // width reveals the effective content width: capped at 1440 even
    // though the viewport itself is 2000px wide. Padding here is zero
    // (each routed page owns its own internal padding), unlike the other
    // modules' tab-bar-based wrapper usage.
    final contentWidth = tester.getSize(find.byType(MainContentArea)).width;
    expect(contentWidth, 1440);
  });

  testWidgets('Main content fills the viewport below the 1440px breakpoint', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MaterialApp(home: AdminDashboardPage()));
    await tester.pumpAndSettle();

    final contentWidth = tester.getSize(find.byType(MainContentArea)).width;
    final sidebarWidth = tester.getSize(find.byType(Sidebar)).width;
    expect(contentWidth, 1200 - sidebarWidth);
  });
}
