import 'package:professor_module/pages/dashboard/conduct_report_view.dart';
import 'package:professor_module/professor_module.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfessorRepositoryException implements Exception {
  ProfessorRepositoryException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Backs the Professor Dashboard — sections/attendance come from the new
/// `class_assignments` / `attendance_records` tables (see
/// supabase/add_professor_module_schema.sql); Conduct Report reuses the
/// existing `student_violations` / `handbook_offenses` tables, exactly like
/// the Discipline Officer dashboard already reads from.
class ProfessorRepository {
  ProfessorRepository(this._client);

  final SupabaseClient _client;

  static const _studentNameEmbed = 'profiles ( first_name, last_name )';

  String _fullName(Map<String, dynamic>? profile) {
    final first = (profile?['first_name'] as String? ?? '').trim();
    final last = (profile?['last_name'] as String? ?? '').trim();
    return '$first $last'.trim();
  }

  String _dateOnly(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  // ---------------------------------------------------------------------
  // Sections
  // ---------------------------------------------------------------------

  Future<List<ProfessorSectionModel>> fetchAssignedSections(
    String professorId,
  ) async {
    final rows = await _client
        .from('class_assignments')
        .select('sections ( id, name )')
        .eq('professor_id', professorId);

    final sectionRows = (rows as List<dynamic>)
        .map((e) => (e as Map<String, dynamic>)['sections'])
        .whereType<Map<String, dynamic>>()
        .toList();
    if (sectionRows.isEmpty) return const [];

    final sectionIds = sectionRows.map((s) => s['id'] as String).toList();
    final studentRows = await _client
        .from('students')
        .select('section_id')
        .inFilter('section_id', sectionIds);

    final counts = <String, int>{};
    for (final raw in studentRows as List<dynamic>) {
      final id = (raw as Map<String, dynamic>)['section_id'] as String?;
      if (id == null) continue;
      counts[id] = (counts[id] ?? 0) + 1;
    }

    final sections = sectionRows
        .map((s) => ProfessorSectionModel(
              id: s['id'] as String,
              name: s['name'] as String,
              studentCount: counts[s['id'] as String] ?? 0,
            ))
        .toList();
    sections.sort((a, b) => a.name.compareTo(b.name));
    return sections;
  }

  // ---------------------------------------------------------------------
  // Attendance
  // ---------------------------------------------------------------------

  Future<AttendanceSummaryModel> fetchAttendanceSummary(
    String sectionId, {
    DateTime? date,
  }) async {
    final rows = await _client
        .from('attendance_records')
        .select('status')
        .eq('section_id', sectionId)
        .eq('session_date', _dateOnly(date ?? DateTime.now()));

    var present = 0, absent = 0, late = 0, excused = 0;
    for (final raw in rows as List<dynamic>) {
      switch ((raw as Map<String, dynamic>)['status'] as String?) {
        case 'Present':
          present++;
        case 'Absent':
          absent++;
        case 'Late':
          late++;
        case 'Excuse':
          excused++;
      }
    }
    return AttendanceSummaryModel(
      present: present,
      absent: absent,
      late: late,
      excused: excused,
    );
  }

  /// One row per student enrolled in [sectionId], with cumulative
  /// present/absent counts and total recorded sessions across every date —
  /// students with no attendance history yet still appear, at 0/0, so
  /// they're available to mark in the Take Attendance dialog.
  Future<List<StudentAttendanceRecordModel>> fetchStudentAttendance(
    String sectionId,
  ) async {
    final students = await _client
        .from('students')
        .select('id, student_number, $_studentNameEmbed')
        .eq('section_id', sectionId)
        .order('student_number');

    final records = await _client
        .from('attendance_records')
        .select('student_id, status, session_date')
        .eq('section_id', sectionId);

    final today = _dateOnly(DateTime.now());
    final presentCounts = <String, int>{};
    final absentCounts = <String, int>{};
    final totalCounts = <String, int>{};
    // Today's status per student, for the Student List table's clickable
    // Status icon — students with no record yet for today fall through to
    // AttendanceStatus.fromValue's default (AttendanceStatus.none, the gray
    // "unmarked" dash icon) rather than assuming Present.
    final todayStatus = <String, String>{};
    for (final raw in records as List<dynamic>) {
      final row = raw as Map<String, dynamic>;
      final studentId = row['student_id'] as String;
      totalCounts[studentId] = (totalCounts[studentId] ?? 0) + 1;
      switch (row['status'] as String?) {
        case 'Present':
          presentCounts[studentId] = (presentCounts[studentId] ?? 0) + 1;
        case 'Absent':
          absentCounts[studentId] = (absentCounts[studentId] ?? 0) + 1;
      }
      if ((row['session_date'] as String?) == today) {
        todayStatus[studentId] = row['status'] as String? ?? 'Present';
      }
    }

    return (students as List<dynamic>).map((raw) {
      final row = raw as Map<String, dynamic>;
      final id = row['id'] as String;
      final name = _fullName(row['profiles'] as Map<String, dynamic>?);
      return StudentAttendanceRecordModel(
        id: id,
        studentName:
            name.isEmpty ? (row['student_number'] as String? ?? 'Unknown') : name,
        studentId: row['student_number'] as String? ?? '',
        presentCount: presentCounts[id] ?? 0,
        totalSessions: totalCounts[id] ?? 0,
        absentCount: absentCounts[id] ?? 0,
        status: AttendanceStatus.fromValue(todayStatus[id]),
      );
    }).toList();
  }

  /// Upserts today's (or [date]'s) attendance for every student in
  /// [statusByStudentId] — resubmitting Take Attendance for the same
  /// session overwrites rather than duplicates (see the unique constraint
  /// on `attendance_records` in add_professor_module_schema.sql).
  Future<void> submitAttendance(
    String sectionId,
    Map<String, String> statusByStudentId, {
    required String recordedBy,
    DateTime? date,
  }) async {
    final sessionDate = _dateOnly(date ?? DateTime.now());
    final rows = [
      for (final entry in statusByStudentId.entries)
        {
          'student_id': entry.key,
          'section_id': sectionId,
          'session_date': sessionDate,
          'status': entry.value,
          'recorded_by': recordedBy,
        },
    ];
    try {
      await _client
          .from('attendance_records')
          .upsert(rows, onConflict: 'student_id,section_id,session_date');
    } on PostgrestException catch (e) {
      throw ProfessorRepositoryException(e.message);
    }
  }

  // ---------------------------------------------------------------------
  // Conduct Report
  // ---------------------------------------------------------------------

  /// Every student across all of [sectionIds] — the Conduct Report tab
  /// shows one flat roster spanning every section the professor teaches,
  /// independent of whichever section is selected on the Attendance tab.
  Future<List<ConductStudentModel>> fetchConductStudentsForSections(
    List<String> sectionIds,
  ) async {
    if (sectionIds.isEmpty) return const [];
    final students = await _client
        .from('students')
        .select('id, student_number, $_studentNameEmbed, sections ( name )')
        .inFilter('section_id', sectionIds)
        .order('student_number');

    final tally = await _violationCountsByStudent();

    return (students as List<dynamic>).map((raw) {
      final row = raw as Map<String, dynamic>;
      final id = row['id'] as String;
      final section = row['sections'] as Map<String, dynamic>?;
      final name = _fullName(row['profiles'] as Map<String, dynamic>?);
      return ConductStudentModel(
        id: id,
        name: name.isEmpty ? 'Unknown student' : name,
        section: section?['name'] as String? ?? '',
        studentNumber: row['student_number'] as String? ?? '',
        previousViolationsCount: tally[id] ?? 0,
      );
    }).toList();
  }

  Future<Map<String, int>> _violationCountsByStudent() async {
    final rows = await _client
        .from('student_violations')
        .select('student_id')
        .filter('archived_at', 'is', null);
    final tally = <String, int>{};
    for (final raw in rows as List<dynamic>) {
      final id = (raw as Map<String, dynamic>)['student_id'] as String;
      tally[id] = (tally[id] ?? 0) + 1;
    }
    return tally;
  }

  Future<List<ConductViolationOption>> fetchOffenseOptions() async {
    final rows = await _client
        .from('handbook_offenses')
        .select('id, description, category')
        .order('description');
    return (rows as List<dynamic>).map((e) {
      final row = e as Map<String, dynamic>;
      final label = row['description'] as String;
      final category = row['category'] as String?;
      return ConductViolationOption(
        id: row['id'] as String,
        label: category == null ? label : '$label ($category)',
      );
    }).toList();
  }

  Future<void> submitConductReport(
    ConductReportSubmission submission, {
    required String reportedBy,
  }) async {
    final notes = submission.comments.trim();
    try {
      await _client.from('student_violations').insert({
        'student_id': submission.studentId,
        'offense_id': submission.violationOptionId,
        'reported_by': reportedBy,
        'status': 'Pending',
        'incident_notes': notes.isEmpty ? null : notes,
      });
    } on PostgrestException catch (e) {
      throw ProfessorRepositoryException(e.message);
    }
  }
}
