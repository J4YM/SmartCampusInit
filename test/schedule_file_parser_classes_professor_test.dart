import 'package:flutter_test/flutter_test.dart';
import 'package:capstone_dashboard/data/schedule_import/schedule_file_parser.dart';
import 'package:capstone_dashboard/data/schedule_import/schedule_import_row.dart';

void main() {
  group('detectScheduleFileFormat', () {
    test('detects a Classes+Professor list by its header row', () {
      final List<List<String?>> rows = [
        ['Campus', 'Class No', 'Career', 'Course ID', 'Course Code',
          'Description', 'Course Unit', 'Instructor ID'],
        ['Baliuag', '9612', 'BCT', '001681', 'GEDC1010', 'Art Appreciation',
          '3', '02000324231'],
      ];
      expect(detectScheduleFileFormat(rows),
          ScheduleFileFormat.classesAndProfessorList);
    });

    test('detects a Confirmation of Faculty Loading file', () {
      final List<List<String?>> rows = [
        ['STI COLLEGE BALIUAG'],
        ['Confirmation of Faculty Loading'],
        ['Instructor:', 'Ronald Christian Pallorina'],
      ];
      expect(detectScheduleFileFormat(rows), ScheduleFileFormat.facultyLoading);
    });

    test('detects a Room Schedule file', () {
      final List<List<String?>> rows = [
        ['ROOM SCHEDULE'],
        ['COMPUTER LABORATORY 2'],
      ];
      expect(detectScheduleFileFormat(rows), ScheduleFileFormat.roomSchedule);
    });

    test('detects a Class Schedule file', () {
      final List<List<String?>> rows = [
        ['SCHEDULE OF CLASSES - 1ST SEMESTER A.Y. 2026-2027'],
      ];
      expect(detectScheduleFileFormat(rows), ScheduleFileFormat.classSchedule);
    });

    test('returns unknown for an unrecognized file', () {
      final List<List<String?>> rows = [
        ['Just', 'Some', 'Random', 'Data'],
      ];
      expect(detectScheduleFileFormat(rows), ScheduleFileFormat.unknown);
    });
  });
}
