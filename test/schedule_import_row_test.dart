import 'package:flutter_test/flutter_test.dart';
import 'package:capstone_dashboard/data/schedule_import/schedule_import_row.dart';

void main() {
  test('ScheduleImportRow holds all fields with correct nullability', () {
    const row = ScheduleImportRow(
      subjectTitle: 'Human Computer Interaction',
      subjectCode: 'CITE1010',
      component: ScheduleComponent.lecture,
      section: 'BSIT 3A',
      professorName: 'Ronald Christian Pallorina',
      instructorId: '02000324231',
      room: 'ComLab 1',
      day: 'T',
      startTime: '07:00',
      endTime: '09:00',
      units: 2,
    );
    expect(row.subjectTitle, 'Human Computer Interaction');
    expect(row.component, ScheduleComponent.lecture);
    expect(row.startTime, '07:00');
  });

  test('ScheduleImportRow allows every optional field to be null', () {
    const row = ScheduleImportRow(subjectTitle: 'Great Books');
    expect(row.subjectCode, isNull);
    expect(row.component, isNull);
    expect(row.section, isNull);
    expect(row.professorName, isNull);
    expect(row.instructorId, isNull);
    expect(row.room, isNull);
    expect(row.day, isNull);
    expect(row.startTime, isNull);
    expect(row.endTime, isNull);
    expect(row.units, isNull);
  });
}
