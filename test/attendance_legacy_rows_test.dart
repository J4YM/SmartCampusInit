import 'package:capstone_dashboard/data/professor_repository.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> row(String student, String date, String? cls, String status) => {
      'student_id': student,
      'session_date': date,
      'class_section_id': cls,
      'status': status,
    };

void main() {
  group('preferClassSpecificRows', () {
    test('class-specific row wins over legacy null row', () {
      final out = preferClassSpecificRows([
        row('s1', '2030-01-07', null, 'Absent'),
        row('s1', '2030-01-07', 'c1', 'Present'),
      ]);
      expect(out, hasLength(1));
      expect(out.single['class_section_id'], 'c1');
      expect(out.single['status'], 'Present');
    });

    test('class-specific wins regardless of input order', () {
      final out = preferClassSpecificRows([
        row('s1', '2030-01-07', 'c1', 'Present'),
        row('s1', '2030-01-07', null, 'Absent'),
      ]);
      expect(out.single['status'], 'Present');
    });

    test('legacy row used when no class-specific row exists', () {
      final out = preferClassSpecificRows([
        row('s1', '2030-01-07', null, 'Absent'),
      ]);
      expect(out, hasLength(1));
      expect(out.single['status'], 'Absent');
    });

    test('different dates and students are untouched', () {
      final out = preferClassSpecificRows([
        row('s1', '2030-01-07', null, 'Absent'),
        row('s1', '2030-01-08', 'c1', 'Present'),
        row('s2', '2030-01-07', 'c1', 'Late'),
        row('s2', '2030-01-08', null, 'Excuse'),
      ]);
      expect(out, hasLength(4));
    });

    test('empty input returns empty', () {
      expect(preferClassSpecificRows([]), isEmpty);
    });
  });
}
