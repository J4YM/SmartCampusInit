import 'package:capstone_dashboard/data/enrollment_import/enrollment_file_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseEnrollmentFile', () {
    test('parses one row per student from the real export\'s header', () {
      final rows = [
        [
          'Student ID', 'LRN', 'ESC ID', 'Voucher Applicant No', 'Last Name',
          'Suffix', 'First Name', 'Middle Name', 'Program', 'Level',
          'Units in Progress', 'Admit Term', 'Requirement Term',
          'Campus Email Address',
        ],
        [
          '2026-0001', null, null, null, 'Dela Cruz', null, 'Juan', 'Reyes',
          'BSIT', '1', '21', null, null, 'juan.delacruz@sti.edu.ph',
        ],
        [
          '2026-0002', null, null, null, 'Santos', 'Jr.', 'Pedro', null,
          'BSIT', '2nd Year', '21', null, null, null,
        ],
      ];

      final parsed = parseEnrollmentFile(rows);

      expect(parsed, hasLength(2));
      expect(parsed[0].studentNumber, '2026-0001');
      expect(parsed[0].firstName, 'Juan');
      expect(parsed[0].lastName, 'Dela Cruz');
      expect(parsed[0].middleName, 'Reyes');
      expect(parsed[0].suffix, isNull);
      expect(parsed[0].course, 'BSIT');
      expect(parsed[0].yearLevel, 1);
      expect(parsed[0].email, 'juan.delacruz@sti.edu.ph');

      expect(parsed[1].studentNumber, '2026-0002');
      expect(parsed[1].suffix, 'Jr.');
      // "2nd Year" (matching AddStudentDialog's own dropdown wording) still
      // resolves via its leading digit.
      expect(parsed[1].yearLevel, 2);
      expect(parsed[1].email, isNull);
    });

    test('skips a blank/stray row missing Student ID, Last Name, or First Name', () {
      final rows = [
        ['Student ID', 'Last Name', 'First Name'],
        [null, null, null],
        ['2026-0003', 'Cruz', 'Ana'],
      ];

      final parsed = parseEnrollmentFile(rows);

      expect(parsed, hasLength(1));
      expect(parsed.single.studentNumber, '2026-0003');
    });

    test('returns an empty list when no "Student ID" header is found anywhere', () {
      final rows = [
        ['Some Other Report'],
        ['A', 'B', 'C'],
      ];

      expect(parseEnrollmentFile(rows), isEmpty);
    });

    test('finds the header row even below a title/banner row', () {
      final rows = [
        ['Student Information Export — A.Y. 2026-2027'],
        ['Student ID', 'Last Name', 'First Name'],
        ['2026-0004', 'Reyes', 'Liza'],
      ];

      final parsed = parseEnrollmentFile(rows);

      expect(parsed, hasLength(1));
      expect(parsed.single.studentNumber, '2026-0004');
    });

    test('prefers Parent/s name+email over Guardian/s when both are present', () {
      final rows = [
        [
          'Student ID', 'Last Name', 'First Name', 'Parent/s', 'Parent/s Email',
          'Guardian/s', 'Guardian/s Email',
        ],
        [
          '2026-0005', 'Castillo', 'Angelica',
          'Christian Castillo / Bea Manalang Castillo', 'bea.castillo@gmail.com',
          'Christian Salazar', 'christian.salazar@yahoo.com',
        ],
      ];

      final parsed = parseEnrollmentFile(rows);

      expect(parsed.single.guardianName,
          'Christian Castillo / Bea Manalang Castillo');
      expect(parsed.single.guardianEmail, 'bea.castillo@gmail.com');
    });

    test('falls back to Guardian/s name+email when Parent/s is blank', () {
      final rows = [
        [
          'Student ID', 'Last Name', 'First Name', 'Parent/s', 'Parent/s Email',
          'Guardian/s', 'Guardian/s Email',
        ],
        [
          '2026-0006', 'Mendoza', 'Kristine', null, null,
          'Nathaniel Castillo', 'nathaniel.castillo@gmail.com',
        ],
      ];

      final parsed = parseEnrollmentFile(rows);

      expect(parsed.single.guardianName, 'Nathaniel Castillo');
      expect(parsed.single.guardianEmail, 'nathaniel.castillo@gmail.com');
    });

    test('leaves guardian fields null when neither column is present', () {
      final rows = [
        ['Student ID', 'Last Name', 'First Name'],
        ['2026-0007', 'Reyes', 'Liza'],
      ];

      final parsed = parseEnrollmentFile(rows);

      expect(parsed.single.guardianName, isNull);
      expect(parsed.single.guardianEmail, isNull);
    });
  });
}
