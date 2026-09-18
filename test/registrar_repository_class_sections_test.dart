import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:capstone_dashboard/data/registrar_repository.dart';

void main() {
  test('fetchSubjects, fetchTeachers, createClassSection have expected signatures', () {
    final repo = RegistrarRepository(
      SupabaseClient('https://example.invalid', 'anon-key'),
    );

    final Future<List<SubjectOption>> Function() fetchSubjects =
        repo.fetchSubjects;
    expect(fetchSubjects, isNotNull);

    final Future<List<TeacherOption>> Function() fetchTeachers =
        repo.fetchTeachers;
    expect(fetchTeachers, isNotNull);

    final Future<String> Function({
      required String subjectId,
      required String sectionId,
      required String professorId,
      required String room,
      required List<String> days,
      required String startTime,
      required String endTime,
      required String schoolYear,
      required String term,
    }) createClassSection = repo.createClassSection;
    expect(createClassSection, isNotNull);
  });

  test('findOrCreateClassSection has the expected signature', () {
    final repo = RegistrarRepository(
      SupabaseClient('https://example.invalid', 'anon-key'),
    );

    final Future<String> Function({
      required String subjectId,
      required String sectionId,
      required String professorId,
      required String schoolYear,
      required String term,
    }) findOrCreateClassSection = repo.findOrCreateClassSection;
    expect(findOrCreateClassSection, isNotNull);
  });
}
