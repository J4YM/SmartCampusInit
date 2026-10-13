import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Skeleton placeholders must follow the dashboard's theme: a fixed light
/// grey at 40-90% opacity stays bright against a dark card.
void main() {
  for (final brightness in Brightness.values) {
    testWidgets('SkeletonColors.fill follows ${brightness.name} mode',
        (tester) async {
      late BuildContext inner;
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(brightness: brightness),
        home: Builder(builder: (context) {
          inner = context;
          return const SizedBox();
        }),
      ));
      final fill = SkeletonColors.fill(inner);
      expect(
        fill,
        brightness == Brightness.dark
            ? const Color(0xFF22242B)
            : const Color(0xFFE6E6E6),
      );
      // Dark fill must be dark, never one of the old light greys.
      if (brightness == Brightness.dark) {
        expect(fill.computeLuminance(), lessThan(0.05));
      }
    });
  }
}
