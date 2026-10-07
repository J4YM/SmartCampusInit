import 'package:capstone_dashboard/data/curriculum_import/curriculum_file_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseCsvText', () {
    test('handles quoted commas, doubled quotes, CRLF and BOM', () {
      final rows = parseCsvText(
        '﻿a,b,c\r\n"x, y","say ""hi""",z\r\n',
      );
      expect(rows, [
        ['a', 'b', 'c'],
        ['x, y', 'say "hi"', 'z'],
      ]);
    });
  });

  group('parseCurriculumRows', () {
    test('parses a sheet with aliased headers in any order', () {
      final parsed = parseCurriculumRows(parseCsvText(
        'Course Code,Subject,Units,Program,Year Level,Semester,Prerequisite(s)\n'
        'cite 1006,Computer Programming 2,3,BS Information Technology,1,2,CITE1003\n'
        'INTE1044,"Object-Oriented Programming, Intro",3,BS Information Technology,Electives,Elective,\n',
      ))!;
      expect(parsed.errors, isEmpty);
      expect(parsed.rows, hasLength(2));
      final first = parsed.rows.first;
      expect(first.code, 'CITE1006');
      expect(first.yearLevel, 1);
      expect(first.term, 2);
      expect(first.prerequisites, 'CITE1003');
      final elective = parsed.rows.last;
      expect(elective.title, 'Object-Oriented Programming, Intro');
      expect(elective.yearLevel, 0);
      expect(elective.term, 0);
      expect(elective.prerequisites, isNull);
    });

    test('skips a bad row and reports it instead of aborting', () {
      final parsed = parseCurriculumRows(parseCsvText(
        'program,year,term,code,title,units\n'
        'BSIT,1,1,CITE1004,Introduction to Computing,3\n'
        'BSIT,1,1,,No Code,3\n',
      ))!;
      expect(parsed.rows, hasLength(1));
      expect(parsed.errors.single, contains('Row 3'));
      expect(parsed.errors.single, contains('code'));
    });

    test('returns null when the required columns are not present', () {
      expect(parseCurriculumRows(parseCsvText('foo,bar\n1,2\n')), isNull);
    });
  });
}
