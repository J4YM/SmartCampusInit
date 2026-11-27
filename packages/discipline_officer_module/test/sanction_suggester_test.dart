import 'package:discipline_officer_module/discipline_officer_module.dart';
import 'package:flutter_test/flutter_test.dart';

SanctionSuggestion? _s(String? penalty, String? category, [int? n]) =>
    SanctionSuggester.suggest(
        handbookPenalty: penalty, category: category, offenseNumber: n);

void main() {
  group('type from the handbook wording', () {
    test('a warning', () {
      final s = _s('Verbal warning; parent notice on the 3rd offense.', 'Minor', 1)!;
      expect(s.type, 'warning');
      expect(s.escalated, isFalse);
      expect(s.description, contains('Verbal warning'));
    });

    test('a suspension', () {
      final s = _s('Suspension pending review by the Discipline Board.',
          'Major_D', 1)!;
      expect(s.type, 'suspension');
      expect(s.days, 5, reason: 'Major D default');
    });

    test('suspension wins over a warning in the same text', () {
      final s = _s('Warning and suspension.', 'Major_B', 1)!;
      expect(s.type, 'suspension');
    });

    test('community service from clean-up duty', () {
      final s = _s('Warning and campus clean-up duty.', 'Minor', 1)!;
      expect(s.type, 'community_service');
      expect(s.days, isNotNull);
    });

    test('probation and conferences are "other"', () {
      expect(_s('Failing mark on the activity and disciplinary probation.',
              'Major_B', 1)!
          .type, 'other');
      expect(_s('Parent conference; guidance counseling referral.',
              'Major_A', 1)!
          .type, 'other');
    });

    test('a possible expulsion is only mentioned, never auto-chosen', () {
      final s = _s('Disciplinary probation and possible expulsion review.',
          'Major_D', 1)!;
      expect(s.type, isNot('dismissal'));
      expect(s.type, isNot('non_readmission'));
    });

    test('an explicit non-readmission or dismissal is recognised', () {
      expect(_s('Non-readmission.', 'Major_D', 1)!.type, 'non_readmission');
      expect(_s('Dismissal from the school.', 'Major_D', 1)!.type, 'dismissal');
    });
  });

  group('duration', () {
    test('uses the number of days written in the handbook', () {
      final s = _s('3-day suspension and counseling.', 'Major_A', 1)!;
      expect(s.type, 'suspension');
      expect(s.days, 3);
      expect(_s('Suspension for five days.', 'Major_A', 1)!.days, 5);
    });

    test('days in a warning text are ignored', () {
      final s = _s('Warning and uniform completion within 3 days.', 'Minor', 1)!;
      expect(s.type, 'warning');
      expect(s.days, isNull);
    });

    test('falls back to a default by severity', () {
      expect(_s('Suspension.', 'Major_A', 1)!.days, 1);
      expect(_s('Suspension.', 'Major_B', 1)!.days, 3);
      expect(_s('Suspension.', 'Major_C', 1)!.days, 3);
    });
  });

  group('repeat offenses escalate', () {
    test('2nd Minor offense stays a warning but asks for a parent notice', () {
      final s = _s('Verbal warning.', 'Minor', 2)!;
      expect(s.type, 'warning');
      expect(s.escalated, isTrue);
      expect(s.description.toLowerCase(), contains('parent'));
    });

    test('3rd Minor offense becomes a 1-day suspension', () {
      final s = _s('Verbal warning.', 'Minor', 3)!;
      expect(s.type, 'suspension');
      expect(s.days, 1);
      expect(s.escalated, isTrue);
    });

    test('2nd Major offense: a warning is raised to a suspension', () {
      final s = _s('Parent conference and written warning.', 'Major_A', 2)!;
      expect(s.type, 'suspension');
      expect(s.escalated, isTrue);
    });

    test('2nd Major offense: a suspension is lengthened', () {
      final first = _s('3-day suspension.', 'Major_B', 1)!;
      final second = _s('3-day suspension.', 'Major_B', 2)!;
      final third = _s('3-day suspension.', 'Major_B', 3)!;
      expect(second.days!, greaterThan(first.days!));
      expect(third.days!, greaterThan(second.days!));
    });

    test('a 3rd Major offense mentions review but does not pick dismissal',
        () {
      final s = _s('3-day suspension.', 'Major_C', 3)!;
      expect(s.type, 'suspension');
      expect(s.reason.toLowerCase(), contains('non-readmission'));
    });

    test('days are capped', () {
      final s = _s('10-day suspension.', 'Major_D', 5)!;
      expect(s.days!, lessThanOrEqualTo(15));
    });

    test('the first offense is never escalated', () {
      expect(_s('Verbal warning.', 'Minor', 1)!.escalated, isFalse);
      expect(_s('Verbal warning.', 'Minor', null)!.escalated, isFalse);
    });
  });

  group('missing handbook text', () {
    test('falls back to a default for the severity', () {
      expect(_s(null, 'Minor', 1)!.type, 'warning');
      expect(_s('', 'Major_B', 1)!.type, 'suspension');
      expect(_s(null, 'Major_A', 1)!.type, 'warning');
    });

    test('no category and no text means no suggestion', () {
      expect(_s(null, null, 1), isNull);
      expect(_s('  ', null), isNull);
    });
  });

  test('the reason explains where the suggestion came from', () {
    final s = _s('Verbal warning.', 'Minor', 1)!;
    expect(s.reason, contains('handbook'));
    final e = _s('Verbal warning.', 'Minor', 3)!;
    expect(e.reason.toLowerCase(), contains('3rd'));
  });
}
