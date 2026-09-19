// Verifies sample_data/confirmation_of_faculty_loading_sample.xlsx (built
// by scripts/generate_sample_schedule_xlsx.dart) actually parses the way
// the "how to test the schedule import cycle" instructions assume — a
// regression check that the checked-in fixture stays in sync with the
// parser it's meant to exercise.
import 'dart:io';

import 'package:capstone_dashboard/data/schedule_import/schedule_file_parser.dart';
import 'package:capstone_dashboard/data/schedule_import/schedule_import_row.dart';
import 'package:capstone_dashboard/data/schedule_import/xlsx_reader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the sample CFL fixture parses into one offering with both meetings', () {
    final bytes = File(
      'sample_data/confirmation_of_faculty_loading_sample.xlsx',
    ).readAsBytesSync();

    final rows = readFirstSheetRows(bytes);
    expect(detectScheduleFileFormat(rows), ScheduleFileFormat.facultyLoading);

    final parsed = parseFacultyLoading(rows);
    expect(parsed, hasLength(2));

    final lecture = parsed.firstWhere((r) => r.component == ScheduleComponent.lecture);
    expect(lecture.subjectTitle, 'Human Computer Interaction');
    expect(lecture.section, 'BSIT 2A');
    expect(lecture.professorName, 'Faculty Member');
    expect(lecture.day, 'T');
    expect(lecture.startTime, '07:00');
    expect(lecture.endTime, '09:00');
    expect(lecture.room, 'LR 203');

    final lab = parsed.firstWhere((r) => r.component == ScheduleComponent.laboratory);
    expect(lab.day, 'TH');
    expect(lab.startTime, '07:00');
    expect(lab.endTime, '10:00');
    expect(lab.room, 'ComLab 1');
  });
}
