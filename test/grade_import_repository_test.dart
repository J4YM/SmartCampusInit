import 'package:capstone_dashboard/data/grade_import/grade_import_row.dart';
import 'package:capstone_dashboard/data/grade_import_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('GradeImportRepository.upsertGpaRecord has the expected signature', () {
    final client = SupabaseClient('https://example.invalid', 'anon-key');
    final repo = GradeImportRepository(client);

    final Future<bool> Function(
      GradeImportRow row, {
      required String schoolYear,
      required String term,
    }) upsertGpaRecord = repo.upsertGpaRecord;
    expect(upsertGpaRecord, isNotNull);
  });
}
