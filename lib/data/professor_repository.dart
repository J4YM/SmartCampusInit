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

/// Collapses per-class attendance rows to one per (student_id, session_date),
/// preferring the class-specific row (non-null `class_section_id`) over a
/// legacy NULL-class row for the same student and date.
List<Map<String, dynamic>> preferClassSpecificRows(
    List<Map<String, dynamic>> rows) {
  final byKey = <String, Map<String, dynamic>>{};
  for (final r in rows) {
    final key = '${r['student_id']}|${r['session_date']}';
    final existing = byKey[key];
    if (existing == null ||
        (existing['class_section_id'] == null &&
            r['class_section_id'] != null)) {
      byKey[key] = r;
    }
  }
  return byKey.values.toList();
}

/// Pure grouping used by [ProfessorRepository.fetchEarlierClassesToday].
Map<String, List<EarlierClassStatus>> groupEarlierClasses({
  required List<Map<String, dynamic>> classes,
  required List<Map<String, dynamic>> records,
  required List<String> studentIds,
}) {
  final ordered = [...classes]..sort((a, b) {
      final byTime =
          (a['start_time'] as String).compareTo(b['start_time'] as String);
      return byTime != 0
          ? byTime
          : (a['subject_title'] as String)
              .compareTo(b['subject_title'] as String);
    });
  final statusByKey = <String, String?>{
    for (final r in records)
      '${r['student_id']}|${r['class_section_id']}': r['status'] as String?,
  };
  return {
    for (final studentId in studentIds)
      studentId: [
        for (final c in ordered)
          EarlierClassStatus(
            subjectName: c['subject_title'] as String,
            professorName: c['professor_name'] as String,
            startTime: c['start_time'] as String,
            status: AttendanceStatus.fromValue(
                statusByKey['$studentId|${c['id']}']),
          ),
      ],
  };
}

