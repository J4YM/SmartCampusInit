import '../pages/dashboard/professor_dashboard_page.dart';

/// Demo content lifted from the Figma "PROF | Overview" frame — lets this
/// package stay independently runnable/demoable before the real
/// `class_sections` / `attendance_records` Supabase tables are wired up.
abstract final class ProfessorMockData {
  /// Illustrative subject groupings for the Section List sidebar's
  /// accordion — every section still keeps its original id/name/count, just
  /// tagged with which of 3 demo subjects it's offered under.
  static List<ProfessorSectionModel> getSections() => const [
        ProfessorSectionModel(
          id: 's1',
          name: 'BSBA - 1A',
          studentCount: 30,
          subjectId: 'subj-dsa',
          subjectName: 'Data Structures & Algorithms',
        ),
        ProfessorSectionModel(
          id: 's6',
          name: 'BSIT - 1A',
          studentCount: 27,
          subjectId: 'subj-dsa',
          subjectName: 'Data Structures & Algorithms',
        ),
        ProfessorSectionModel(
          id: 's7',
          name: 'BSIT - 3C',
          studentCount: 33,
          subjectId: 'subj-dsa',
          subjectName: 'Data Structures & Algorithms',
        ),
        ProfessorSectionModel(
          id: 's9',
          name: 'BSTM - 1C',
          studentCount: 31,
          subjectId: 'subj-dsa',
          subjectName: 'Data Structures & Algorithms',
        ),
        ProfessorSectionModel(
          id: 's2',
          name: 'BSBA - 1B',
          studentCount: 28,
          subjectId: 'subj-mad',
          subjectName: 'Mobile Application Development',
        ),
        ProfessorSectionModel(
          id: 's4',
          name: 'BSHM - 1A',
          studentCount: 32,
          subjectId: 'subj-mad',
          subjectName: 'Mobile Application Development',
        ),
        ProfessorSectionModel(
          id: 's8',
          name: 'BSIT - 4B',
          studentCount: 32,
          subjectId: 'subj-mad',
          subjectName: 'Mobile Application Development',
        ),
        ProfessorSectionModel(
          id: 's10',
          name: 'BSTM - 2B',
          studentCount: 31,
          subjectId: 'subj-mad',
          subjectName: 'Mobile Application Development',
        ),
        ProfessorSectionModel(
          id: 's3',
          name: 'BSBA - 1C',
          studentCount: 29,
          subjectId: 'subj-wst',
          subjectName: 'Web Systems & Technologies',
        ),
        ProfessorSectionModel(
          id: 's5',
          name: 'BSHM 2C',
          studentCount: 33,
          subjectId: 'subj-wst',
          subjectName: 'Web Systems & Technologies',
        ),
        ProfessorSectionModel(
          id: 's11',
          name: 'BSTM - 3C',
          studentCount: 30,
          subjectId: 'subj-wst',
          subjectName: 'Web Systems & Technologies',
        ),
        ProfessorSectionModel(
          id: 's12',
          name: 'BSTM - 4C',
          studentCount: 29,
          subjectId: 'subj-wst',
          subjectName: 'Web Systems & Technologies',
        ),
      ];

  static AttendanceSummaryModel getAttendanceSummary() =>
      const AttendanceSummaryModel();

  /// Deterministic (stable across rebuilds/hot reloads) attendance cells
  /// for the weekly matrix — every weekday in the 3-week window ending
  /// today, for every student in [students], with a light pseudo-random
  /// status spread so the matrix has a realistic present/absent/late mix
  /// without ever being truly random.
  static List<AttendanceCellModel> getAttendanceCells(
    List<StudentAttendanceRecordModel> students,
  ) {
    final today = dateOnly(DateTime.now());
    final start = today.subtract(const Duration(days: 20));

    final cells = <AttendanceCellModel>[];
    for (var date = start; !date.isAfter(today); date = date.add(const Duration(days: 1))) {
      if (date.weekday == DateTime.saturday || date.weekday == DateTime.sunday) {
        continue;
      }
      final dayIndex = date.difference(start).inDays;
      for (var i = 0; i < students.length; i++) {
        final seed = (dayIndex * 7 + i * 13) % 20;
        final AttendanceStatus status;
        if (seed == 0) {
          status = AttendanceStatus.absent;
        } else if (seed == 1 || seed == 2) {
          status = AttendanceStatus.tardy;
        } else if (seed == 3) {
          status = AttendanceStatus.excused;
        } else {
          status = AttendanceStatus.present;
        }
        cells.add(AttendanceCellModel(
          studentRecordId: students[i].id,
          date: date,
          status: status,
        ));
      }
    }
    return cells;
  }

