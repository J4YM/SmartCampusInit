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

  test('AttendanceStatusX.fromDbValue is case-insensitive for capitalized enum values', () {
    // Real Postgres enum stores capitalized values
    expect(AttendanceStatusX.fromDbValue('Absent'), AttendanceStatus.absent);
    expect(AttendanceStatusX.fromDbValue('Late'), AttendanceStatus.late);
    expect(AttendanceStatusX.fromDbValue('Excused'), AttendanceStatus.excused);
    expect(AttendanceStatusX.fromDbValue('Present'), AttendanceStatus.present);

    // Also works with lowercase (existing test data)
    expect(AttendanceStatusX.fromDbValue('absent'), AttendanceStatus.absent);
    expect(AttendanceStatusX.fromDbValue('late'), AttendanceStatus.late);
    expect(AttendanceStatusX.fromDbValue('excused'), AttendanceStatus.excused);
    expect(AttendanceStatusX.fromDbValue('present'), AttendanceStatus.present);
  });
}
