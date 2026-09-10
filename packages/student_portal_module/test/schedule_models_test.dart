import 'package:flutter_test/flutter_test.dart';
import 'package:student_portal_module/models/schedule_models.dart';

void main() {
  test('StudentScheduleEntryModel formats a readable days/time summary', () {
    const entry = StudentScheduleEntryModel(
      id: 'cs_1',
      subjectTitle: 'Data Structures and Algorithms',
      professorName: 'R. Santiago',
      room: 'CL03',
      days: ['Mon', 'Wed', 'Fri'],
      startTime: '08:30',
      endTime: '10:00',
    );

    expect(entry.daysLabel, 'Mon, Wed, Fri');
    expect(entry.timeLabel, '08:30 - 10:00');
  });
}
