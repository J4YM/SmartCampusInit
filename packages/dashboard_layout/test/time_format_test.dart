import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatTime12h', () {
    test('uses the 12-hour clock with AM/PM, never 24-hour', () {
      expect(formatTime12h(DateTime(2026, 10, 4, 0, 0)), '12:00 AM');
      expect(formatTime12h(DateTime(2026, 10, 4, 0, 5)), '12:05 AM');
      expect(formatTime12h(DateTime(2026, 10, 4, 7, 30)), '7:30 AM');
      expect(formatTime12h(DateTime(2026, 10, 4, 11, 59)), '11:59 AM');
      expect(formatTime12h(DateTime(2026, 10, 4, 12, 0)), '12:00 PM');
      expect(formatTime12h(DateTime(2026, 10, 4, 13, 5)), '1:05 PM');
      expect(formatTime12h(DateTime(2026, 10, 4, 23, 59)), '11:59 PM');
    });

    test('every hour of the day reads 1-12 with the right period', () {
      for (var h = 0; h < 24; h++) {
        final text = formatTime12h(DateTime(2026, 1, 1, h, 0));
        final shown = int.parse(text.split(':').first);
        expect(shown, inInclusiveRange(1, 12), reason: text);
        expect(text.endsWith(h < 12 ? 'AM' : 'PM'), isTrue, reason: text);
      }
    });

    test('seconds are optional', () {
      expect(formatTime12h(DateTime(2026, 10, 4, 15, 5, 9), seconds: true),
          '3:05:09 PM');
      expect(formatTime12h(DateTime(2026, 10, 4, 15, 5, 9)), '3:05 PM');
    });
  });

  test('formatDateTime12h puts the numeric date before the 12-hour time', () {
    expect(formatDateTime12h(DateTime(2026, 10, 4, 15, 5)),
        '2026-10-04 3:05 PM');
    expect(formatDateTime12h(DateTime(2026, 1, 9, 0, 0, 3), seconds: true),
        '2026-01-09 12:00:03 AM');
  });

  group('formatClock12h (stored "HH:mm" / "HH:mm:ss" text)', () {
    test('converts 24-hour times', () {
      expect(formatClock12h('08:00'), '8:00 AM');
      expect(formatClock12h('08:00:00'), '8:00 AM');
      expect(formatClock12h('00:15'), '12:15 AM');
      expect(formatClock12h('12:00'), '12:00 PM');
      expect(formatClock12h('13:30:00'), '1:30 PM');
      expect(formatClock12h('23:45'), '11:45 PM');
      expect(formatClock12h('7:05'), '7:05 AM');
    });

    test('leaves anything it cannot read as 24-hour untouched', () {
      expect(formatClock12h(''), '');
      expect(formatClock12h('1:30 PM'), '1:30 PM');
      expect(formatClock12h('Not yet scheduled'), 'Not yet scheduled');
      expect(formatClock12h('25:00'), '25:00');
    });

    test('ranges', () {
      expect(formatClockRange12h('08:00', '09:30'), '8:00 AM - 9:30 AM');
      expect(formatClockRange12h('11:00', '13:00'), '11:00 AM - 1:00 PM');
    });
  });
}
