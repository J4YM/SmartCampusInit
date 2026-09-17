import 'package:flutter_test/flutter_test.dart';
import 'package:capstone_dashboard/data/schedule_import/schedule_file_parser.dart';
import 'package:capstone_dashboard/data/schedule_import/schedule_import_row.dart';

void main() {
  group('parseFacultyLoading', () {
    // Columns: Subject, Units, M, T, W, TH, F, S, Room, Section
    test('parses a lecture+lab subject meeting on different days/rooms', () {
      final List<List<String?>> rows = [
        ['STI COLLEGE BALIUAG'],
        ['Confirmation of Faculty Loading'],
        ['Instructor:', 'Ronald Christian Pallorina'],
        <String?>[],
        ['SUBJECT', 'Units', 'M', 'T', 'W', 'TH', 'F', 'S', 'Room', 'Section'],
        ['Human Computer Interaction', null, null, null, null, null, null, null, null, 'BSIT 2A'],
        ['Lecture', '2', null, '7:00 - 9:00', null, null, null, null, 'LR 203', null],
        ['Laboratory (3 hours)', '1', null, null, null, '7:00 - 10:00', null, null, 'ComLab 1', null],
      ];
      final result = parseFacultyLoading(rows);
      expect(result, hasLength(2));

      final lecture = result.firstWhere((r) => r.component == ScheduleComponent.lecture);
      expect(lecture.subjectTitle, 'Human Computer Interaction');
      expect(lecture.professorName, 'Ronald Christian Pallorina');
      expect(lecture.units, 2);
      expect(lecture.day, 'T');
      expect(lecture.startTime, '07:00');
      expect(lecture.endTime, '09:00');
      expect(lecture.room, 'LR 203');
      expect(lecture.section, 'BSIT 2A');

      final lab = result.firstWhere((r) => r.component == ScheduleComponent.laboratory);
      expect(lab.day, 'TH');
      expect(lab.startTime, '07:00');
      expect(lab.endTime, '10:00');
      expect(lab.room, 'ComLab 1');
      expect(lab.section, 'BSIT 2A');
      expect(lab.units, 1);
    });

    test('expands a cell with two time ranges into two rows for the same component', () {
      final List<List<String?>> rows = [
        ['Confirmation of Faculty Loading'],
        ['Instructor:', 'Jayson Villafuerte'],
        ['SUBJECT', 'Units', 'M', 'T', 'W', 'TH', 'F', 'S', 'Room', 'Section'],
        ['Application Development and Emerging Technologies', null, null, null, null, null, null, null, null, 'BSIT 3A'],
        ['Lecture', '2', '11:00 - 12:00 / 1:00 - 2:00', null, null, null, null, null, 'LR 202', null],
        ['Laboratory (3 hours)', '1', null, null, null, null, null, null, 'ComLab 3', null],
      ];
      final result = parseFacultyLoading(rows);
      final lectures = result.where((r) => r.component == ScheduleComponent.lecture).toList();
      expect(lectures, hasLength(2));
      expect(lectures[0].day, 'M');
      expect(lectures[0].startTime, '11:00');
      expect(lectures[0].endTime, '12:00');
      expect(lectures[1].day, 'M');
      expect(lectures[1].startTime, '13:00');
      expect(lectures[1].endTime, '14:00');
    });

    test('a component cell with no time range produces no row for that component', () {
      final List<List<String?>> rows = [
        ['Confirmation of Faculty Loading'],
        ['Instructor:', 'Jayson Villafuerte'],
        ['SUBJECT', 'Units', 'M', 'T', 'W', 'TH', 'F', 'S', 'Room', 'Section'],
        ['Advanced Database System', null, null, null, null, null, null, null, null, 'BSIT 3A'],
        ['Lecture', '2', null, null, null, null, null, null, null, null],
        ['Laboratory (3 hours)', '1', '2:30 - 5:30', null, null, null, null, null, 'ComLab 1', null],
      ];
      final result = parseFacultyLoading(rows);
      expect(result, hasLength(1));
      expect(result.single.component, ScheduleComponent.laboratory);
      expect(result.single.day, 'M');
    });

    test('stops at the first fully blank subject row (trailing blank rows in the sheet)', () {
      final List<List<String?>> rows = [
        ['Confirmation of Faculty Loading'],
        ['Instructor:', 'Jayson Villafuerte'],
        ['SUBJECT', 'Units', 'M', 'T', 'W', 'TH', 'F', 'S', 'Room', 'Section'],
        ['Network Technology 2', null, null, null, null, null, null, null, null, 'BSIT 4B'],
        ['Lecture', '2', '7:00 - 9:00', null, null, null, null, null, null, null],
        ['Laboratory (3 hours)', '1', null, null, null, null, null, null, null, null],
        <String?>[],
        <String?>[],
      ];
      final result = parseFacultyLoading(rows);
      expect(result, hasLength(1));
      expect(result.single.subjectTitle, 'Network Technology 2');
    });
  });
}
