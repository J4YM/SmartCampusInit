import 'package:flutter_test/flutter_test.dart';
import 'package:capstone_dashboard/data/schedule_import/schedule_time_parsing.dart';

void main() {
  group('to24Hour', () {
    test('hour 12 stays 12 (noon)', () {
      expect(to24Hour('12:00'), '12:00');
      expect(to24Hour('12:30'), '12:30');
    });
    test('hours 1-6 become PM (add 12)', () {
      expect(to24Hour('1:00'), '13:00');
      expect(to24Hour('2:30'), '14:30');
      expect(to24Hour('6:00'), '18:00');
    });
    test('hours 7-11 stay AM (unchanged)', () {
      expect(to24Hour('7:00'), '07:00');
      expect(to24Hour('9:00'), '09:00');
      expect(to24Hour('11:30'), '11:30');
    });
    test('pads single-digit hours with a leading zero', () {
      expect(to24Hour('7:00'), '07:00');
    });
  });

  group('extractTimeRanges', () {
    test('extracts a single plain range', () {
      final ranges = extractTimeRanges('7:00-9:00');
      expect(ranges, [(start: '07:00', end: '09:00')]);
    });
    test('extracts a range with spaces around the dash', () {
      final ranges = extractTimeRanges('7:00 - 9:00');
      expect(ranges, [(start: '07:00', end: '09:00')]);
    });
    test('extracts two ranges separated by a slash', () {
      final ranges = extractTimeRanges('12:00 - 2:00 / 5:00 - 6:00');
      expect(ranges, [
        (start: '12:00', end: '14:00'),
        (start: '17:00', end: '18:00'),
      ]);
    });
    test('extracts two ranges even without spaces around the slash', () {
      final ranges = extractTimeRanges('11:00-12:00/1:00-2:00');
      expect(ranges, [
        (start: '11:00', end: '12:00'),
        (start: '13:00', end: '14:00'),
      ]);
    });
    test('returns an empty list for a cell with no recognizable range', () {
      // Real data has typos like this ("10:00:11:30" instead of
      // "10:00-11:30") — must not throw, must not silently invent a
      // guess. The unit-hours conflict check (Task 6) catches the
      // resulting missing meeting instead.
      expect(extractTimeRanges('10:00:11:30'), isEmpty);
    });
    test('returns an empty list for a blank cell', () {
      expect(extractTimeRanges(''), isEmpty);
      expect(extractTimeRanges('   '), isEmpty);
    });
  });
}
