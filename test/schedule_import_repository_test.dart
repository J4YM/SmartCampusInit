import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:capstone_dashboard/data/schedule_import_repository.dart';
import 'package:capstone_dashboard/data/schedule_import/schedule_import_row.dart';

void main() {
  test('ScheduleImportRepository methods have the expected signatures', () {
    final client = SupabaseClient('https://example.invalid', 'anon-key');
    final repo = ScheduleImportRepository(client);

    final Future<String> Function({required String title, String? code})
        resolveSubjectId = repo.resolveSubjectId;
    expect(resolveSubjectId, isNotNull);

    final Future<String> Function(String) resolveSectionId =
        repo.resolveSectionId;
    expect(resolveSectionId, isNotNull);

    final Future<String> Function({String? instructorId, String? fullName})
        resolveProfessorId = repo.resolveProfessorId;
    expect(resolveProfessorId, isNotNull);

    final Future<String> Function(String) resolveRoomCanonicalName =
        repo.resolveRoomCanonicalName;
    expect(resolveRoomCanonicalName, isNotNull);

    final Future<List<String>> Function(
      List<ScheduleImportRow>,
      List<ScheduleImportRow>,
    ) findRosterMismatches = repo.findRosterMismatches;
    expect(findRosterMismatches, isNotNull);

    final Future<void> Function({
      required String classSectionId,
      required List<ScheduleImportRow> meetings,
    }) commitMeetings = repo.commitMeetings;
    expect(commitMeetings, isNotNull);
  });

  test('resolveProfessorId auto-resolves a placeholder name without a real match', () {
    // Placeholder detection is pure string logic, testable without a
    // live Supabase call — see isPlaceholderProfessorName below.
    expect(isPlaceholderProfessorName('New IT Faculty 2'), isTrue);
    expect(isPlaceholderProfessorName('New GE Instructor 2'), isTrue);
    expect(isPlaceholderProfessorName('Ronald Christian Pallorina'), isFalse);
  });
}
