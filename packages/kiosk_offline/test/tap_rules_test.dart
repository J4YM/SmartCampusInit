import 'package:flutter_test/flutter_test.dart';
import 'package:kiosk_offline/src/tap_rules.dart';

DateTime t(String iso) => DateTime.parse(iso); // offsets in the string make these exact instants

void main() {
  group('schoolDayOf', () {
    test('18:29 Manila stays on the same school day', () {
      expect(schoolDayOf(t('2026-10-05T18:29:00+08:00')), '2026-10-05');
    });

    test('18:30 Manila rolls over to the next school day', () {
      expect(schoolDayOf(t('2026-10-05T18:30:00+08:00')), '2026-10-06');
    });

    test('is independent of the machine timezone (UTC-5 clock at rollover)', () {
      // Same instants as above, expressed on a UTC-5 wall clock.
      expect(schoolDayOf(t('2026-10-05T05:29:00-05:00')), '2026-10-05');
      expect(schoolDayOf(t('2026-10-05T05:30:00-05:00')), '2026-10-06');
    });

    test('early-morning Manila tap belongs to that calendar day', () {
      expect(schoolDayOf(t('2026-10-05T07:00:00+08:00')), '2026-10-05');
    });
  });

  group('TapRules.decide', () {
    const rules = TapRules();
    final base = t('2026-10-05T08:00:00+08:00');

    test('first tap of the day is in', () {
      final d = rules.decide(tappedAt: base, studentKnown: true);
      expect(d, isA<TapAccepted>().having((a) => a.direction, 'direction', 'in'));
    });

    test('unrecognised card always logs in, ignoring history', () {
      final d = rules.decide(
        tappedAt: base,
        studentKnown: false,
        lastTapToday: PriorTap(direction: 'out', tappedAt: base),
      );
      expect(d, isA<TapAccepted>().having((a) => a.direction, 'direction', 'in'));
    });

    test('double tap within 5 s echoes the previous tap', () {
      final d = rules.decide(
        tappedAt: base.add(const Duration(seconds: 3)),
        studentKnown: true,
        lastTapToday: PriorTap(direction: 'in', tappedAt: base),
      );
      expect(d, isA<TapEchoed>().having((e) => e.direction, 'direction', 'in'));
    });

    test('tap-out before the minimum wait is denied with the server message', () {
      final d = rules.decide(
        tappedAt: base.add(const Duration(minutes: 59)),
        studentKnown: true,
        lastTapToday: PriorTap(direction: 'in', tappedAt: base),
      );
      expect(
        d,
        isA<TapDenied>().having(
          (x) => x.message,
          'message',
          'Please wait at least 1 hour after tapping in before tapping out.',
        ),
      );
    });

    test('tap-out at exactly the minimum wait is accepted', () {
      final d = rules.decide(
        tappedAt: base.add(const Duration(hours: 1)),
        studentKnown: true,
        lastTapToday: PriorTap(direction: 'in', tappedAt: base),
      );
      expect(d, isA<TapAccepted>().having((a) => a.direction, 'direction', 'out'));
    });

    test('third tap of the day is denied', () {
      final d = rules.decide(
        tappedAt: base.add(const Duration(hours: 3)),
        studentKnown: true,
        lastTapToday: PriorTap(
          direction: 'out',
          tappedAt: base.add(const Duration(hours: 2)),
        ),
      );
      expect(
        d,
        isA<TapDenied>().having(
          (x) => x.message,
          'message',
          'You have already tapped in and out for today.',
        ),
      );
    });

    test('dev wait of 5 s is honoured and worded in seconds', () {
      const dev = TapRules(tapOutMinWait: Duration(seconds: 10));
      final denied = dev.decide(
        tappedAt: base.add(const Duration(seconds: 6)),
        studentKnown: true,
        lastTapToday: PriorTap(direction: 'in', tappedAt: base),
      );
      expect(
        denied,
        isA<TapDenied>().having((x) => x.message, 'message',
            'Please wait at least 10 seconds after tapping in before tapping out.'),
      );
      final ok = dev.decide(
        tappedAt: base.add(const Duration(seconds: 10)),
        studentKnown: true,
        lastTapToday: PriorTap(direction: 'in', tappedAt: base),
      );
      expect(ok, isA<TapAccepted>());
    });
  });
}
