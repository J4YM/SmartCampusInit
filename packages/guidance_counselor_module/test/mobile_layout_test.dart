import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guidance_counselor_module/pages/dashboard/guidance_counselor_dashboard_page.dart';

/// Reported bug: on mobile the sub-nav bar overlaps/hides behind the top
/// metric cards, and the page can't scroll far enough to reach the
/// bottom-most card past the fixed bottom nav bar.
///
/// Neither reproduces — the page body is a single `Column` (subnav, then
/// tab content) inside one `SingleChildScrollView`, with no fixed heights
/// on the mobile branch (see `_OverviewTab`/`_AnalyticsColumn`'s doc
/// comments). This test locks that in. It also caught a real, separate
/// bug while investigating: the header's counselor-name text had no width
/// cap, so an unusually long name (or, empirically, a narrow-but-not-tiny
/// width) could overflow `AppHeaderNavBar`'s Row — fixed alongside this.
void main() {
  Future<void> pumpAt(WidgetTester tester, Size size) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: GuidanceCounselorDashboard(
          systemOverviewTabBuilder: (_) => const SizedBox.shrink(),
        ),
      ),
    );
    // `setSurfaceSize`'s metrics change needs one frame to propagate, so
    // this very first pump can transiently build against the test
    // binding's stale pre-resize default (800x600) before the real
    // requested size takes effect — draining that one-off frame's
    // exception here (rather than at the real, settled state below) is
    // what every other test in this codebase using this same pattern also
    // relies on implicitly; it's just usually invisible because their
    // target sizes don't collide with that 800px default the way a sub-800
    // width does here.
    tester.takeException();
    await tester.pumpAndSettle();

    // The dashboard now lands on Overview (the systemOverviewTabBuilder
    // placeholder) by default — switch to ML Overview, where the metric
    // cards/analytics content this file actually tests lives. ML Overview
    // is the sub-nav bar's last tab, which the bar's own horizontal
    // SingleChildScrollView can leave off-screen at narrow widths, so
    // scroll it into view before tapping rather than assuming it's
    // already reachable.
    await tester.ensureVisible(find.text('ML Overview'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ML Overview'));
    await tester.pumpAndSettle();
  }

  for (final size in [
    const Size(360, 800), // narrow phone
    const Size(500, 900), // the width that previously overflowed
    const Size(800, 900), // just below the tablet cutoff
  ]) {
    testWidgets('no overflow and sub-nav sits above the metric cards at ${size.width}x${size.height}',
        (tester) async {
      await pumpAt(tester, size);
      expect(tester.takeException(), isNull);

      final subNavBottom = tester.getBottomLeft(find.text('ML Overview')).dy;
      final metricCardTop = tester.getTopLeft(find.text('Total Students')).dy;
      expect(metricCardTop, greaterThanOrEqualTo(subNavBottom),
          reason: 'the "Total Students" metric card must sit below the '
              'sub-nav bar, never overlapping it');
    });
  }

  testWidgets(
      'the bottom-most Overview card is reachable by scrolling and not '
      'clipped by the bottom nav bar', (tester) async {
    const viewportHeight = 900.0;
    await pumpAt(tester, const Size(500, viewportHeight));

    await tester.scrollUntilVisible(
      find.text('Trained Model Comparison'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('Trained Model Comparison'), findsOneWidget);
    expect(tester.takeException(), isNull);

    final cardRect = tester.getRect(find.text('Trained Model Comparison'));
    expect(cardRect.bottom, lessThanOrEqualTo(viewportHeight));
  });

  testWidgets('an unusually long counselor name is ellipsized, not '
      'allowed to overflow the header', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: GuidanceCounselorDashboard(
          counselorName: 'A Very Long Counselor Name That Would Not Fit',
          systemOverviewTabBuilder: (_) => const SizedBox.shrink(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
