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

  group('parseClassesAndProfessorList', () {
    test('parses subject, code, unit, instructor id, and professor name', () {
      final List<List<String?>> rows = [
        ['Campus', 'Class No', 'Career', 'Course ID', 'Course Code',
          'Description', 'Course Unit', 'Instructor ID', 'Last Name',
          'First Name', 'Middle Name', 'Enrolled Student'],
        ['Baliuag', '9612', 'BCT', '001681', 'GEDC1010', 'Art Appreciation',
          '3', '02000324231', 'PERALTA', 'MICHAELLA', 'P.', '37'],
        ['Baliuag', '9877', 'BCT', '002257', 'OJTC1003',
          'BSHM Practicum (600 hours)', '6', '02000429469', 'AQUINO',
          'MELISSA', 'LARA', '21'],
      ];
      final result = parseClassesAndProfessorList(rows);
      expect(result, hasLength(2));
      expect(result[0].subjectCode, 'GEDC1010');
      expect(result[0].subjectTitle, 'Art Appreciation');
      expect(result[0].units, 3);
      expect(result[0].instructorId, '02000324231');
      expect(result[0].professorName, 'PERALTA MICHAELLA P.');
      expect(result[0].component, isNull);
      expect(result[0].room, isNull);
      expect(result[0].day, isNull);
      expect(result[1].subjectCode, 'OJTC1003');
      expect(result[1].units, 6);
    });

    test('skips a row with a blank Course Code (a stray/blank source row)', () {
      final List<List<String?>> rows = [
        ['Campus', 'Class No', 'Career', 'Course ID', 'Course Code',
          'Description', 'Course Unit', 'Instructor ID', 'Last Name',
          'First Name', 'Middle Name', 'Enrolled Student'],
        ['Baliuag', null, null, null, null, null, null, null, null, null, null, null],
        ['Baliuag', '9612', 'BCT', '001681', 'GEDC1010', 'Art Appreciation',
          '3', '02000324231', 'PERALTA', 'MICHAELLA', 'P.', '37'],
      ];
      final result = parseClassesAndProfessorList(rows);
      expect(result, hasLength(1));
      expect(result[0].subjectCode, 'GEDC1010');
    });

    test('joins last/first/middle name with single spaces, tolerating a blank middle name', () {
      final List<List<String?>> rows = [
        ['Campus', 'Class No', 'Career', 'Course ID', 'Course Code',
          'Description', 'Course Unit', 'Instructor ID', 'Last Name',
          'First Name', 'Middle Name', 'Enrolled Student'],
        ['Baliuag', '9877', 'BCT', '002257', 'OJTC1003',
          'BSHM Practicum (600 hours)', '6', '02000429469', 'AQUINO',
          'MELISSA LARA', null, '21'],
      ];
      final result = parseClassesAndProfessorList(rows);
      expect(result[0].professorName, 'AQUINO MELISSA LARA');
    });
  });
}
