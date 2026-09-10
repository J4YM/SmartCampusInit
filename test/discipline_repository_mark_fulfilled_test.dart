import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:capstone_dashboard/data/discipline_repository.dart';

void main() {
  test('markGoodMoralRequestFulfilled has the expected signature', () {
    final repo = DisciplineRepository(
      SupabaseClient('https://example.invalid', 'anon-key'),
    );

    final Future<void> Function(String requestId) markFulfilled =
        repo.markGoodMoralRequestFulfilled;
    expect(markFulfilled, isNotNull);
  });
}