/// Like [groupEarlierClasses] but keeps, per student, only the classes the
/// student attends: [classes] rows carry `section_id`; a class applies when
/// it equals the student's home section or `'studentId|classId'` is in
/// [activeEnrollmentKeys].
Map<String, List<EarlierClassStatus>> groupEarlierClassesForAttendees({
  required List<Map<String, dynamic>> classes,
  required List<Map<String, dynamic>> records,
  required Map<String, String?> studentSectionIds,
  required Set<String> activeEnrollmentKeys,
}) {
  return {
    for (final studentId in studentSectionIds.keys)
      studentId: groupEarlierClasses(
        classes: [
          for (final c in classes)
            if ((c['section_id'] != null &&
                    c['section_id'] == studentSectionIds[studentId]) ||
                activeEnrollmentKeys.contains('$studentId|${c['id']}'))
              c,
        ],
        records: records,
        studentIds: [studentId],
      )[studentId]!,
  };
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

  /// The current academic term from `academic_terms`, or null when it cannot
  /// be determined (no row, table missing, any failure) — callers then skip
  /// term filtering.
  Future<({String schoolYear, String term})?> _currentTerm() async {
    try {
      final row = await _client
          .from('academic_terms')
          .select('school_year, term')
          .eq('is_current', true)
          .limit(1)
          .maybeSingle();
      if (row == null) return null;
      final schoolYear = row['school_year'] as String?;
      final term = row['term'] as String?;
      if (schoolYear == null || term == null) return null;
      return (schoolYear: schoolYear, term: term);
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------
  // Sections
  // ---------------------------------------------------------------------

  /// The Subjects & Sections list: one entry per (subject, section) this
  /// professor teaches, from `class_sections` (subject + section +
  /// professor) — so the sidebar can group sections under their subject
  /// (e.g. Network Technology 2 -> BSIT 4A, BSIT 4B). The same section can
  /// appear under several subjects; its student count is the section's
  /// whole roster either way. Attendance is recorded per class
  /// (`class_section_id`), so each entry carries its [classSectionId].
  /// Only the current academic term's classes are listed when it is known.
  Future<List<ProfessorSectionModel>> fetchAssignedSections(
    String professorId,
  ) async {
    final term = await _currentTerm();
    var query = _client
        .from('class_sections')
        .select('id, subjects ( id, title ), sections ( id, name )')
        .eq('professor_id', professorId);
    if (term != null) {
      query = query.eq('school_year', term.schoolYear).eq('term', term.term);
    }
    final rows = await query;

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

    // A class's roster is the students with an Active enrollment in THAT
    // class whose account is active — belonging to the section is not enough
    // (an unconfirmed/inactive student, or one not enrolled yet, is not listed).
    final counts = <String, int>{};
    final enrollmentRows = await _client
        .from('enrollments')
        .select('student_id, class_section_id, students ( profiles ( is_active ) )')
        .inFilter('class_section_id', pairs.keys.toList())
        .eq('status', 'Active');
    for (final raw in enrollmentRows as List<dynamic>) {
      final row = raw as Map<String, dynamic>;
      if (!_isActiveStudentRow(row['students'] as Map<String, dynamic>?)) {
        continue;
      }
      final classId = row['class_section_id'] as String;
      counts[classId] = (counts[classId] ?? 0) + 1;
    }

    final sections = [
      for (final p in pairs.values)
        ProfessorSectionModel(
          id: p.id,
          name: p.name,
          studentCount: counts[p.classSectionId] ?? 0,
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
        .select('student_id, session_date, class_section_id, status')
        .eq('section_id', sectionId)
        .eq('session_date', _dateOnly(date ?? DateTime.now()));
    if (classSectionId != null) {
      // Include legacy NULL-class rows of this section; class-specific rows
      // win per student (see preferClassSpecificRows).
      query = query.or(
          'class_section_id.eq.$classSectionId,class_section_id.is.null');
    }
    final fetched = await query;
    final rows = classSectionId != null
        ? preferClassSpecificRows([
            for (final r in fetched as List<dynamic>)
              r as Map<String, dynamic>,
          ])
        : fetched;

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
    // The roster is ONLY students with an Active enrollment in this class
    // (or, with no class given, any class of the section) and an active
    // account. Merely sitting in the section (`students.section_id`) does
    // not put a student on a professor's list: until they are enrolled — and,
    // after a term migration, confirmed by the Registrar — they are not here.
    final enrolledIds = await _fetchEnrolledStudentIds(
      sectionId,
      classSectionId: classSectionId,
    );
    final students = <dynamic>[];
    if (enrolledIds.isNotEmpty) {
      final rosterRows = await _client
          .from('students')
          .select('id, student_number, $_studentNameEmbed')
          .inFilter('id', enrolledIds)
          .order('student_number');
      students.addAll(rosterRows as List<dynamic>);
    }

    var recordsQuery = _client
        .from('attendance_records')
        .select('student_id, status, session_date, class_section_id')
        .eq('section_id', sectionId);
    if (classSectionId != null) {
      recordsQuery = recordsQuery.or(
          'class_section_id.eq.$classSectionId,class_section_id.is.null');
    }
    final fetchedRecords = await recordsQuery;
    final records = classSectionId != null
        ? preferClassSpecificRows([
            for (final r in fetchedRecords as List<dynamic>)
              r as Map<String, dynamic>,
          ])
        : fetchedRecords;

    final todaysTaps =
        await _fetchTodaysKioskTaps([
      for (final raw in students)
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

    return students.map((raw) {
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
        kioskTapInAt: todaysTaps.tapIn[id],
        kioskTapOutAt: todaysTaps.tapOut[id],
      );
    }).toList();
  }

  /// True unless the embedded `students ( profiles ( is_active ) )` row says
  /// the account is inactive (an unconfirmed student after a term migration).
  /// A missing flag counts as active, matching the Registrar's own reading.
  bool _isActiveStudentRow(Map<String, dynamic>? student) {
    final profile = student?['profiles'] as Map<String, dynamic>?;
    return (profile?['is_active'] as bool?) ?? true;
  }

  /// Ids of students with an Active `enrollments` row in any class offering
  /// of [sectionId]. Empty on failure so the regular roster still loads.
  Future<List<String>> _fetchEnrolledStudentIds(
    String sectionId, {
    String? classSectionId,
  }) async {
    try {
      final classRows = await _client
          .from('class_sections')
          .select('id')
          .eq('section_id', sectionId);
      final classIds = [
        for (final r in classRows as List<dynamic>)
          if (classSectionId == null ||
              (r as Map<String, dynamic>)['id'] == classSectionId)
            (r as Map<String, dynamic>)['id'] as String,
      ];
      if (classIds.isEmpty) return const [];
      final rows = await _client
          .from('enrollments')
          .select('student_id, students ( profiles ( is_active ) )')
          .inFilter('class_section_id', classIds)
          .eq('status', 'Active');
      return {
        for (final r in rows as List<dynamic>)
          if (_isActiveStudentRow(
              (r as Map<String, dynamic>)['students'] as Map<String, dynamic>?))
            r['student_id'] as String,
      }.toList();
    } catch (_) {
      return const [];
    }
  }

  /// Each student's FIRST kiosk tap-in and LAST tap-out today (local calendar
  /// day), keyed by `students.id`, from the floor readers' `rfid_tap_events`
  /// log. Both maps are empty on any failure (table not migrated, offline):
  /// attendance must still load, the indicators just read "no tap yet".
  Future<({Map<String, DateTime> tapIn, Map<String, DateTime> tapOut})>
      _fetchTodaysKioskTaps(List<String> studentIds) async {
    const empty = (tapIn: <String, DateTime>{}, tapOut: <String, DateTime>{});
    if (studentIds.isEmpty) return empty;
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    try {
      final rows = await _client
          .from('rfid_tap_events')
          .select('student_id, tapped_at, tap_direction')
          .inFilter('student_id', studentIds)
          .gte('tapped_at', startOfDay.toUtc().toIso8601String())
          .order('tapped_at', ascending: true);
      final firstIn = <String, DateTime>{};
      final lastOut = <String, DateTime>{};
      for (final raw in rows as List<dynamic>) {
        final row = raw as Map<String, dynamic>;
        final id = row['student_id'] as String?;
        final at = DateTime.tryParse(row['tapped_at'] as String? ?? '')?.toLocal();
        if (id == null || at == null) continue;
        if (row['tap_direction'] == 'out') {
          lastOut[id] = at; // rows are ascending, so the last one wins
        } else {
          firstIn.putIfAbsent(id, () => at);
        }
      }
      return (tapIn: firstIn, tapOut: lastOut);
    } catch (_) {
      return empty;
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
        .select('student_id, status, session_date, class_section_id')
        .eq('section_id', sectionId);
    if (classSectionId != null) {
      query = query.or(
          'class_section_id.eq.$classSectionId,class_section_id.is.null');
    }
    final fetchedCells = await query;
    final records = classSectionId != null
        ? preferClassSpecificRows([
            for (final r in fetchedCells as List<dynamic>)
              r as Map<String, dynamic>,
          ])
        : fetchedCells;

    return (records as List<dynamic>).map((raw) {
      final row = raw as Map<String, dynamic>;
      return AttendanceCellModel(
        studentRecordId: row['student_id'] as String,
        date: dateOnly(DateTime.parse(row['session_date'] as String)),
        status: AttendanceStatus.fromValue(row['status'] as String?),
      );
    }).toList();
  }

  static const _dayCodes = ['M', 'T', 'W', 'TH', 'F', 'S'];

  /// For each student in [studentIds]: every OTHER class that meets on
  /// [date]'s weekday (earlier or later than [classSectionId]) and that the
  /// student has an Active enrollment in — with the status recorded that day
  /// (`none` when not recorded), earliest first. Empty when
  /// [classSectionId] itself has no meeting that weekday, and on any failure.
  Future<Map<String, List<EarlierClassStatus>>> fetchEarlierClassesToday({
    required List<String> studentIds,
    required DateTime date,
    required String classSectionId,
  }) async {
    if (studentIds.isEmpty || date.weekday > 6) return const {};
    try {
      final day = _dayCodes[date.weekday - 1];
      // Only for a day this class actually meets: nothing to compare against
      // on a day it has no session.
      final current = await _client
          .from('class_section_meetings')
          .select('start_time')
          .eq('class_section_id', classSectionId)
          .eq('day', day)
          .limit(1);
      if ((current as List<dynamic>).isEmpty) return const {};

      // Every OTHER class meeting that same day — earlier or later than this
      // one — so the professor sees how each student did in their other
      // subjects that day (and only that day).
      final earlier = await _client
          .from('class_section_meetings')
          .select(
              'start_time, class_section_id, class_sections ( id, section_id, school_year, term, subjects ( title ), profiles ( first_name, last_name ) )')
          .eq('day', day)
          .neq('class_section_id', classSectionId)
          .order('start_time');

      final term = await _currentTerm();
      final classes = <Map<String, dynamic>>[];
      final seen = <String>{};
      for (final raw in earlier as List<dynamic>) {
        final row = raw as Map<String, dynamic>;
        final cs = row['class_sections'] as Map<String, dynamic>?;
        if (cs == null) continue;
        if (term != null &&
            (cs['school_year'] != term.schoolYear || cs['term'] != term.term)) {
          continue;
        }
        final id = cs['id'] as String;
        if (!seen.add(id)) continue;
        classes.add({
          'id': id,
          'section_id': cs['section_id'],
          'subject_title':
              ((cs['subjects'] as Map<String, dynamic>?)?['title'] as String?) ??
                  'Class',
          'professor_name': _fullName(cs['profiles'] as Map<String, dynamic>?),
          'start_time': (row['start_time'] as String).substring(0, 5),
        });
      }
      if (classes.isEmpty) return const {};
      final classIds = [for (final c in classes) c['id'] as String];

      final studentRows = await _client
          .from('students')
          .select('id, section_id')
          .inFilter('id', studentIds);
      // Home section is deliberately NOT used: a student attends only the
      // classes they have an Active enrollment in.
      final studentSectionIds = <String, String?>{
        for (final r in studentRows as List<dynamic>)
          (r as Map<String, dynamic>)['id'] as String: null,
      };

      final enrollmentRows = await _client
          .from('enrollments')
          .select('student_id, class_section_id')
          .inFilter('student_id', studentIds)
          .inFilter('class_section_id', classIds)
          .eq('status', 'Active');
      final activeEnrollmentKeys = <String>{
        for (final r in enrollmentRows as List<dynamic>)
          '${(r as Map<String, dynamic>)['student_id']}|${r['class_section_id']}',
      };

      final records = await _client
          .from('attendance_records')
          .select('student_id, class_section_id, status')
          .inFilter('student_id', studentIds)
          .inFilter('class_section_id', classIds)
          .eq('session_date', _dateOnly(date));

      return groupEarlierClassesForAttendees(
        classes: classes,
        records: [
          for (final r in records as List<dynamic>) r as Map<String, dynamic>,
        ],
        studentSectionIds: studentSectionIds,
        activeEnrollmentKeys: activeEnrollmentKeys,
      );
    } catch (_) {
      return const {};
    }
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

  /// Deletes every attendance record taken for [sectionId] (and, when given,
  /// [classSectionId] — the same class the professor's Take Attendance writes
  /// to) on [date]. Needs the delete policy in
  /// supabase/add_attendance_delete_policy.sql.
  Future<void> deleteAttendance(
    String sectionId,
    DateTime date, {
    String? classSectionId,
  }) async {
    try {
      var query = _client
          .from('attendance_records')
          .delete()
          .eq('section_id', sectionId)
          .eq('session_date', _dateOnly(date));
      query = classSectionId != null
          ? query.eq('class_section_id', classSectionId)
          : query.filter('class_section_id', 'is', null);
      await query;
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
