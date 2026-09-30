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

  group('EnrollmentImportRepository.deriveSchoolEmail', () {
    test('takes the last 6 digits of a long real Student ID', () {
      expect(
        EnrollmentImportRepository.deriveSchoolEmail(
          lastName: 'Cruz',
          studentNumber: '02000250559',
        ),
        'cruz.250559@baliuag.sti.edu.ph',
      );
    });

    test('joins a multi-word last name with dots, lowercased', () {
      expect(
        EnrollmentImportRepository.deriveSchoolEmail(
          lastName: 'Dela Cruz',
          studentNumber: '02000250559',
        ),
        'dela.cruz.250559@baliuag.sti.edu.ph',
      );
    });

    test('strips non-digit punctuation from the student number first', () {
      expect(
        EnrollmentImportRepository.deriveSchoolEmail(
          lastName: 'Santos',
          studentNumber: '2023-0250559',
        ),
        'santos.250559@baliuag.sti.edu.ph',
      );
    });

    test('returns null when fewer than 6 digits are available', () {
      expect(
        EnrollmentImportRepository.deriveSchoolEmail(
          lastName: 'Reyes',
          studentNumber: '2023-1',
        ),
        isNull,
      );
    });

    test('returns null when the last name has no letters at all', () {
      expect(
        EnrollmentImportRepository.deriveSchoolEmail(
          lastName: '   ',
          studentNumber: '02000250559',
        ),
        isNull,
      );
    });
  });
}
