import 'package:capstone_dashboard/documents/room_assignment_pdf.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildRoomAssignmentCsv', () {
    test('renders one row per meeting, times in 12-hour non-military '
        'format, sorted as given (sorting itself is the repository\'s '
        'job)', () {
      final csv = buildRoomAssignmentCsv(
        schoolYear: '2026-2027',
        term: '1st Semester',
        rows: const [
          RoomAssignmentPdfRow(
            subjectCode: 'TOUR1016',
            subjectTitle: 'Applied Business Tools and Technologies in Tourism',
            component: 'Lecture',
            sectionName: 'BSTM 3C',
            professorName: 'Mr. Kim Lasco',
            room: 'LR 101',
            day: 'T',
            startTime: '07:00',
            endTime: '09:00',
          ),
        ],
      );

      final lines = csv.trim().split('\n');
      expect(lines[0], 'Room Assignment Schedule - 1ST SEMESTER A.Y. 2026-2027');
      expect(lines[1], 'Room,Day,Time,Subject,Section,Instructor');
      expect(
        lines[2],
        'LR 101,Tue,7:00-9:00,TOUR1016 - Applied Business Tools and '
        'Technologies in Tourism (Lecture),BSTM 3C,Mr. Kim Lasco',
      );
    });

    test('a subject with no course code on file omits the code prefix', () {
      final csv = buildRoomAssignmentCsv(
        schoolYear: '2026-2027',
        term: '1st Semester',
        rows: const [
          RoomAssignmentPdfRow(
            subjectTitle: 'Physical Education 1',
            sectionName: 'BSIT 1A',
            professorName: 'Ms. Dela Cruz',
            room: 'GYM',
            day: 'M',
            startTime: '13:00',
            endTime: '15:00',
          ),
        ],
      );

      final lines = csv.trim().split('\n');
      expect(
        lines[2],
        'GYM,Mon,1:00-3:00,Physical Education 1,BSIT 1A,Ms. Dela Cruz',
      );
    });

    test('a value containing a comma is quoted', () {
      final csv = buildRoomAssignmentCsv(
        schoolYear: '2026-2027',
        term: '1st Semester',
        rows: const [
          RoomAssignmentPdfRow(
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
      expect(
        lines[2],
        'LR 101,Mon,7:00-9:00,"Subject, With Comma",BSIT 1A,Prof A',
      );
    });
  });

  test('buildRoomAssignmentPdf renders without throwing and produces '
      'non-empty bytes', () async {
    final bytes = await buildRoomAssignmentPdf(
      schoolYear: '2026-2027',
      term: '1st Semester',
      rows: const [
        RoomAssignmentPdfRow(
          subjectCode: 'TOUR1016',
          subjectTitle: 'Applied Business Tools and Technologies in Tourism',
          component: 'Lecture',
          sectionName: 'BSTM 3C',
          professorName: 'Mr. Kim Lasco',
          room: 'LR 101',
          day: 'T',
          startTime: '07:00',
          endTime: '09:00',
        ),
        RoomAssignmentPdfRow(
          subjectTitle: 'Physical Education 1',
          sectionName: 'BSIT 1A',
          professorName: 'Ms. Dela Cruz',
          room: 'GYM',
          day: 'M',
          startTime: '13:00',
          endTime: '15:00',
        ),
      ],
    );

    expect(bytes, isNotEmpty);
  });
}
