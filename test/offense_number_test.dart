import 'package:capstone_dashboard/data/violation_notice_repository.dart';
import 'package:flutter_test/flutter_test.dart';

({String id, DateTime createdAt, String? category}) _v(
        String id, int day, String? category) =>
    (id: id, createdAt: DateTime(2026, 3, day), category: category);

void main() {
  test('ordinal labels, including the teens', () {
    expect([1, 2, 3, 4, 11, 12, 13, 21, 22, 23, 101, 111].map(ordinalLabel), [
      '1st', '2nd', '3rd', '4th', '11th', '12th', '13th', '21st', '22nd',
      '23rd', '101st', '111th',
    ]);
  });

  test('counts offenses within the Minor group by date filed', () {
    final history = [
      _v('a', 1, 'Minor'),
      _v('b', 5, 'Minor'),
      _v('c', 9, 'Minor'),
    ];
    expect(offenseNumberFor('a', history), 1);
    expect(offenseNumberFor('b', history), 2);
    expect(offenseNumberFor('c', history), 3);
  });

  test('Minor and Major offenses are counted separately', () {
    final history = [
      _v('a', 1, 'Minor'),
      _v('m1', 2, 'Major_B'),
      _v('b', 3, 'Minor'),
      _v('m2', 4, 'Major_A'),
    ];
    expect(offenseNumberFor('b', history), 2);
    expect(offenseNumberFor('m1', history), 1);
    expect(offenseNumberFor('m2', history), 2);
  });

  test('unknown violation id falls back to 1st offense', () {
    expect(offenseNumberFor('zzz', [_v('a', 1, 'Minor')]), 1);
  });
}
