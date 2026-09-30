import 'package:capstone_dashboard/data/guidance_counselor_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('gwaToPercentage', () {
    test('maps exact standard breakpoints to their known percentage', () {
      expect(gwaToPercentage(1.00), 100);
      expect(gwaToPercentage(1.50), 94);
      expect(gwaToPercentage(2.00), 88);
      expect(gwaToPercentage(3.00), 76);
    });

    test('interpolates linearly between breakpoints', () {
      // Midpoint of 1.00 (100) and 1.25 (97) is 98.5.
      expect(gwaToPercentage(1.125), closeTo(98.5, 0.001));
    });

    test('clamps anything better than 1.00 to 100', () {
      expect(gwaToPercentage(0.5), 100);
    });

    test('extrapolates below 76% for a cumulative GPA worse than 3.00 '
        '(possible once failed subjects are averaged in), clamped at 0',
        () {
      final worseThanThreeOh = gwaToPercentage(3.25);
      expect(worseThanThreeOh, lessThan(76));

      expect(gwaToPercentage(50.0), 0.0);
    });

    test('a higher (worse) GPA never produces a higher percentage than a '
        'lower (better) one', () {
      expect(gwaToPercentage(1.42), greaterThan(gwaToPercentage(2.50)));
    });
  });
}
