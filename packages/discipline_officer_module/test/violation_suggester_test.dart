import 'package:discipline_officer_module/discipline_officer_module.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ViolationSuggester.suggestBehaviorCategory', () {
    test('detects each category from free text', () {
      const cases = {
        'Student was caught cheating during the quiz and copied answers':
            BehaviorCategory.academicIntegrity,
        'Came late to class three times, habitually tardy':
            BehaviorCategory.attendanceTardiness,
        'Not wearing the proper uniform and no ID inside campus':
            BehaviorCategory.uniformDressCode,
        'Vandalized a chair and damaged the projector in room 301':
            BehaviorCategory.propertyDamage,
        'Disrespectful to the teacher, shouting and disrupting the class':
            BehaviorCategory.disruptiveConduct,
        'Using mobile phone and playing online games during lecture':
            BehaviorCategory.digitalDevicePolicy,
      };
      for (final e in cases.entries) {
        expect(ViolationSuggester.suggestBehaviorCategory(e.key), e.value,
            reason: e.key);
      }
    });

    test('returns null when nothing matches or the text is empty', () {
      expect(ViolationSuggester.suggestBehaviorCategory(''), isNull);
      expect(ViolationSuggester.suggestBehaviorCategory('   '), isNull);
      expect(ViolationSuggester.suggestBehaviorCategory('xyz qwerty'), isNull);
    });

    test('the category with the most keyword hits wins', () {
      expect(
        ViolationSuggester.suggestBehaviorCategory(
            'late, late again, tardy, and wearing a cap'),
        BehaviorCategory.attendanceTardiness,
      );
    });
  });

  group('ViolationSuggester.suggestOffenses', () {
    const options = [
      OffenseOption(
          id: 'a', label: 'Cheating during quizzes, exams, or graded activities',
          category: 'Major_A', behaviorCategory: 'Academic_Integrity'),
      OffenseOption(
          id: 'b', label: 'No valid ID worn inside campus',
          category: 'Minor', behaviorCategory: 'Uniform_Dress_Code'),
      OffenseOption(
          id: 'c', label: 'Habitual tardiness without valid excuse',
          category: 'Minor', behaviorCategory: 'Attendance_Tardiness'),
    ];

    test('ranks the best matching offense first', () {
      final result = ViolationSuggester.suggestOffenses(
          'He was caught cheating on the midterm exam', options);
      expect(result.first.id, 'a');
    });

    test('matches word stems (tardy / tardiness)', () {
      final result = ViolationSuggester.suggestOffenses(
          'Student is always tardy', options);
      expect(result.first.id, 'c');
    });

    test('returns at most the requested count and nothing for no match', () {
      expect(ViolationSuggester.suggestOffenses('zzz', options), isEmpty);
      expect(
          ViolationSuggester.suggestOffenses('valid ID exam late', options,
                  limit: 2)
              .length,
          lessThanOrEqualTo(2));
    });
  });
}
