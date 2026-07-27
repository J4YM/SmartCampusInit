import 'package:discipline_officer_module/discipline_officer_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Main content is capped at 1440px on ultra-wide viewports', (tester) async {
    await tester.binding.setSurfaceSize(const Size(2000, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(home: DisciplineOfficerDashboardPage()),
    );
    await tester.pumpAndSettle();

    // DashboardHeaderNavBar fills whatever width DashboardPageWrapper hands
    // it, so its rendered width reveals the effective content width: capped
    // at 1440 (minus the wrapper's own 24px horizontal padding on each
    // side) even though the viewport itself is 2000px wide.
    final navBarWidth = tester.getSize(find.byType(DashboardHeaderNavBar)).width;
    expect(navBarWidth, 1440 - 24 * 2);
  });

  testWidgets('Main content fills the viewport below the 1440px breakpoint', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(home: DisciplineOfficerDashboardPage()),
    );
    await tester.pumpAndSettle();

    final navBarWidth = tester.getSize(find.byType(DashboardHeaderNavBar)).width;
    expect(navBarWidth, 1200 - 24 * 2);
  });
}
