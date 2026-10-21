import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:capstone_dashboard/data/students_repository.dart';
import 'package:capstone_dashboard/models/student_record.dart';

void main() {
  test('fetchPage compiles with the new section/search filter parameters', () {
    final repo = StudentsRepository(SupabaseClient('https://example.invalid', 'anon-key'));

    // A tear-off with this exact signature only compiles if fetchPage still
    // accepts every one of these named parameters — a guard against a
    // future accidental signature break, without ever calling the method
    // (which would fire a real network request against a fake URL).
    final Future<({List<StudentRecord> items, int totalCount})> Function({
      required int page,
      int pageSize,
      String? course,
      int? yearLevel,
      String? sectionId,
      String? studentNumberQuery,
    }) fetchPage = repo.fetchPage;

    expect(fetchPage, isNotNull);
  });

  group('student search (number or name)', () {
    test('splits the text into words and strips filter-breaking characters', () {
      expect(StudentsRepository.studentSearchWords('  carl   ventura '),
          ['carl', 'ventura']);
      expect(StudentsRepository.studentSearchWords('a,b (c)'), ['ab', 'c']);
      expect(StudentsRepository.studentSearchWords(' , '), isEmpty);
    });

    test('a number prefix is always searched', () {
      expect(StudentsRepository.studentSearchFilter('0200', const []),
          'student_number.ilike.0200%');
    });

    test('students whose profile name matched are included by id', () {
      expect(
        StudentsRepository.studentSearchFilter('carl', ['id-1', 'id-2']),
        'student_number.ilike.carl%,id.in.(id-1,id-2)',
      );
    });

    test('commas and parentheses cannot break out of the filter', () {
      expect(StudentsRepository.studentSearchFilter('x),id.eq.1', const []),
          'student_number.ilike.xid.eq.1%');
    });
  });
}
