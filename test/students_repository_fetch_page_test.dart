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
}
