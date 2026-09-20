import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:parent_portal_module/models/schedule_models.dart';
import 'package:capstone_dashboard/data/parent_portal_repository.dart';

void main() {
  test('fetchSchedule has the expected signature', () {
    final repo = ParentPortalRepository(
      SupabaseClient('https://example.invalid', 'anon-key'),
    );

    final Future<List<StudentScheduleEntryModel>> Function(String studentId)
        fetchSchedule = repo.fetchSchedule;
    expect(fetchSchedule, isNotNull);
  });
}
