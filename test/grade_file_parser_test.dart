import 'package:capstone_dashboard/data/grade_import/grade_file_parser.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds a row of the given width with [values] placed at their column
/// index and everything else null — matches the real export's fixed
/// positional layout (see grade_file_parser.dart's own doc comment) more
/// legibly than typing out 25+ nulls by hand per row.
List<String?> _row(Map<int, String> values, {int width = 25}) {
  final row = List<String?>.filled(width, null);
  values.forEach((index, value) => row[index] = value);
  return row;
}

void main() {
  group('parseGradeFile', () {
    test('parses school year/term and one row per student from the real '
        'export\'s fixed column layout', () {
      final rows = [
        _row({0: 'Candidates for Academic Honors'}),
        _row({0: 'SY & Term:', 2: '2025-2026/2nd Term'}),
        _row({0: 'Student Information'}),
        _row({
          0: 'Student ID', 1: 'First Name', 3: 'Middle Name', 4: 'Last Name',
          5: 'Suffix', 7: 'Gender', 9: 'Program', 10: 'Level',
          11: 'Transfer Units', 12: 'No of Failed Courses',
          13: 'Units Taken', 15: 'GPA', 17: 'Units Taken', 22: 'GPA',
        }),
        _row({
          0: '02000216121', 1: 'KARYLL', 3: 'LANSANGAN', 4: 'SALAS',
          7: 'F', 9: 'BSHM', 10: '4Y2', 11: '0.000', 12: '0',
          13: '140.000', 15: '1.420', 17: '6.000', 22: '1.000',
        }),
      ];

      final parsed = parseGradeFile(rows);

      expect(parsed, isNotNull);
      expect(parsed!.schoolYear, '2025-2026');
      expect(parsed.term, '2nd Term');
      expect(parsed.rows, hasLength(1));

      final row = parsed.rows.single;
      expect(row.studentNumber, '02000216121');
      expect(row.firstName, 'KARYLL');
      expect(row.lastName, 'SALAS');
      expect(row.middleName, 'LANSANGAN');
      expect(row.transferUnits, 0.0);
      expect(row.failedCoursesCount, 0);
      expect(row.cumulativeUnitsTaken, 140.0);
      expect(row.cumulativeGpa, 1.420);
      expect(row.currentTermUnitsTaken, 6.0);
      expect(row.currentTermGpa, 1.000);
    });

    test('returns null when the "SY & Term:" banner is missing', () {
      final rows = [
        _row({
          0: 'Student ID', 1: 'First Name', 4: 'Last Name',
        }),
        _row({0: '2026-0001', 1: 'Juan', 4: 'Dela Cruz'}),
      ];

      expect(parseGradeFile(rows), isNull);
    });

    test('returns null when no "Student ID" header is found anywhere', () {
      final rows = [
        _row({0: 'SY & Term:', 2: '2025-2026/2nd Term'}),
        _row({0: 'Some Other Report'}),
      ];

      expect(parseGradeFile(rows), isNull);
    });

    test('skips a blank/stray row missing Student ID, First Name, or Last Name', () {
      final rows = [
        _row({0: 'SY & Term:', 2: '2025-2026/2nd Term'}),
        _row({0: 'Student ID', 1: 'First Name', 4: 'Last Name'}),
        _row({}),
        _row({0: '2026-0002', 1: 'Pedro', 4: 'Santos'}),
      ];

      final parsed = parseGradeFile(rows);

      expect(parsed, isNotNull);
      expect(parsed!.rows, hasLength(1));
      expect(parsed.rows.single.studentNumber, '2026-0002');
    });

    test('does not confuse the current-term GPA/Units Taken columns with '
        'the cumulative ones despite sharing the same header text', () {
      final rows = [
        _row({0: 'SY & Term:', 2: '2025-2026/2nd Term'}),
        _row({
          0: 'Student ID', 1: 'First Name', 4: 'Last Name',
          13: 'Units Taken', 15: 'GPA', 17: 'Units Taken', 22: 'GPA',
        }),
        _row({
          0: '2026-0003', 1: 'Liza', 4: 'Reyes',
          13: '166.000', 15: '1.380', 17: '9.000', 22: '2.500',
        }),
      ];

      final parsed = parseGradeFile(rows);
      final row = parsed!.rows.single;

      expect(row.cumulativeUnitsTaken, 166.0);
      expect(row.cumulativeGpa, 1.380);
      expect(row.currentTermUnitsTaken, 9.0);
      expect(row.currentTermGpa, 2.500);
    });
  });
}