  static List<StudentAttendanceRecordModel> getStudentAttendance() => const [
        StudentAttendanceRecordModel(
          id: 'st1',
          studentName: 'Alden Rodriguez',
          studentId: '02000123401',
          presentCount: 100,
          totalSessions: 120,
          absentCount: 20,
        ),
        StudentAttendanceRecordModel(
          id: 'st2',
          studentName: 'Carl Vintuan',
          studentId: '02000123402',
          presentCount: 100,
          totalSessions: 120,
          absentCount: 20,
        ),
        StudentAttendanceRecordModel(
          id: 'st3',
          studentName: 'Ella Mae Peralta',
          studentId: '02000123403',
          presentCount: 100,
          totalSessions: 120,
          absentCount: 20,
        ),
        StudentAttendanceRecordModel(
          id: 'st4',
          studentName: 'Jake Bernardo',
          studentId: '02000123404',
          presentCount: 100,
          totalSessions: 120,
          absentCount: 20,
        ),
        StudentAttendanceRecordModel(
          id: 'st5',
          studentName: 'John Bryan Tiongson',
          studentId: '02000123405',
          presentCount: 100,
          totalSessions: 120,
          absentCount: 20,
        ),
        StudentAttendanceRecordModel(
          id: 'st6',
          studentName: 'Joseph Latimag',
          studentId: '02000123406',
          presentCount: 100,
          totalSessions: 120,
          absentCount: 20,
        ),
        StudentAttendanceRecordModel(
          id: 'st7',
          studentName: 'Josephine Enriquez',
          studentId: '02000123407',
          presentCount: 100,
          totalSessions: 120,
          absentCount: 20,
        ),
        StudentAttendanceRecordModel(
          id: 'st8',
          studentName: 'Juan Dela Cruz',
          studentId: '02000123408',
          presentCount: 100,
          totalSessions: 120,
          absentCount: 20,
        ),
        StudentAttendanceRecordModel(
          id: 'st9',
          studentName: 'Julie Anne Bernardino',
          studentId: '02000123409',
          presentCount: 100,
          totalSessions: 120,
          absentCount: 20,
        ),
        StudentAttendanceRecordModel(
          id: 'st10',
          studentName: 'Luis Polig',
          studentId: '02000123410',
          presentCount: 100,
          totalSessions: 120,
          absentCount: 20,
        ),
        StudentAttendanceRecordModel(
          id: 'st11',
          studentName: 'Mike Santiago',
          studentId: '02000123411',
          presentCount: 100,
          totalSessions: 120,
          absentCount: 20,
        ),
        StudentAttendanceRecordModel(
          id: 'st12',
          studentName: 'Nelson Canlas',
          studentId: '02000123412',
          presentCount: 100,
          totalSessions: 120,
          absentCount: 20,
        ),
        StudentAttendanceRecordModel(
          id: 'st13',
          studentName: 'Paul Rosales',
          studentId: '02000123413',
          presentCount: 100,
          totalSessions: 120,
          absentCount: 20,
        ),
        StudentAttendanceRecordModel(
          id: 'st14',
          studentName: 'Ryan Santos',
          studentId: '02000123414',
          presentCount: 100,
          totalSessions: 120,
          absentCount: 20,
        ),
        StudentAttendanceRecordModel(
          id: 'st15',
          studentName: 'Ryzza Mae Cruz',
          studentId: '02000123415',
          presentCount: 100,
          totalSessions: 120,
          absentCount: 20,
        ),
        StudentAttendanceRecordModel(
          id: 'st16',
          studentName: 'Sarah Macati',
          studentId: '02000123416',
          presentCount: 100,
          totalSessions: 120,
          absentCount: 20,
        ),
      ];
}
