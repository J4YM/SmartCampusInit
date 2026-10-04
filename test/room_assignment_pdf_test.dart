import 'package:capstone_dashboard/documents/room_assignment_pdf.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildRoomAssignmentCsv', () {
    test('a subject with a Lecture/Laboratory split renders a header row '
        'plus one row per component, times in 12-hour non-military '
        'format, with Section/Instructor blank on the component rows', () {
      final csv = buildRoomAssignmentCsv(
        schoolYear: '2026-2027',
        term: '1st Semester',
        rows: const [
          RoomAssignmentPdfRow(
            classSectionId: 'cs1',
            subjectTitle: 'Computer Programming 1',
            component: 'Lecture',
            sectionName: 'BSIT 1A',
            professorName: 'Mr. Jayson Villafuerte',
            room: 'LR 101',
            day: 'M',
            startTime: '07:00',
            endTime: '09:00',
          ),
        ],
      );

      final lines = csv.trim().split('\n');
      expect(lines[0], 'ROOM SCHEDULE');
      expect(lines[1], 'LR 101');
      expect(lines[2], '1ST SEMESTER A.Y. 2026-2027');
      expect(lines[3], 'SUBJECT,M,T,W,TH,F,S,INSTRUCTOR,SECTION');
      expect(
        lines[4],
        'Computer Programming 1,,,,,,,Mr. Jayson Villafuerte,BSIT 1A',
      );
      expect(lines[5], 'Lecture,7:00-9:00,,,,,,,');
    });

    test('a Laboratory component is suffixed with its block length in '
        'hours', () {
      final csv = buildRoomAssignmentCsv(
        schoolYear: '2026-2027',
        term: '1st Semester',
        rows: const [
          RoomAssignmentPdfRow(
            classSectionId: 'cs1',
            subjectTitle: 'Computer Programming 1',
            component: 'Laboratory',
            sectionName: 'BSIT 1A',
            professorName: 'Mr. Jayson Villafuerte',
            room: 'Computer Lab 1',
            day: 'W',
            startTime: '07:00',
            endTime: '10:00',
          ),
        ],
      );

      final lines = csv.trim().split('\n');
      expect(lines[5], 'Laboratory (3 hours),,,7:00-10:00,,,,,');
    });

    test('a subject with no Lecture/Laboratory split renders a single row '
        'with its own day/time, instructor, and section', () {
      final csv = buildRoomAssignmentCsv(
        schoolYear: '2026-2027',
        term: '1st Semester',
        rows: const [
          RoomAssignmentPdfRow(
            classSectionId: 'cs2',
            subjectTitle: 'P.E./PATHFIT 1',
            sectionName: 'BSBA 1A',
            professorName: 'Ms. Jiezel Kaye Balita',
            room: 'GYM',
            day: 'TH',
            startTime: '16:00',
            endTime: '18:00',
          ),
        ],
      );

      final lines = csv.trim().split('\n');
      expect(
        lines[4],
        'P.E./PATHFIT 1,,,,4:00-6:00,,,Ms. Jiezel Kaye Balita,BSBA 1A',
      );
    });

    test('rows for two different rooms produce two separate blocks, each '
        'with its own ROOM SCHEDULE header, separated by a blank line', () {
      final csv = buildRoomAssignmentCsv(
        schoolYear: '2026-2027',
        term: '1st Semester',
        rows: const [
          RoomAssignmentPdfRow(
            classSectionId: 'cs1',
            subjectTitle: 'Subject A',
            sectionName: 'BSIT 1A',
            professorName: 'Prof A',
            room: 'LR 101',
            day: 'M',
            startTime: '07:00',
            endTime: '09:00',
          ),
          RoomAssignmentPdfRow(
            classSectionId: 'cs2',
            subjectTitle: 'Subject B',
            sectionName: 'BSIT 1B',
            professorName: 'Prof B',
            room: 'GYM',
            day: 'T',
            startTime: '13:00',
            endTime: '15:00',
          ),
        ],
      );

      final blocks = csv.trim().split('\n\n');
      expect(blocks.length, 2);
      expect(blocks[0].split('\n')[1], 'LR 101');
      expect(blocks[1].split('\n')[1], 'GYM');
    });

    test('a value containing a comma is quoted', () {
      final csv = buildRoomAssignmentCsv(
        schoolYear: '2026-2027',
        term: '1st Semester',
        rows: const [
          RoomAssignmentPdfRow(
            classSectionId: 'cs1',
            subjectTitle: 'Subject, With Comma',
            sectionName: 'BSIT 1A',
            professorName: 'Prof A',
            room: 'LR 101',
            day: 'M',
            startTime: '07:00',
            endTime: '09:00',
          ),
        ],
      );

      final lines = csv.trim().split('\n');
      expect(lines[4], '"Subject, With Comma",7:00-9:00,,,,,,Prof A,BSIT 1A');
    });
  });

  group('groupRoomAssignmentsByRoom', () {
    test('groups rows by room, preserving first-seen order', () {
      final grouped = groupRoomAssignmentsByRoom(const [
        RoomAssignmentPdfRow(
          classSectionId: 'cs1',
          subjectTitle: 'Subject A',
          sectionName: 'BSIT 1A',
          professorName: 'Prof A',
          room: 'GYM',
          day: 'M',
          startTime: '07:00',
          endTime: '09:00',
        ),
        RoomAssignmentPdfRow(
          classSectionId: 'cs2',
          subjectTitle: 'Subject B',
          sectionName: 'BSIT 1B',
          professorName: 'Prof B',
          room: 'LR 101',
          day: 'T',
          startTime: '07:00',
          endTime: '09:00',
        ),
        RoomAssignmentPdfRow(
          classSectionId: 'cs3',
          subjectTitle: 'Subject C',
          sectionName: 'BSIT 1C',
          professorName: 'Prof C',
          room: 'GYM',
          day: 'W',
          startTime: '07:00',
          endTime: '09:00',
        ),
      ]);

      expect(grouped.keys.toList(), ['GYM', 'LR 101']);
      expect(grouped['GYM']!.length, 2);
      expect(grouped['LR 101']!.length, 1);
    });
  });

  test('buildRoomAssignmentPdf renders without throwing and produces '
      'non-empty bytes, one page group per room', () async {
    final bytes = await buildRoomAssignmentPdf(
      schoolYear: '2026-2027',
      term: '1st Semester',
      rows: const [
        RoomAssignmentPdfRow(
          classSectionId: 'cs1',
          subjectTitle: 'Computer Programming 1',
          component: 'Lecture',
          sectionName: 'BSIT 1A',
          professorName: 'Mr. Jayson Villafuerte',
          room: 'LR 101',
          day: 'M',
          startTime: '07:00',
          endTime: '09:00',
        ),
        RoomAssignmentPdfRow(
          classSectionId: 'cs2',
          subjectTitle: 'P.E./PATHFIT 1',
          sectionName: 'BSBA 1A',
          professorName: 'Ms. Jiezel Kaye Balita',
          room: 'GYM',
          day: 'TH',
          startTime: '16:00',
          endTime: '18:00',
        ),
      ],
    );

    expect(bytes, isNotEmpty);
  });
}
