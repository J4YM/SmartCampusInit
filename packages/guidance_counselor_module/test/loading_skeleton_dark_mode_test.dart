import 'package:dashboard_layout/dashboard_layout.dart'
    show BentoCard, DashboardSkeletonScreen, SkeletonBox, ThemeModeStore;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guidance_counselor_module/pages/dashboard/guidance_counselor_dashboard_page.dart';

/// The loading skeleton must follow the dashboard's own dark-mode toggle. It
/// used to be built with the State's bare `context`, which sits above the
/// page's Theme, so it stayed light on a dark dashboard.
void main() {
  testWidgets('the loading skeleton is dark in dark mode', (tester) async {
    // `remember` is inert in tests, so set the start-up mode directly.
    ThemeModeStore.current = ThemeMode.dark;
    addTearDown(() => ThemeModeStore.current = ThemeMode.light);
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      home: GuidanceCounselorDashboard(
        isLoading: true,
        systemOverviewTabBuilder: (_) => const SizedBox(),
      ),
    ));
    // The skeleton stands in for the ML Overview tab.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('ML Overview').first);
    // It pulses forever, so settle by pumping a few frames.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    tester.takeException();

    expect(find.byType(DashboardSkeletonScreen), findsOneWidget);

    // Placeholder bars use the dark fill, never the pale light grey.
    final bars = tester.widgetList<SkeletonBox>(find.byType(SkeletonBox));
    expect(bars, isNotEmpty);
    for (final bar in bars) {
      expect(bar.color, const Color(0xFF22242B));
    }

    // And the skeleton's cards are the dark card colour, not white.
    final cards = tester.widgetList<BentoCard>(find.descendant(
      of: find.byType(DashboardSkeletonScreen),
      matching: find.byType(BentoCard),
    ));
    expect(cards, isNotEmpty);
    for (final card in cards) {
      expect(card.backgroundColor, const Color(0xFF191A1F));
    }
  });
}
