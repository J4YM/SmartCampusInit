import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guidance_counselor_module/pages/dashboard/guidance_counselor_dashboard_page.dart';

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
  testWidgets('Single Student Analysis tab shows the real form, not a placeholder', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: GuidanceCounselorDashboard(
          systemOverviewTabBuilder: (_) => const SizedBox.shrink(),
        ),
      ),
    );

    // Starts on Overview (the systemOverviewTabBuilder placeholder) —
    // switch to ML Overview first to reach the risk-analysis content.
    await tester.tap(find.text('ML Overview'));
    await tester.pumpAndSettle();
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

  testWidgets(
      'Overview tab analytics column has no nested inner scrollbar on a '
      'short desktop viewport', (tester) async {
    // Short enough that the old ConstrainedBox(maxHeight:
    // masterDetailRowMaxHeight()) around the master-detail Row would have
    // capped the analytics column below its natural content height,
    // forcing its own internal SingleChildScrollView to appear.
    await tester.binding.setSurfaceSize(const Size(1400, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: GuidanceCounselorDashboard(
          systemOverviewTabBuilder: (_) => const SizedBox.shrink(),
        ),
      ),
    );

    // Starts on Overview (the systemOverviewTabBuilder placeholder) —
    // switch to ML Overview to reach the analytics column under test.
    await tester.tap(find.text('ML Overview'));
    await tester.pumpAndSettle();

    expect(find.text('Risk Distribution'), findsOneWidget);
    expect(find.text('Trained Model Comparison'), findsOneWidget);
    // The chart card sits under exactly one Scrollable — the page's own
    // outer SingleChildScrollView — not a second, nested one from the
    // analytics column wrapping itself when force-capped to a bounded
    // height. (A TextField elsewhere on the page has its own unrelated
    // internal Scrollable, which is why this checks ancestors of the
    // chart's own text rather than counting Scrollables page-wide.)
    expect(
      find.ancestor(
        of: find.text('Trained Model Comparison'),
        matching: find.byType(Scrollable),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Main content is capped at 1440px on ultra-wide viewports', (tester) async {
    await tester.binding.setSurfaceSize(const Size(2000, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: GuidanceCounselorDashboard(
          systemOverviewTabBuilder: (_) => const SizedBox(width: double.infinity, height: 10),
        ),
      ),
    );

    // The content frame (DashboardPageWrapper's padded box) is capped at
    // 1440 even though the viewport itself is 2000px wide...
    expect(_contentFrameWidth(tester), 1440);
    // ...while the sub-nav bar is a full-bleed strip under the header.
    expect(tester.getSize(find.byType(DashboardHeaderNavBar)).width, 2000);
  });

  testWidgets('Main content fills the viewport below the 1440px breakpoint', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: GuidanceCounselorDashboard(
          systemOverviewTabBuilder: (_) => const SizedBox(width: double.infinity, height: 10),
        ),
      ),
    );

    expect(_contentFrameWidth(tester), 1200);
    expect(tester.getSize(find.byType(DashboardHeaderNavBar)).width, 1200);
  });
}
