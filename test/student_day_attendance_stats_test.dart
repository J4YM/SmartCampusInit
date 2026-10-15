import 'package:flutter_test/flutter_test.dart';
import 'package:student_portal_module/models/attendance_models.dart';

AttendanceEntry e(int day, AttendanceStatus s, [String? subject]) =>
    AttendanceEntry(date: DateTime(2030, 1, day), subjectName: subject, status: s);

void main() {
  test('three absent classes on one day is one absent day', () {
    final r = dayAttendanceStats([
      e(7, AttendanceStatus.absent, 'A'),
      e(7, AttendanceStatus.absent, 'B'),
      e(7, AttendanceStatus.absent, 'C'),
    ]);
    expect((r.absent, r.present, r.late, r.rate), (1, 0, 0, 0.0));
  });

  test('mixed day uses aggregateStatus; rate counts days', () {
    final r = dayAttendanceStats([
      e(7, AttendanceStatus.present),
      e(7, AttendanceStatus.absent),
      e(8, AttendanceStatus.present),
      e(8, AttendanceStatus.present),
      e(9, AttendanceStatus.late),
      e(9, AttendanceStatus.present),
    ]);
    expect((r.absent, r.present, r.late), (1, 1, 1));
    expect(r.rate, closeTo(1 / 3, 1e-9));
  });

  test('empty input', () {
    final r = dayAttendanceStats(const []);
    expect((r.absent, r.present, r.late, r.rate), (0, 0, 0, 0.0));
  });
}
