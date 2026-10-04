import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guidance_counselor_module/pages/dashboard/guidance_counselor_dashboard_page.dart';

final _violet = {
  const Color(0xFF5B21B6),
  const Color(0xFF8B5CF6),
  const Color(0xFFA78BFA),
  const Color(0xFFC4B5FD),
};

/// Lighter colors have a higher luminance.
bool _lightToDark(List<Color> colors) {
  for (var i = 1; i < colors.length; i++) {
    if (colors[i].computeLuminance() >= colors[i - 1].computeLuminance()) {
      return false;
    }
  }
  return true;
}

void main() {
  testWidgets(
      'ML Overview charts: Risk Distribution and Trained Model Comparison '
      'both run from the lightest color (first) to the darkest (last)',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: GuidanceCounselorDashboard(
        systemOverviewTabBuilder: (_) => const SizedBox.shrink(),
      ),
    ));
    await tester.tap(find.text('ML Overview'));
    await tester.pumpAndSettle();
    expect(find.text('Risk Distribution'), findsOneWidget);
    expect(find.text('Trained Model Comparison'), findsOneWidget);

    // Legend dots (round) and bars (plain colored boxes), in violet.
    final dots = <({double x, double y, Color color})>[];
    for (final element in find.byType(Container).evaluate()) {
      final decoration = (element.widget as Container).decoration;
      if (decoration is! BoxDecoration ||
          decoration.shape != BoxShape.circle ||
          !_violet.contains(decoration.color)) {
        continue;
      }
      final rect = tester.getRect(find.byWidget(element.widget));
      dots.add((x: rect.left, y: rect.top, color: decoration.color!));
    }
    final bars = <({double x, double y, Color color})>[];
    for (final element in find.byType(ColoredBox).evaluate()) {
      final color = (element.widget as ColoredBox).color;
      if (!_violet.contains(color)) continue;
      final rect = tester.getRect(find.byWidget(element.widget));
      bars.add((x: rect.left, y: rect.top, color: color));
    }

    // Two legends: Risk Distribution (above) and the model series (below),
    // each four dots in a row.
    dots.sort((a, b) => a.y != b.y ? a.y.compareTo(b.y) : a.x.compareTo(b.x));
    expect(dots, hasLength(8));
    final riskLegend = dots.sublist(0, 4);
    final modelLegend = dots.sublist(4);
    for (final legend in [riskLegend, modelLegend]) {
      expect(_lightToDark([for (final d in legend) d.color]), isTrue,
          reason: 'legend: ${[for (final d in legend) d.color]}');
    }

    // Each model's group of four bars: same order and colors as its legend.
    bars.sort((a, b) => a.x.compareTo(b.x));
    expect(bars.length % 4, 0);
    expect(bars, isNotEmpty);
    for (var i = 0; i < bars.length; i += 4) {
      final group = [for (final b in bars.sublist(i, i + 4)) b.color];
      expect(_lightToDark(group), isTrue, reason: 'bars: $group');
      expect(group, [for (final d in modelLegend) d.color]);
    }
  });

  testWidgets(
      'Risk Distribution: Mild is the lightest and first, No decline the '
      'darkest and last, and every donut segment matches its legend color',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: GuidanceCounselorDashboard(
        systemOverviewTabBuilder: (_) => const SizedBox.shrink(),
        // Distinct counts, so each segment can be told apart by its value.
        initialRiskDistribution: const RiskDistributionModel(
            noDecline: 40, severe: 10, moderate: 20, mild: 30),
      ),
    ));
    await tester.tap(find.text('ML Overview'));
    await tester.pumpAndSettle();

    // Legend: labels left to right, with the dot beside each.
    const order = ['Mild', 'Moderate', 'Severe', 'No decline'];
    final labelXs = [
      for (final label in order) tester.getTopLeft(find.text(label)).dx,
    ];
    expect(labelXs, orderedEquals([...labelXs]..sort()),
        reason: 'legend order left to right: $order');
    // Dots, row by row from the top: the first four are Risk Distribution's.
    final dots = <({double x, double y, Color color})>[];
    for (final element in find.byType(Container).evaluate()) {
      final decoration = (element.widget as Container).decoration;
      if (decoration is! BoxDecoration ||
          decoration.shape != BoxShape.circle ||
          !_violet.contains(decoration.color)) {
        continue;
      }
      final rect = tester.getRect(find.byWidget(element.widget));
      dots.add((x: rect.left, y: rect.top, color: decoration.color!));
    }
    dots.sort((a, b) => a.y != b.y ? a.y.compareTo(b.y) : a.x.compareTo(b.x));
    final legendColors = [for (final d in dots.take(4)) d.color];
    expect(_lightToDark(legendColors), isTrue);

    // The donut itself: same labels in the same order, each segment holding
    // that label's count and exactly the color of the legend dot beside it.
    final donut = find.byWidgetPredicate((w) =>
        w is CustomPaint &&
        w.painter.runtimeType.toString() == '_DonutChartPainter');
    expect(donut, findsOneWidget);
    final segments = (tester.widget<CustomPaint>(donut).painter as dynamic)
        .segments as List<dynamic>;
    expect([for (final s in segments) s.label], order);
    expect([for (final s in segments) (s.value as double).round()],
        [30, 20, 10, 40]);
    expect([for (final s in segments) s.color as Color], legendColors);
  });
}
