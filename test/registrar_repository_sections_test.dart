import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:registrar_module/registrar_module.dart';
import 'package:capstone_dashboard/data/registrar_repository.dart';

void main() {
  test('fetchSections has the expected signature', () {
    final repo = RegistrarRepository(
      SupabaseClient('https://example.invalid', 'anon-key'),
    );

    final Future<List<SectionOption>> Function() fetchSections =
        repo.fetchSections;
    expect(fetchSections, isNotNull);
  });
}
