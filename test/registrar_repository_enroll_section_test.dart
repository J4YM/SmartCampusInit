import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:capstone_dashboard/data/registrar_repository.dart';

void main() {
  test('enrollSectionStudents has the expected signature', () {
    final repo = RegistrarRepository(
      SupabaseClient('https://example.invalid', 'anon-key'),
    );

    final Future<int> Function(String classSectionId) enrollSectionStudents =
        repo.enrollSectionStudents;
    expect(enrollSectionStudents, isNotNull);
  });
}
