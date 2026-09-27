import 'package:capstone_dashboard/documents/section_schedule_pdf.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildSectionScheduleCsv', () {
    test('renders a subject with a Lecture/Laboratory split as a header '
        'row plus one row per component, times in 12-hour non-military '
        'format, and days in chronological (not alphabetical) order', () {
      final csv = buildSectionScheduleCsv(
        sectionName: 'BSTM 3C',
        rows: const [
          SectionSchedulePdfRow(
            classSectionId: 'cs1',
            subjectCode: 'TOUR1016',
            subjectTitle: 'Applied Business Tools and Technologies in Tourism',
            professorName: 'Mr. Kim Lasco',
            component: 'Lecture',
            day: 'T',
            startTime: '07:00',
            endTime: '09:00',
            room: 'Comlab2',
            units: 2,
          ),
          SectionSchedulePdfRow(
            classSectionId: 'cs1',
            subjectCode: 'TOUR1016',
            subjectTitle: 'Applied Business Tools and Technologies in Tourism',
            professorName: 'Mr. Kim Lasco',
            component: 'Laboratory',
            day: 'W',
            startTime: '09:00',
            endTime: '12:00',
            room: 'Comlab2',
            units: 1,
          ),
        ],
      );

      final lines = csv.trim().split('\n');
      // Line 0: section name. Line 1: headers. Line 2: subject header row.
      // Lines 3-4: Lecture then Laboratory sub-rows. Line 5: totals.
      expect(lines[0], 'BSTM 3C');
      expect(lines[1], 'CODE,SUBJECT,UNITS,M,T,W,TH,F,S,ROOM,INSTRUCTOR');
      expect(
        lines[2],
        'TOUR1016,Applied Business Tools and Technologies in Tourism,,,,,,,,'
        'Comlab2,Mr. Kim Lasco',
      );
      // Lecture on Tuesday: "7:00-9:00", no leading zero, no AM/PM.
      expect(lines[3], ',Lecture,2,,7:00-9:00,,,,,,');
      // Laboratory(3 Hours): 09:00-12:00 is a 3-hour block.
      expect(lines[4], ',Laboratory(3 Hours),1,,,9:00-12:00,,,,,');
      expect(lines[5], ',,3,,,,,,,,');
    });

    test('joins two time ranges on the same day with a slash', () {
      final csv = buildSectionScheduleCsv(
        sectionName: 'BSTM 3C',
        rows: const [
          SectionSchedulePdfRow(
            classSectionId: 'cs2',
            subjectCode: 'CTHC1014',
            subjectTitle: 'Tourism and Hospitality Marketing',
            professorName: 'Mr. Jose Mari Marcelo',
            day: 'W',
            startTime: '10:00',
            endTime: '11:30',
            room: 'RM 202',
            units: 3,
          ),
          SectionSchedulePdfRow(
            classSectionId: 'cs2',
            subjectCode: 'CTHC1014',
            subjectTitle: 'Tourism and Hospitality Marketing',
            professorName: 'Mr. Jose Mari Marcelo',
            day: 'W',
            startTime: '14:00',
            endTime: '15:30',
            room: 'RM 202',
            units: 3,
          ),
        ],
      );

      final lines = csv.trim().split('\n');
      expect(
        lines[2],
        'CTHC1014,Tourism and Hospitality Marketing,3,,,10:00-11:30/2:00-3:30,,,,'
        'RM 202,Mr. Jose Mari Marcelo',
      );
    });

    test('a subject with no meeting committed yet still renders a row, '
        'with blank day/time/room cells', () {
      final csv = buildSectionScheduleCsv(
        sectionName: 'BSTM 3C',
        rows: const [
          SectionSchedulePdfRow(
            classSectionId: 'cs3',
            subjectCode: 'CTHC1013',
            subjectTitle: 'Professional Development and Applied Ethics',
            professorName: 'Ms. Jennilyn Crisostomo',
            units: 3,
          ),
        ],
      );

      final lines = csv.trim().split('\n');
      expect(
        lines[2],
        'CTHC1013,Professional Development and Applied Ethics,3,,,,,,,,'
        'Ms. Jennilyn Crisostomo',
      );
    });

    test('sums every rendered row\'s units into the totals row', () {
      final csv = buildSectionScheduleCsv(
        sectionName: 'BSTM 3C',
        rows: const [
          SectionSchedulePdfRow(
            classSectionId: 'cs1',
            subjectTitle: 'Subject A',
            professorName: 'Prof A',
            component: 'Lecture',
            day: 'M',
            startTime: '07:00',
            endTime: '09:00',
            units: 2,
          ),
          SectionSchedulePdfRow(
            classSectionId: 'cs1',
            subjectTitle: 'Subject A',
            professorName: 'Prof A',
            component: 'Laboratory',
            day: 'T',
            startTime: '09:00',
            endTime: '12:00',
            units: 1,
          ),
          SectionSchedulePdfRow(
            classSectionId: 'cs2',
            subjectTitle: 'Subject B',
            professorName: 'Prof B',
            day: 'F',
            startTime: '07:00',
            endTime: '10:00',
            units: 3,
          ),
        ],
      );

      final lines = csv.trim().split('\n');
      expect(lines.last, ',,6,,,,,,,,');
    });
  });

  test('buildSectionSchedulePdf renders without throwing and produces '
      'non-empty bytes', () async {
    final bytes = await buildSectionSchedulePdf(
      sectionName: 'BSTM 3C',
      rows: const [
        SectionSchedulePdfRow(
          classSectionId: 'cs1',
          subjectCode: 'TOUR1016',
          subjectTitle: 'Applied Business Tools and Technologies in Tourism',
          professorName: 'Mr. Kim Lasco',
          component: 'Lecture',
          day: 'T',
          startTime: '07:00',
          endTime: '09:00',
          room: 'Comlab2',
          units: 2,
          schoolYear: '2026-2027',
          term: '1st Semester',
        ),
        SectionSchedulePdfRow(
          classSectionId: 'cs3',
          subjectCode: 'CTHC1013',
          subjectTitle: 'Professional Development and Applied Ethics',
          professorName: 'Ms. Jennilyn Crisostomo',
          units: 3,
          schoolYear: '2026-2027',
          term: '1st Semester',
        ),
      ],
    );

    expect(bytes, isNotEmpty);
  });
}
