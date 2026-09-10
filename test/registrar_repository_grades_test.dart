import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:registrar_module/registrar_module.dart';
import 'package:capstone_dashboard/data/registrar_repository.dart';

void main() {
  test('fetchGradeRecords and saveGrade have the expected signatures', () {
    final repo = RegistrarRepository(
      SupabaseClient('https://example.invalid', 'anon-key'),
    );

    final Future<List<GradeRecordModel>> Function() fetchGradeRecords =
        repo.fetchGradeRecords;
    expect(fetchGradeRecords, isNotNull);

    final Future<void> Function({
      required String studentId,
      required String classSectionId,
      required double grade,
    }) saveGrade = repo.saveGrade;
    expect(saveGrade, isNotNull);
  });
}
