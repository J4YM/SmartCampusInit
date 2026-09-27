import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:capstone_dashboard/data/section_schedule_repository.dart';

void main() {
  test('SectionScheduleRepository methods have the expected signatures', () {
    final repo = SectionScheduleRepository(
      SupabaseClient('https://example.invalid', 'anon-key'),
    );

    final Future<List<SectionScheduleOption>> Function() fetchSectionOptions =
        repo.fetchSectionOptions;
    expect(fetchSectionOptions, isNotNull);

    final Future<List<SectionScheduleEntryModel>> Function({
      required String sectionId,
    }) fetchSectionSchedule = repo.fetchSectionSchedule;
    expect(fetchSectionSchedule, isNotNull);
  });
}
