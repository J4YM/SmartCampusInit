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

  group('canonicalPlaceholderName', () {
    test('also recognizes the "New "-less spelling as a placeholder', () {
      // Confirmed real duplicate: Room Schedule spelled it "New IT
      // Faculty 1", a different tab spelled the same open position
      // "IT Faculty 1" — both must be recognized as placeholders.
      expect(isPlaceholderProfessorName('IT Faculty 1'), isTrue);
    });

    test('collapses "New X" and plain "X" to the same canonical form', () {
      expect(
        canonicalPlaceholderName('New IT Faculty 1'),
        canonicalPlaceholderName('IT Faculty 1'),
      );
    });

    test('also recognizes and collapses a numberless spelling — confirmed the same open slot', () {
      // Confirmed real duplicate + confirmed by the school: "New IT
      // Faculty 1" and plain "New IT Faculty" (no number at all) are the
      // same not-yet-filled position, just numbered inconsistently.
      expect(isPlaceholderProfessorName('New IT Faculty'), isTrue);
      expect(
        canonicalPlaceholderName('New IT Faculty 1'),
        canonicalPlaceholderName('New IT Faculty'),
      );
    });

    test('returns null for a real (non-placeholder) name', () {
      expect(canonicalPlaceholderName('Ronald Christian Pallorina'), isNull);
    });
  });

  group('isSeniorHighSection', () {
    test('flags Senior High sections (grade 11/12) as out of scope', () {
      // Confirmed real case: a Room Schedule file mixed SHS sections in
      // with college ones, and letting "ABM 12A" through hit
      // sections_year_level_check as a raw PostgrestException.
      expect(isSeniorHighSection('ABM 12A'), isTrue);
      expect(isSeniorHighSection('STEM 11B'), isTrue);
    });

    test('does not flag a normal college section', () {
      expect(isSeniorHighSection('BSIT 3B'), isFalse);
      expect(isSeniorHighSection('BSIT-3B'), isFalse);
    });

    test('does not flag a name that does not match the program/year pattern at all', () {
      expect(isSeniorHighSection('Some Unrelated Text'), isFalse);
    });
  });

  group('coreProfessorName', () {
    test('matches the same person spelled with/without an honorific and a middle initial', () {
      // Confirmed real duplicate: these two strings created two separate
      // profiles/class_sections/meetings for what should be one offering.
      expect(
        coreProfessorName('Mr. Jayson Villafuerte'),
        coreProfessorName('Jayson V. Villafuerte'),
      );
    });

    test('strips other honorifics too', () {
      expect(coreProfessorName('Dr. Maria Santos'), 'maria santos');
      expect(coreProfessorName('Engr. Jose Cruz'), 'jose cruz');
    });

    test('does not fix reversed "Last, First" ordering — a separate, known limitation', () {
      expect(
        coreProfessorName('Villafuerte Jayson V.'),
        isNot(coreProfessorName('Jayson V. Villafuerte')),
      );
    });

    test('is stable for a name with no middle initial or honorific', () {
      expect(coreProfessorName('Jayson Villafuerte'), 'jayson villafuerte');
    });
  });
}
