import 'package:discipline_officer_module/theme/discipline_officer_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// WCAG contrast ratio between two opaque colors.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  Future<({Color bg, Color border, Color text})> tokens(
      WidgetTester tester, Brightness brightness) async {
    late Color bg, border, text;
    await tester.pumpWidget(MaterialApp(
      key: UniqueKey(),
      theme: ThemeData(brightness: brightness),
      home: Builder(builder: (context) {
        bg = DisciplineOfficerColors.violationBannerBg(context);
        border = DisciplineOfficerColors.violationBannerBorder(context);
        text = DisciplineOfficerColors.violationBannerText(context);
        return const SizedBox();
      }),
    ));
    return (bg: bg, border: border, text: text);
  }

  for (final brightness in Brightness.values) {
    testWidgets('the violation banner is a soft pastel in $brightness mode',
        (tester) async {
      final c = await tokens(tester, brightness);

      // Opaque colors, and nothing close to the old saturated pure red.
      for (final color in [c.bg, c.border, c.text]) {
        expect(color.alpha, 0xFF);
        expect(color, isNot(const Color(0xFFFF0004)));
      }
      // Pastel: a low-chroma fill and outline. (The text in light mode is a
      // deeper rose on purpose, for contrast on the pale fill.)
      final tinted = [c.bg, c.border, if (brightness == Brightness.dark) c.text];
      for (final color in tinted) {
        expect(HSVColor.fromColor(color).saturation, lessThan(0.45),
            reason: 'too saturated: $color');
      }
      // Still reads as red/rose, not grey.
      for (final color in [c.bg, c.border, c.text]) {
        expect(color.red, greaterThan(color.green));
        expect(color.red, greaterThan(color.blue));
      }
      // The text stays comfortably readable on the fill.
      expect(_contrast(c.text, c.bg), greaterThanOrEqualTo(4.5));
    });
  }

  testWidgets('dark mode is a muted dark fill, light mode a pale blush',
      (tester) async {
    final dark = await tokens(tester, Brightness.dark);
    final light = await tokens(tester, Brightness.light);
    expect(HSLColor.fromColor(dark.bg).lightness, lessThan(0.25));
    expect(HSLColor.fromColor(light.bg).lightness, greaterThan(0.9));
  });
}
