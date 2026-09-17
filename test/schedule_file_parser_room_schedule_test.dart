import 'package:flutter_test/flutter_test.dart';
import 'package:capstone_dashboard/data/schedule_import/schedule_file_parser.dart';
import 'package:capstone_dashboard/data/schedule_import/schedule_import_row.dart';

void main() {
  group('parseRoomSchedule', () {
    test('reads the room name from the line under the ROOM SCHEDULE title', () {
      final List<List<String?>> rows = [
        ['ROOM SCHEDULE'],
        ['COMPUTER LABORATORY 2'],
        ['SUBJECT', 'M', 'T', 'W', 'TH', 'F', 'S', 'INSTRUCTOR', 'SECTION'],
        ['Introduction to Computing', null, null, null, null, null, null, null, 'BSIT 1A'],
        ['Laboratory (3 hours)', null, null, null, '7:00 - 10:00', null, null, 'Mr. Kar-El Paulino', null],
      ];
      final result = parseRoomSchedule(rows);
      expect(result, hasLength(1));
      expect(result.single.room, 'COMPUTER LABORATORY 2');
      expect(result.single.subjectTitle, 'Introduction to Computing');
      expect(result.single.component, ScheduleComponent.laboratory);
      expect(result.single.day, 'TH');
      expect(result.single.startTime, '07:00');
      expect(result.single.endTime, '10:00');
      expect(result.single.professorName, 'Mr. Kar-El Paulino');
      expect(result.single.section, 'BSIT 1A');
    });

    test('parses a subject with both lecture and laboratory rows', () {
      final List<List<String?>> rows = [
        ['ROOM SCHEDULE'],
        ['COMPUTER LABORATORY 2'],
        ['SUBJECT', 'M', 'T', 'W', 'TH', 'F', 'S', 'INSTRUCTOR', 'SECTION'],
        ['Applied Business Tools in Tourism', null, null, null, null, null, null, null, 'BSTM 3C'],
        ['Lecture', null, '7:00 - 9:00', null, null, null, null, 'Mr. Kim Lasco', null],
        ['Laboratory (3 hours)', null, '9:00 - 12:00', null, null, null, null, 'Mr. Kim Lasco', null],
      ];
      final result = parseRoomSchedule(rows);
      expect(result, hasLength(2));
      expect(result.every((r) => r.room == 'COMPUTER LABORATORY 2'), isTrue);
      expect(result.every((r) => r.section == 'BSTM 3C'), isTrue);
      expect(result.every((r) => r.professorName == 'Mr. Kim Lasco'), isTrue);
    });
  });
}
