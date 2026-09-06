import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guidance_counselor_module/pages/dashboard/guidance_counselor_dashboard_page.dart';

/// Real crash (exact repro from a live run, not a synthetic report):
/// `_QueueEmptyState` (the "No at-risk students found" empty state)
/// unconditionally forced `ConstrainedBox(minHeight: constraints.maxHeight)`
/// from its own `LayoutBuilder`, regardless of whether that height was
/// actually bounded. On mobile the Overview tab's Approval Queue card sizes
/// to its own content (unbounded height — the outer page scrolls instead;
/// only the desktop sidebar caps it to a fixed height), so
/// `constraints.maxHeight` was `double.infinity` there, and
/// `BoxConstraints(minHeight: double.infinity)` throws
/// "BoxConstraints forces an infinite height" during layout — visible to a
/// user as the whole tab failing to render. This only reproduced when the
/// approval queue was actually empty, which is why it wasn't caught by
/// earlier tests (the built-in mock data always seeds a non-empty queue).
void main() {
  testWidgets(
      'an empty approval queue renders (does not crash) on the mobile/'
      'stacked layout, where the queue card is given unbounded height',
      (tester) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: GuidanceCounselorDashboard(
          initialApprovalQueue: const [],
          systemOverviewTabBuilder: (_) => const SizedBox.shrink(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The dashboard now lands on Overview (the systemOverviewTabBuilder
    // placeholder) by default — switch to ML Overview, where the Approval
    // Queue card under test actually lives. ML Overview is the sub-nav
    // bar's last tab, which its own horizontal SingleChildScrollView can
    // leave off-screen at narrow widths, so scroll it into view first.
    await tester.ensureVisible(find.text('ML Overview'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ML Overview'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('No at-risk students found'), findsOneWidget);
  });

  testWidgets(
      'an empty approval queue also renders on the desktop master-detail '
      'layout, where the queue card gets a bounded height', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: GuidanceCounselorDashboard(
          initialApprovalQueue: const [],
          systemOverviewTabBuilder: (_) => const SizedBox.shrink(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The dashboard now lands on Overview (the systemOverviewTabBuilder
    // placeholder) by default — switch to ML Overview, where the Approval
    // Queue card under test actually lives. ML Overview is the sub-nav
    // bar's last tab, which its own horizontal SingleChildScrollView can
    // leave off-screen at narrow widths, so scroll it into view first.
    await tester.ensureVisible(find.text('ML Overview'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ML Overview'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('No at-risk students found'), findsOneWidget);
  });
}
