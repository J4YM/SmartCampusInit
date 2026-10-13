import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// "Active" and the other status pills must not glow on a dark card: the pale
/// light-mode slab becomes a deep, low-saturation tint with a softened label.
void main() {
  Future<BuildContext> pumpIn(WidgetTester tester, Brightness b) async {
    late BuildContext inner;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: b),
      home: Builder(builder: (context) {
        inner = context;
        return const SizedBox();
      }),
    ));
    return inner;
  }

  testWidgets('light mode keeps the familiar pale pills', (tester) async {
    final c = await pumpIn(tester, Brightness.light);
    expect(StatusPillColors.success(c).$1, const Color(0xFFDCFCE7));
    expect(StatusPillColors.success(c).$2, const Color(0xFF15803D));
    expect(StatusPillColors.neutral(c).$1, const Color(0xFFF1F5F9));
    expect(StatusPillColors.danger(c).$1, const Color(0xFFFEE2E2));
  });

  testWidgets('dark mode pills are deep tints, not bright slabs',
      (tester) async {
    final c = await pumpIn(tester, Brightness.dark);
    for (final pill in [
      StatusPillColors.success(c),
      StatusPillColors.neutral(c),
      StatusPillColors.danger(c),
    ]) {
      // The fill sits close to the dark card, far from the pale light fill…
      expect(pill.$1.computeLuminance(), lessThan(0.05));
      // …and the label is readable but soft (never near-white / neon).
      expect(pill.$2.computeLuminance(), greaterThan(0.2));
      expect(pill.$2.computeLuminance(), lessThan(0.6));
    }
    // Specifically softer than the old #4ADE80 / #DCFCE7 "Active".
    expect(
      StatusPillColors.success(c).$2.computeLuminance(),
      lessThan(const Color(0xFF4ADE80).computeLuminance()),
    );
  });
}
