import 'package:flutter_test/flutter_test.dart';
import 'package:student_portal_module/models/attendance_models.dart';

void main() {
  test('AttendanceEntry allows a null subject (section-level attendance)', () {
    final entry = AttendanceEntry(
      date: DateTime(2026, 9, 10),
      subjectId: null,
      subjectName: null,
      status: AttendanceStatus.present,
    );

    expect(entry.subjectId, isNull);
    expect(entry.subjectName, isNull);
  });

  test('fromJson tolerates missing subject_id/subject_name', () {
    final entry = AttendanceEntry.fromJson({
      'session_date': '2026-09-10T00:00:00.000',
      'status': 'present',
    });

    expect(entry.subjectId, isNull);
    expect(entry.subjectName, isNull);
  });
}
