import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guidance_counselor_module/pages/dashboard/guidance_counselor_dashboard_page.dart';

void main() {
  testWidgets('Single Student Analysis tab shows the real form, not a placeholder', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(home: GuidanceCounselorDashboard()),
    );

    // Starts on Overview.
    expect(find.text('Risk Distribution'), findsOneWidget);
    expect(find.text('Student Risk Parameters'), findsNothing);

    await tester.tap(find.text('Single Student Analysis'));
    await tester.pumpAndSettle();

    expect(find.text('Student Risk Parameters'), findsOneWidget);
    expect(find.text('Analyze Risk'), findsOneWidget);
    expect(find.text('Dropout Risk %'), findsOneWidget);
    expect(find.text('Recommended Interventions'), findsOneWidget);
    // The old placeholder text must be gone.
    expect(find.text('Look up an individual student’s dropout-risk profile'), findsNothing);
  });

  testWidgets('Main content is capped at 1440px on ultra-wide viewports', (tester) async {
    await tester.binding.setSurfaceSize(const Size(2000, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(home: GuidanceCounselorDashboard()),
    );

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
      const MaterialApp(home: GuidanceCounselorDashboard()),
    );

    final navBarWidth = tester.getSize(find.byType(DashboardHeaderNavBar)).width;
    expect(navBarWidth, 1200 - 24 * 2);
  });
}
