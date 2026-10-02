import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:discipline_officer_module/discipline_officer_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Width of the padded content frame (the scrolling page body).
double _contentFrameWidth(WidgetTester tester) => tester
    .getSize(find
        .descendant(
          of: find.byType(DashboardPageWrapper),
          matching: find.byType(Padding),
        )
        .first)
    .width;

void main() {
  testWidgets('Main content is capped at 1440px on ultra-wide viewports', (tester) async {
    await tester.binding.setSurfaceSize(const Size(2000, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(home: DisciplineOfficerDashboardPage()),
    );
    await tester.pumpAndSettle();

    // The content frame is capped at 1440 even though the viewport itself is
    // 2000px wide...
    expect(_contentFrameWidth(tester), 1440);
    // ...while the sub-nav bar is a full-bleed strip under the header.
    expect(tester.getSize(find.byType(DashboardHeaderNavBar)).width, 2000);
  });

  testWidgets('Main content fills the viewport below the 1440px breakpoint', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(home: DisciplineOfficerDashboardPage()),
    );
    await tester.pumpAndSettle();

    expect(_contentFrameWidth(tester), 1200);
    expect(tester.getSize(find.byType(DashboardHeaderNavBar)).width, 1200);
  });
}
