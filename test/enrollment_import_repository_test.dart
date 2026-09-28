import 'package:capstone_dashboard/data/enrollment_import/enrollment_import_row.dart';
import 'package:capstone_dashboard/data/enrollment_import_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('EnrollmentImportRepository.upsertStudent has the expected signature', () {
    final client = SupabaseClient('https://example.invalid', 'anon-key');
    final repo = EnrollmentImportRepository(client);

    final Future<bool> Function(
      EnrollmentImportRow row, {
      required String sectionId,
      required String course,
      required int yearLevel,
    }) upsertStudent = repo.upsertStudent;
    expect(upsertStudent, isNotNull);

    final Future<List<SectionCandidate>> Function({
      required String course,
      required int yearLevel,
    }) fetchSectionCandidates = repo.fetchSectionCandidates;
    expect(fetchSectionCandidates, isNotNull);
  });
}
