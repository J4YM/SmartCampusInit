import '../pages/dashboard/professor_dashboard_page.dart';

/// Demo content lifted from the Figma "PROF | Overview" frame — lets this
/// package stay independently runnable/demoable before the real
/// `class_sections` / `attendance_records` Supabase tables are wired up.
abstract final class ProfessorMockData {
  static List<ProfessorSectionModel> getSections() => const [
        ProfessorSectionModel(id: 's1', name: 'BSBA - 1A', studentCount: 30),
        ProfessorSectionModel(id: 's2', name: 'BSBA - 1B', studentCount: 28),
        ProfessorSectionModel(id: 's3', name: 'BSBA - 1C', studentCount: 29),
        ProfessorSectionModel(id: 's4', name: 'BSHM - 1A', studentCount: 32),
        ProfessorSectionModel(id: 's5', name: 'BSHM 2C', studentCount: 33),
        ProfessorSectionModel(id: 's6', name: 'BSIT - 1A', studentCount: 27),
        ProfessorSectionModel(id: 's7', name: 'BSIT - 3C', studentCount: 33),
        ProfessorSectionModel(id: 's8', name: 'BSIT - 4B', studentCount: 32),
        ProfessorSectionModel(id: 's9', name: 'BSTM - 1C', studentCount: 31),
        ProfessorSectionModel(id: 's10', name: 'BSTM - 2B', studentCount: 31),
        ProfessorSectionModel(id: 's11', name: 'BSTM - 3C', studentCount: 30),
        ProfessorSectionModel(id: 's12', name: 'BSTM - 4C', studentCount: 29),
      ];

  static AttendanceSummaryModel getAttendanceSummary() =>
      const AttendanceSummaryModel();

  static List<StudentAttendanceRecordModel> getStudentAttendance() => const [
        StudentAttendanceRecordModel(
          id: 'st1',
          studentName: 'Alden Rodriguez',
          presentCount: 100,
          totalSessions: 120,
          absentCount: 20,
        ),
        StudentAttendanceRecordModel(
          id: 'st2',
          studentName: 'Carl Vintuan',
          presentCount: 100,
          totalSessions: 120,
          absentCount: 20,
        ),
        StudentAttendanceRecordModel(
          id: 'st3',
          studentName: 'Ella Mae Peralta',
          presentCount: 100,
          totalSessions: 120,
          absentCount: 20,
        ),
        StudentAttendanceRecordModel(
          id: 'st4',
          studentName: 'Jake Bernardo',
          presentCount: 100,
          totalSessions: 120,
          absentCount: 20,
        ),
        StudentAttendanceRecordModel(
          id: 'st5',
          studentName: 'John Bryan Tiongson',
          presentCount: 100,
          totalSessions: 120,
          absentCount: 20,
        ),
        StudentAttendanceRecordModel(
          id: 'st6',
          studentName: 'Joseph Latimag',
          presentCount: 100,
          totalSessions: 120,
          absentCount: 20,
        ),
        StudentAttendanceRecordModel(
          id: 'st7',
          studentName: 'Josephine Enriquez',
          presentCount: 100,
          totalSessions: 120,
          absentCount: 20,
        ),
        StudentAttendanceRecordModel(
          id: 'st8',
          studentName: 'Juan Dela Cruz',
          presentCount: 100,
          totalSessions: 120,
          absentCount: 20,
        ),
        StudentAttendanceRecordModel(
          id: 'st9',
          studentName: 'Julie Anne Bernardino',
          presentCount: 100,
          totalSessions: 120,
          absentCount: 20,
        ),
        StudentAttendanceRecordModel(
          id: 'st10',
          studentName: 'Luis Polig',
          presentCount: 100,
          totalSessions: 120,
          absentCount: 20,
        ),
        StudentAttendanceRecordModel(
          id: 'st11',
          studentName: 'Mike Santiago',
          presentCount: 100,
          totalSessions: 120,
          absentCount: 20,
        ),
        StudentAttendanceRecordModel(
          id: 'st12',
          studentName: 'Nelson Canlas',
          presentCount: 100,
          totalSessions: 120,
          absentCount: 20,
        ),
        StudentAttendanceRecordModel(
          id: 'st13',
          studentName: 'Paul Rosales',
          presentCount: 100,
          totalSessions: 120,
          absentCount: 20,
        ),
        StudentAttendanceRecordModel(
          id: 'st14',
          studentName: 'Ryan Santos',
          presentCount: 100,
          totalSessions: 120,
          absentCount: 20,
        ),
        StudentAttendanceRecordModel(
          id: 'st15',
          studentName: 'Ryzza Mae Cruz',
          presentCount: 100,
          totalSessions: 120,
          absentCount: 20,
        ),
        StudentAttendanceRecordModel(
          id: 'st16',
          studentName: 'Sarah Macati',
          presentCount: 100,
          totalSessions: 120,
          absentCount: 20,
        ),
      ];
}
