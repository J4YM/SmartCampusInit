import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:parent_portal_module/models/attendance_models.dart';
import 'package:parent_portal_module/models/violation_models.dart';
import 'package:capstone_dashboard/data/parent_portal_repository.dart';

void main() {
  test('fetchViolations and fetchAttendance have the expected signatures', () {
    final repo = ParentPortalRepository(
      SupabaseClient('https://example.invalid', 'anon-key'),
    );

    final Future<List<StudentViolationModel>> Function(String studentId)
        fetchViolations = repo.fetchViolations;
    expect(fetchViolations, isNotNull);

    final Future<List<AttendanceEntry>> Function(
      String studentId,
      String sectionId, {
      required DateTime from,
      required DateTime to,
    }) fetchAttendance = repo.fetchAttendance;
    expect(fetchAttendance, isNotNull);
  });
}
