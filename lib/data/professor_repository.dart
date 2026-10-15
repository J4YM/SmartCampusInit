import 'package:professor_module/pages/dashboard/conduct_report_view.dart';
import 'package:professor_module/pages/dashboard/violation_reports_view.dart';
import 'package:professor_module/professor_module.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

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

  /// The Subjects & Sections list: one entry per (subject, section) this
  /// professor teaches, from `class_sections` (subject + section +
  /// professor) — so the sidebar can group sections under their subject
  /// (e.g. Network Technology 2 -> BSIT 4A, BSIT 4B). The same section can
  /// appear under several subjects; its student count is the section's
  /// whole roster either way, and attendance stays per section.
  Future<List<ProfessorSectionModel>> fetchAssignedSections(
    String professorId,
  ) async {
    final rows = await _client
        .from('class_sections')
        .select('id, subjects ( id, title ), sections ( id, name )')
        .eq('professor_id', professorId);

    final pairs = <String, ({String subjectId, String subjectName, String id, String name, String classSectionId})>{};
    for (final raw in rows as List<dynamic>) {
      final row = raw as Map<String, dynamic>;
      final subject = row['subjects'] as Map<String, dynamic>?;
      final section = row['sections'] as Map<String, dynamic>?;
      if (subject == null || section == null) continue;
      final subjectId = subject['id'] as String;
      final sectionId = section['id'] as String;
      final classSectionId = row['id'] as String;
      pairs[classSectionId] = (
        subjectId: subjectId,
        subjectName: (subject['title'] as String? ?? '').trim(),
        id: sectionId,
        name: section['name'] as String,
        classSectionId: classSectionId,
      );
    }
    if (pairs.isEmpty) return const [];

    final sectionIds = {for (final p in pairs.values) p.id}.toList();
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

    final sections = [
      for (final p in pairs.values)
        ProfessorSectionModel(
          id: p.id,
          name: p.name,
          studentCount: counts[p.id] ?? 0,
          subjectId: p.subjectId,
          subjectName: p.subjectName,
          classSectionId: p.classSectionId,
        ),
    ];
    sections.sort((a, b) {
      final bySubject = (a.subjectName ?? '').compareTo(b.subjectName ?? '');
      return bySubject != 0 ? bySubject : a.name.compareTo(b.name);
    });
    return sections;
  }

  /// This professor's real teaching schedule — `class_sections` (created
  /// manually via the Registrar's Class Schedule tab, or by the schedule
  /// import flow) joined to `class_section_meetings` for the per-meeting
  /// day/time/room detail. Deliberately two queries merged client-side
  /// rather than one embedded-filter query (`class_section_meetings`
  /// has no `professor_id` column of its own to filter on directly) —
  /// matches this repo's established pattern for exactly this shape, see
  /// fetchGradeRecords's own doc comment for the same reasoning.
  Future<List<ProfessorScheduleEntryModel>> fetchMySchedule(
    String professorId,
  ) async {
    final classSections = await _client
        .from('class_sections')
        .select('id, subjects ( title ), sections ( name )')
        .eq('professor_id', professorId);

    final sectionsList = classSections as List<dynamic>;
    if (sectionsList.isEmpty) return const [];

    final classSectionIds = sectionsList
        .map((e) => (e as Map<String, dynamic>)['id'] as String)
        .toList();
    final infoById = <String, ({String subjectTitle, String sectionName})>{
      for (final raw in sectionsList)
        (raw as Map<String, dynamic>)['id'] as String: (
          subjectTitle:
              (raw['subjects'] as Map<String, dynamic>?)?['title'] as String? ??
                  '',
          sectionName:
              (raw['sections'] as Map<String, dynamic>?)?['name'] as String? ??
                  '',
        ),
    };

    final meetings = await _client
        .from('class_section_meetings')
        .select('id, class_section_id, component, day, start_time, end_time, room')
        .inFilter('class_section_id', classSectionIds)
        .order('day')
        .order('start_time');

    return (meetings as List<dynamic>).map((raw) {
      final row = raw as Map<String, dynamic>;
      final info = infoById[row['class_section_id'] as String];
      return ProfessorScheduleEntryModel(
        id: row['id'] as String,
        subjectTitle: info?.subjectTitle ?? '',
        sectionName: info?.sectionName ?? '',
        component: row['component'] as String?,
        day: row['day'] as String,
        startTime: (row['start_time'] as String).substring(0, 5),
        endTime: (row['end_time'] as String).substring(0, 5),
        room: row['room'] as String,
      );
    }).toList();
  }

  // ---------------------------------------------------------------------
  // Attendance
  // ---------------------------------------------------------------------

  Future<AttendanceSummaryModel> fetchAttendanceSummary(
    String sectionId, {
    DateTime? date,
    String? classSectionId,
  }) async {
    var query = _client
        .from('attendance_records')
        .select('status')
        .eq('section_id', sectionId)
        .eq('session_date', _dateOnly(date ?? DateTime.now()));
    if (classSectionId != null) {
      query = query.eq('class_section_id', classSectionId);
    }
    final rows = await query;

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
    String sectionId, {
    String? classSectionId,
  }) async {
    final students = await _client
        .from('students')
        .select('id, student_number, $_studentNameEmbed')
        .eq('section_id', sectionId)
        .order('student_number');

    var recordsQuery = _client
        .from('attendance_records')
        .select('student_id, status, session_date')
        .eq('section_id', sectionId);
    if (classSectionId != null) {
      recordsQuery = recordsQuery.eq('class_section_id', classSectionId);
    }
    final records = await recordsQuery;

    final tapInByStudent =
        await _fetchTodaysKioskTapIns([
      for (final raw in students as List<dynamic>)
        (raw as Map<String, dynamic>)['id'] as String,
    ]);

    final presentCounts = <String, int>{};
    final absentCounts = <String, int>{};
    final totalCounts = <String, int>{};
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
        kioskTapInAt: tapInByStudent[id],
      );
    }).toList();
  }

  /// Each student's FIRST kiosk tap-in today (local calendar day), keyed by
  /// `students.id`, from the floor readers' `rfid_tap_events` log. Empty on
  /// any failure (table not migrated, offline): attendance must still load,
  /// the tap indicator just reads "no tap yet".
  Future<Map<String, DateTime>> _fetchTodaysKioskTapIns(
    List<String> studentIds,
  ) async {
    if (studentIds.isEmpty) return const {};
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    try {
      final rows = await _client
          .from('rfid_tap_events')
          .select('student_id, tapped_at')
          .inFilter('student_id', studentIds)
          .eq('tap_direction', 'in')
          .gte('tapped_at', startOfDay.toUtc().toIso8601String())
          .order('tapped_at', ascending: true);
      final firstTap = <String, DateTime>{};
      for (final raw in rows as List<dynamic>) {
        final row = raw as Map<String, dynamic>;
        final id = row['student_id'] as String?;
        final at = DateTime.tryParse(row['tapped_at'] as String? ?? '')?.toLocal();
        if (id == null || at == null) continue;
        firstTap.putIfAbsent(id, () => at);
      }
      return firstTap;
    } catch (_) {
      return const {};
    }
  }

  /// Every recorded (student, date, status) cell across every session ever
  /// taken for [sectionId] — the weekly attendance matrix's raw data,
  /// unlike [fetchStudentAttendance] which collapses everything down to
  /// cumulative counts plus today's status only.
  Future<List<AttendanceCellModel>> fetchAttendanceCells(
    String sectionId, {
    String? classSectionId,
  }) async {
    var query = _client
        .from('attendance_records')
        .select('student_id, status, session_date')
        .eq('section_id', sectionId);
    if (classSectionId != null) {
      query = query.eq('class_section_id', classSectionId);
    }
    final records = await query;

    return (records as List<dynamic>).map((raw) {
      final row = raw as Map<String, dynamic>;
      return AttendanceCellModel(
        studentRecordId: row['student_id'] as String,
        date: dateOnly(DateTime.parse(row['session_date'] as String)),
        status: AttendanceStatus.fromValue(row['status'] as String?),
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
    String? classSectionId,
  }) async {
    final sessionDate = _dateOnly(date ?? DateTime.now());
    final rows = [
      for (final entry in statusByStudentId.entries)
        {
          'student_id': entry.key,
          'section_id': sectionId,
          if (classSectionId != null) 'class_section_id': classSectionId,
          'session_date': sessionDate,
          'status': entry.value,
          'recorded_by': recordedBy,
        },
    ];
    try {
      await _client
          .from('attendance_records')
          .upsert(rows, onConflict: 'student_id,section_id,class_section_id,session_date');
    } on PostgrestException catch (e) {
      throw ProfessorRepositoryException(e.message);
    }
  }

  // ---------------------------------------------------------------------
  // Conduct Report
  // ---------------------------------------------------------------------

  static const _reportSelectBase = '''
id, status, created_at, is_escalated, incident_notes, admission_slip_id,
reported_by,
students ( student_number, profiles ( first_name, last_name ), sections ( name ) ),
handbook_offenses ( description, category )
''';

  /// Same columns plus the professor's confirm / deny, which need
  /// add_professor_violation_confirmation.sql.
  static final _reportSelect =
      _reportSelectBase.replaceFirst(
          'reported_by,', 'reported_by, professor_decision, professor_decision_note,');

  /// Every open or resolved violation report tied to [professorId]: ones they
  /// filed (dashboard, or tapping their ID at the kiosk) and ones a student
  /// filed at the kiosk naming them as the teacher (`professor_id`). Newest
  /// first. Falls back to the filed-by-them half when the `professor_id`
  /// column hasn't been migrated yet.
  Future<List<ProfessorReportModel>> fetchMyReports(String professorId) async {
    Future<List<dynamic>> query(String select, {required bool named}) async {
      final base = _client.from('student_violations').select(select);
      final filtered = named
          ? base.or('reported_by.eq.$professorId,professor_id.eq.$professorId')
          : base.eq('reported_by', professorId);
      return await filtered
          .filter('archived_at', 'is', null)
          .order('created_at', ascending: false);
    }

    // Newest schema first; each fallback drops what an older database lacks.
    List<dynamic> rows;
    try {
      rows = await query(_reportSelect, named: true);
    } on PostgrestException {
      try {
        rows = await query(_reportSelectBase, named: true);
      } on PostgrestException {
        rows = await query(_reportSelectBase, named: false);
      }
    }

    return rows.map((raw) {
      final row = raw as Map<String, dynamic>;
      final student = row['students'] as Map<String, dynamic>?;
      final name = _fullName(student?['profiles'] as Map<String, dynamic>?);
      final section = student?['sections'] as Map<String, dynamic>?;
      final offense = row['handbook_offenses'] as Map<String, dynamic>?;
      return ProfessorReportModel(
        id: row['id'] as String,
        studentName: name.isEmpty ? 'Unknown student' : name,
        studentNumber: student?['student_number'] as String? ?? '',
        section: section?['name'] as String? ?? '',
        violationLabel:
            offense?['description'] as String? ?? 'Unspecified offense',
        category: offense?['category'] as String? ?? 'Other',
        status: row['status'] as String? ?? 'Pending',
        createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
        filedByYou: row['reported_by'] == professorId,
        admissionSlipId: row['admission_slip_id'] as String?,
        notes: row['incident_notes'] as String?,
        isEscalated: row['is_escalated'] as bool? ?? false,
        professorDecision: row['professor_decision'] as String?,
        professorDecisionNote: row['professor_decision_note'] as String?,
      );
    }).toList();
  }

  /// Any student, by student-number prefix or part of their name — a
  /// professor may report a student outside their own sections.
  Future<List<ReportStudentOption>> searchStudents(
    String query, {
    int limit = 10,
  }) async {
    final q = query.trim().replaceAll(RegExp(r'[,()%*]'), ' ').trim();
    if (q.isEmpty) return const [];
    const select =
        'id, student_number, $_studentNameEmbed, sections ( name )';

    final byNumber = await _client
        .from('students')
        .select(select)
        .ilike('student_number', '$q%')
        .order('student_number')
        .limit(limit);

    final nameHits = await _client
        .from('profiles')
        .select('id')
        .or('first_name.ilike.%$q%,last_name.ilike.%$q%')
        .limit(25);
    final ids = [for (final p in nameHits as List<dynamic>) (p as Map)['id'] as String];
    final byName = ids.isEmpty
        ? const <dynamic>[]
        : await _client
            .from('students')
            .select(select)
            .inFilter('id', ids)
            .order('student_number')
            .limit(limit) as List<dynamic>;

    final seen = <String>{};
    final out = <ReportStudentOption>[];
    for (final raw in [...(byNumber as List<dynamic>), ...byName]) {
      final row = raw as Map<String, dynamic>;
      final id = row['id'] as String;
      if (!seen.add(id)) continue;
      final section = row['sections'] as Map<String, dynamic>?;
      final name = _fullName(row['profiles'] as Map<String, dynamic>?);
      out.add(ReportStudentOption(
        id: id,
        name: name.isEmpty ? 'Unknown student' : name,
        studentNumber: row['student_number'] as String? ?? '',
        section: section?['name'] as String? ?? '',
      ));
      if (out.length >= limit) break;
    }
    return out;
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
        label: label,
        category: category ?? 'Other',
      );
    }).toList();
  }

  /// Records the professor's confirm / deny on a report that names them
  /// (supabase/add_professor_violation_confirmation.sql).
  Future<void> decideReport(
    String violationId, {
    required String professorId,
    required bool confirm,
    String? note,
  }) async {
    try {
      await _client.rpc('professor_decide_violation', params: {
        'p_violation_id': violationId,
        'p_professor_id': professorId,
        'p_decision': confirm ? 'Confirmed' : 'Denied',
        if (note != null && note.isNotEmpty) 'p_note': note,
      });
    } on PostgrestException catch (e) {
      throw ProfessorRepositoryException(e.message);
    }
  }

  /// Files [submission] the way the kiosk's Security flow does: one
  /// admission slip holding a violation row per ticked offense, reported by
  /// and tied to the professor, so it shows up under their Violation Reports.
  Future<void> submitReport(
    ReportSubmission submission, {
    required String professorId,
  }) async {
    if (submission.offenseIds.isEmpty) {
      throw ProfessorRepositoryException('Pick at least one violation.');
    }
    try {
      await _client.rpc('submit_admission_slip', params: {
        'p_slip_id': const Uuid().v4(),
        'p_student_id': submission.studentId,
        'p_reported_by': professorId,
        'p_offense_ids': submission.offenseIds,
        'p_is_escalated': submission.escalateNow,
        if (submission.notes.isNotEmpty) 'p_incident_notes': submission.notes,
        'p_professor_id': professorId,
      });
    } on PostgrestException catch (e) {
      throw ProfessorRepositoryException(e.message);
    }
  }
}
