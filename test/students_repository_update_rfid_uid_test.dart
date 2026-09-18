import 'package:capstone_dashboard/data/students_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('updateRfidUid has the expected signature', () {
    final client = SupabaseClient('https://example.supabase.co', 'anon-key');
    final repo = StudentsRepository(client);

    Future<void> Function({
      required String studentId,
      required String rfidUid,
    }) updateRfidUid = repo.updateRfidUid;

    expect(updateRfidUid, isNotNull);
  });
}
