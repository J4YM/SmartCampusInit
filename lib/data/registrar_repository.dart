import 'package:registrar_module/registrar_module.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/student_record.dart';
import 'schedule_import_repository.dart' show isPlaceholderProfessorName;

// `SubjectOption`/`TeacherOption` are UI-facing models consumed by
// `ClassScheduleView` (packages/registrar_module), so — like every other
// model this repository returns (RegistrarStudentModel, ScheduleEntryModel,
// etc.) — they're defined over there, not here: `registrar_module` cannot
// depend back on this app package, so `class_schedule_view.dart` couldn't
// import them if they lived in this file. Re-exported here so callers that
// only import this repository (e.g. its signature-guard test) can still
// reference the type names directly.
export 'package:registrar_module/registrar_module.dart'
    show
        SubjectOption,
        TeacherOption,
        SectionOption,
        StudentEnrollmentModel,
        ClassSectionOffering;

class RegistrarRepositoryException implements Exception {
  RegistrarRepositoryException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Backs the Registrar dashboard's Overview/Student Records/RFID Management,
/// Class Schedule, and Grades tabs with real `students`/`profiles`/
/// `sections`/`subjects`/`class_sections`/`grades` data.
class RegistrarRepository {
  RegistrarRepository(this._client);

  final SupabaseClient _client;

  static const _studentSelect = '''
id,
student_number,
rfid_uid,
created_at,
enrollment_year,
guardian_name,
guardian_contact_no,
profiles ( first_name, last_name, email, phone_number, is_active ),
sections ( name, program ),
parent_student_links (
  profiles!parent_student_links_parent_id_fkey ( first_name, last_name, email )
)
''';

  Future<List<RegistrarStudentModel>> fetchStudents() async {
    final rows = await _client
        .from('students')
        .select(_studentSelect)
        .order('created_at', ascending: false);

    final currentYear = DateTime.now().year;
    final gwaByStudent = await _fetchLatestGwaByStudent();

    return (rows as List<dynamic>).map((e) {
      final row = e as Map<String, dynamic>;
      final profile = row['profiles'] as Map<String, dynamic>?;
      final section = row['sections'] as Map<String, dynamic>?;
      final parentLinks = row['parent_student_links'] as List<dynamic>?;
      final parentProfile = (parentLinks != null && parentLinks.isNotEmpty)
          ? (parentLinks.first as Map<String, dynamic>)['profiles']
              as Map<String, dynamic>?
          : null;
      final rfidUid = row['rfid_uid'] as String?;
      final createdAt = DateTime.tryParse(row['created_at'] as String? ?? '')?.toLocal();
      final enrollmentYear = row['enrollment_year'] as int?;
      final nameParts = StudentRecord.splitStoredFirstName(
        profile?['first_name'] as String? ?? '',
      );
      // A guardian entered on an edit form wins over a linked parent
      // account's name — same precedence as StudentRecord.fromSupabase.
      final storedGuardian = (row['guardian_name'] as String?)?.trim() ?? '';

      return RegistrarStudentModel(
        firstName: nameParts.$1,
        middleInitial: nameParts.$2,
        lastName: (profile?['last_name'] as String?)?.trim() ?? '',
        guardianContactNo:
            (row['guardian_contact_no'] as String?)?.trim() ?? '',
        guardianEmail: (parentProfile?['email'] as String?)?.trim() ?? '',
        id: row['id'] as String,
        name: _fullName(
          profile?['first_name'] as String?,
          profile?['last_name'] as String?,
        ),
        studentId: row['student_number'] as String? ?? '',
        program: section?['program'] as String? ?? '',
        section: section?['name'] as String? ?? '',
        // Latest GPA snapshot (batch upload or manual entry), null until one
        // exists — see [_fetchLatestGwaByStudent].
        gpa: gwaByStudent[row['id'] as String],
        status: (profile?['is_active'] as bool? ?? true)
            ? EnrollmentStatus.active
            : EnrollmentStatus.inactive,
        hasRfid: rfidUid != null && rfidUid.isNotEmpty,
        isNewStudent: enrollmentYear != null && enrollmentYear == currentYear,
        parentGuardian: storedGuardian.isNotEmpty
            ? storedGuardian
            : _fullName(
                parentProfile?['first_name'] as String?,
                parentProfile?['last_name'] as String?,
              ),
        contactNo: profile?['phone_number'] as String? ?? '',
        email: profile?['email'] as String? ?? '',
        enrolledDate: createdAt == null ? '' : _formatDate(createdAt),
      );
    }).toList();
  }

  /// Each student's most recently written GWA (1.00-5.00, 1.00 = best) from
  /// `student_gpa_records` — the table the GPA batch upload and the manual
  /// GWA entry both write. Cumulative GPA wins, else the current-term GPA.
  /// Best-effort: an unreadable/missing table leaves every GWA blank rather
  /// than failing the whole student list.
  Future<Map<String, double>> _fetchLatestGwaByStudent() async {
    final latest = <String, double>{};
    try {
      const pageSize = 1000; // PostgREST's default row cap per request
      for (var from = 0;; from += pageSize) {
        final rows = await _client
            .from('student_gpa_records')
            .select('student_id, cumulative_gpa, current_term_gpa')
            .order('updated_at', ascending: false)
            .order('id')
            .range(from, from + pageSize - 1);
        for (final e in rows as List<dynamic>) {
          final row = e as Map<String, dynamic>;
          final studentId = row['student_id'] as String;
          // Rows arrive newest first, so the first one seen per student wins.
          if (latest.containsKey(studentId)) continue;
          final gwa = (row['cumulative_gpa'] as num?) ??
              (row['current_term_gpa'] as num?);
          if (gwa != null) latest[studentId] = gwa.toDouble();
        }
        if ((rows).length < pageSize) break;
      }
    } catch (_) {
      // Fall through with whatever was read.
    }
    return latest;
  }

  /// Which (school year, term) a manually entered GWA is filed under: the
  /// term of the most recent GPA record on file (so it lines up with the
  /// batch upload's own "2025-2026 / 2nd Term" spelling and overrides that
  /// term's value in place), else the Admin's current academic term.
  Future<({String schoolYear, String term})> _gwaTargetTerm() async {
    final recent = await _client
        .from('student_gpa_records')
        .select('school_year, term')
        .order('updated_at', ascending: false)
        .limit(1)
        .maybeSingle();
    final recentYear = (recent?['school_year'] as String?)?.trim() ?? '';
    final recentTerm = (recent?['term'] as String?)?.trim() ?? '';
    if (recentYear.isNotEmpty && recentTerm.isNotEmpty) {
      return (schoolYear: recentYear, term: recentTerm);
    }

    try {
      final current = await _client
          .from('academic_terms')
          .select('school_year, term')
          .eq('is_current', true)
          .maybeSingle();
      final year = (current?['school_year'] as String?)?.trim() ?? '';
      final term = (current?['term'] as String?)?.trim() ?? '';
      if (year.isNotEmpty && term.isNotEmpty) {
        return (schoolYear: year, term: term);
      }
    } catch (_) {
      // academic_terms not installed — handled below.
    }
    throw Exception(
      'No school year/term is on file yet. Upload a GPA file or start an '
      'academic term (Admin -> Academic Term) first.',
    );
  }

  /// Registrar's manual GWA entry/override for one student. Written to
  /// `student_gpa_records.cumulative_gpa` for the term from [_gwaTargetTerm],
  /// updating that student's row for the term in place (a later GPA upload
  /// for the same term overwrites it again). Other columns of an existing
  /// row are left alone. Returns the "school year / term" label it was filed
  /// under so the caller can show it.
  Future<String> saveGwa({
    required String studentId,
    required double gwa,
  }) async {
    if (gwa.isNaN || gwa < 1.0 || gwa > 5.0) {
      throw Exception('GWA must be between 1.00 and 5.00.');
    }
    final target = await _gwaTargetTerm();
    final rows = await _client
        .from('student_gpa_records')
        .upsert(
          {
            'student_id': studentId,
            'school_year': target.schoolYear,
            'term': target.term,
            'cumulative_gpa': double.parse(gwa.toStringAsFixed(2)),
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          },
          onConflict: 'student_id,school_year,term',
        )
        .select('id');
    if ((rows as List).isEmpty) {
      throw Exception(
        'The database refused the change (no rows written). Check the '
        'student_gpa_records policies (add_student_gpa_records_schema.sql).',
      );
    }
    return '${target.schoolYear} / ${target.term}';
  }

  Future<OverviewStatsModel> fetchOverviewStats() async {
    final students = await fetchStudents();
    return OverviewStatsModel(
      totalStudents: students.length,
      newlyEnrolled: students.where((s) => s.isNewStudent).length,
      rfidPending: students.where((s) => !s.hasRfid).length,
    );
  }

  /// Deduplicated by title (case/whitespace-insensitive): a CFL/Room
  /// Schedule import can leave the same subject sitting under two rows —
  /// a real-coded one and an AUTO-coded fallback (see
  /// fetchClassSectionOfferings' own doc comment for the full mechanism).
  /// Showing both in a picker as if they were different subjects is
  /// exactly what caused a real "no offerings exist" report, so this
  /// keeps one row per title — preferring a real code over an AUTO-xxxx
  /// one when both exist, since that's the one a Registrar would
  /// recognize.
  Future<List<SubjectOption>> fetchSubjects() async {
    final rows =
        await _client.from('subjects').select('id, code, title').order('code');

    final byTitle = <String, SubjectOption>{};
    for (final e in rows as List<dynamic>) {
      final row = e as Map<String, dynamic>;
      final code = row['code'] as String;
      final title = row['title'] as String;
      final key = title.trim().toLowerCase();
      final existing = byTitle[key];
      final isAuto = code.toUpperCase().startsWith('AUTO-');
      if (existing == null ||
          (isAuto == false &&
              existing.code.toUpperCase().startsWith('AUTO-'))) {
        byTitle[key] =
            SubjectOption(id: row['id'] as String, code: code, title: title);
      }
    }
    return byTitle.values.toList();
  }

  /// Room numbers from the `rooms` inventory (add_rooms_schema.sql), for
  /// the Add Class Schedule form's Room dropdown. Natural order, so "Room 2"
  /// sorts before "Room 10".
  Future<List<String>> fetchRoomNumbers() async {
    final rows = await _client.from('rooms').select('room_number');
    final numbers = [
      for (final e in rows as List<dynamic>)
        ((e as Map<String, dynamic>)['room_number'] as String).trim(),
    ]..removeWhere((n) => n.isEmpty);
    int cmp(String a, String b) {
      final re = RegExp(r'\d+|\D+');
      final pa = re.allMatches(a).map((m) => m[0]!).toList();
      final pb = re.allMatches(b).map((m) => m[0]!).toList();
      for (var i = 0; i < pa.length && i < pb.length; i++) {
        final na = int.tryParse(pa[i]);
        final nb = int.tryParse(pb[i]);
        final c = (na != null && nb != null)
            ? na.compareTo(nb)
            : pa[i].toLowerCase().compareTo(pb[i].toLowerCase());
        if (c != 0) return c;
      }
      return pa.length.compareTo(pb.length);
    }

    numbers.sort(cmp);
    return numbers;
  }

  /// [realOnly] drops unfilled positions ("New IT Faculty", "New GE
  /// Instructor 2") — stub profiles the schedule import creates so classes
  /// have an owner. They are not people, so the kiosk's professor picker
  /// must not offer them; the Registrar's class-schedule form still needs
  /// them and keeps the default.
  Future<List<TeacherOption>> fetchTeachers({bool realOnly = false}) async {
    final rows = await _client
        .from('profiles')
        .select('id, first_name, last_name, status')
        .eq('role', 'Teacher')
        .order('last_name');
    final teachers = <TeacherOption>[];
    for (final e in rows as List<dynamic>) {
      final row = e as Map<String, dynamic>;
      final first = (row['first_name'] as String?) ?? '';
      final last = (row['last_name'] as String?) ?? '';
      final fullName = '$first $last'.trim();
      if (realOnly &&
          (row['status'] == 'Placeholder' ||
              isPlaceholderProfessorName(fullName))) {
        continue;
      }
      teachers.add(TeacherOption(id: row['id'] as String, fullName: fullName));
    }
    return teachers;
  }

  Future<List<SectionOption>> fetchSections() async {
    final rows = await _client
        .from('sections')
        .select('id, name, year_level, program')
        .order('name');
    return (rows as List<dynamic>).map((e) {
      final row = e as Map<String, dynamic>;
      return SectionOption(
        id: row['id'] as String,
        name: row['name'] as String,
        yearLevel: row['year_level'] as int? ?? 1,
        program: row['program'] as String?,
      );
    }).toList();
  }

  /// Creates one `class_sections` offering (a specific subject taught by a
  /// specific professor to a specific home section, on a specific
  /// schedule). See docs/superpowers/specs/2026-09-04-irregular-students-schema-design.md
  /// for the full schema rationale. Returns the new row's id.
  Future<String> createClassSection({
    required String subjectId,
    required String sectionId,
    required String professorId,
    required String room,
    required List<String> days,
    required String startTime,
    required String endTime,
    required String schoolYear,
    required String term,
  }) async {
    final row = await _client
        .from('class_sections')
        .insert({
          'subject_id': subjectId,
          'section_id': sectionId,
          'professor_id': professorId,
          'room': room,
          'schedule_days': days,
          'start_time': startTime,
          'end_time': endTime,
          'school_year': schoolYear,
          'term': term,
        })
        .select('id')
        .single();
    return row['id'] as String;
  }

  /// Same offering as [createClassSection], but for the schedule import
  /// flow: re-importing the same file (or a corrected re-upload) must
  /// keep adding meetings to the SAME offering rather than creating a
  /// duplicate `class_sections` row every time. Matches on the four
  /// columns that together identify one offering; room/days/start/end
  /// are left null on a fresh insert — that per-meeting detail now lives
  /// in `class_section_meetings`, not on this row (see
  /// add_class_section_meetings_schema.sql).
  Future<String> findOrCreateClassSection({
    required String subjectId,
    required String sectionId,
    required String professorId,
    required String schoolYear,
    required String term,
  }) async {
    final existing = await _client
        .from('class_sections')
        .select('id')
        .eq('subject_id', subjectId)
        .eq('section_id', sectionId)
        .eq('professor_id', professorId)
        .eq('school_year', schoolYear)
        .eq('term', term)
        .maybeSingle();
    if (existing != null) return existing['id'] as String;

    final inserted = await _client
        .from('class_sections')
        .insert({
          'subject_id': subjectId,
          'section_id': sectionId,
          'professor_id': professorId,
          'school_year': schoolYear,
          'term': term,
        })
        .select('id')
        .single();
    return inserted['id'] as String;
  }

  /// Count of `subjects` rows on file — the Scheduling Officer dashboard's
  /// readiness banner reads this to tell whether the Registrar has
  /// uploaded the Classes+Professor list yet. Deliberately NOT a
  /// `class_sections` count scoped to a school year/term (an earlier
  /// version of this method was): that format carries no section at all
  /// (see ScheduleImportRow's own doc comment), so ScheduleImportRunner
  /// never calls findOrCreateClassSection for it — every row just
  /// resolves/creates a `subjects` + `profiles` row and stops there. A
  /// `class_sections`-based check would (and did) always read zero after
  /// a pure roster upload. `subjects` and `profiles` aren't themselves
  /// scoped by school year/term, so neither is this count.
  /// `count(...)`'s exact() mode asks PostgREST for a real row count
  /// instead of an estimate.
  Future<int> countExistingOfferings() async {
    final response =
        await _client.from('subjects').select('id').count(CountOption.exact);
    return response.count;
  }

  /// Edits one `class_sections` offering — see
  /// supabase/add_class_section_edit_delete.sql for what happens to its
  /// imported meetings.
  Future<void> updateClassSection({
    required String id,
    required String subjectId,
    required String sectionId,
    required String professorId,
    required String schoolYear,
    required String term,
    required String room,
    required List<String> days,
    required String startTime,
    required String endTime,
  }) async {
    try {
      await _client.rpc('update_class_section', params: {
        'p_id': id,
        'p_subject_id': subjectId,
        'p_section_id': sectionId,
        'p_professor_id': professorId,
        'p_school_year': schoolYear,
        'p_term': term,
        'p_room': room,
        'p_days': days,
        'p_start_time': startTime,
        'p_end_time': endTime,
      });
    } on PostgrestException catch (e) {
      throw RegistrarRepositoryException(e.message);
    }
  }

  /// Deletes an offering along with its enrollments and grades (attendance
  /// and meetings cascade). Returns how many enrollments were removed.
  Future<int> deleteClassSection(String id) async {
    try {
      final result =
          await _client.rpc('delete_class_section', params: {'p_id': id});
      return (result as num?)?.toInt() ?? 0;
    } on PostgrestException catch (e) {
      throw RegistrarRepositoryException(e.message);
    }
  }

  static const _classSectionSelect = '''
id,
subject_id,
section_id,
professor_id,
school_year,
term,
room,
schedule_days,
start_time,
end_time,
subjects ( title ),
sections ( name ),
profiles ( first_name, last_name ),
class_section_meetings ( day, start_time, end_time, room )
''';

  static const _meetingDayLabels = {
    'M': 'Mon',
    'T': 'Tue',
    'W': 'Wed',
    'TH': 'Thu',
    'F': 'Fri',
    'S': 'Sat',
  };
  static const _meetingDayOrder = ['M', 'T', 'W', 'TH', 'F', 'S'];

  /// Populates the Class Schedule tab's table with real `class_sections`
  /// offerings. Day/time/room come from the offering's
  /// `class_section_meetings` — where the Scheduling Officer's CFL import and
  /// room auto-assignment write them — falling back to the legacy
  /// `class_sections` columns (manual Add Schedule form) when an offering has
  /// no meetings.
  Future<List<ScheduleEntryModel>> fetchClassSections() async {
    final rows = await _client
        .from('class_sections')
        .select(_classSectionSelect)
        .order('created_at', ascending: false);
    return (rows as List<dynamic>).map((e) {
      final row = e as Map<String, dynamic>;
      final subject = row['subjects'] as Map<String, dynamic>?;
      final section = row['sections'] as Map<String, dynamic>?;
      final professor = row['profiles'] as Map<String, dynamic>?;
      final meetings = (row['class_section_meetings'] as List<dynamic>?)
              ?.cast<Map<String, dynamic>>() ??
          const <Map<String, dynamic>>[];
      final schedule = meetings.isNotEmpty
          ? _scheduleFromMeetings(meetings)
          : (
              room: row['room'] as String? ?? '',
              days: (row['schedule_days'] as List<dynamic>?)?.cast<String>() ??
                  const <String>[],
              timeRange: _formatTimeRange(
                row['start_time'] as String?,
                row['end_time'] as String?,
              ),
            );
      // Prefill values for "Edit": the offering's own columns, else the
      // earliest start / latest end across its meetings ('HH:MM:SS' text
      // sorts chronologically).
      final starts = [
        for (final m in meetings)
          if (m['start_time'] is String) m['start_time'] as String,
      ]..sort();
      final ends = [
        for (final m in meetings)
          if (m['end_time'] is String) m['end_time'] as String,
      ]..sort();
      String? hhmm(String? t) =>
          (t == null || t.length < 5) ? null : t.substring(0, 5);
      return ScheduleEntryModel(
        id: row['id'] as String,
        subject: subject?['title'] as String? ?? '',
        gradeSection: section?['name'] as String? ?? '',
        teacher: _fullName(
          professor?['first_name'] as String?,
          professor?['last_name'] as String?,
        ),
        room: schedule.room,
        days: schedule.days,
        timeRange: schedule.timeRange,
        subjectId: row['subject_id'] as String?,
        sectionId: row['section_id'] as String?,
        professorId: row['professor_id'] as String?,
        schoolYear: row['school_year'] as String?,
        term: row['term'] as String?,
        startTime: hhmm(row['start_time'] as String?) ??
            hhmm(starts.isEmpty ? null : starts.first),
        endTime: hhmm(row['end_time'] as String?) ??
            hhmm(ends.isEmpty ? null : ends.last),
        hasMeetings: meetings.isNotEmpty,
      );
    }).toList();
  }

  /// Collapses an offering's weekly meetings into the single room/days/time
  /// cells the table shows: distinct days in week order, distinct real rooms
  /// ('TBA' = not yet assigned, so skipped) and distinct time ranges, each
  /// joined when a lecture and lab differ.
  ({String room, List<String> days, String timeRange}) _scheduleFromMeetings(
    List<Map<String, dynamic>> meetings,
  ) {
    final days = <String>{};
    final rooms = <String>[];
    final times = <String>[];
    for (final m in meetings) {
      final day = (m['day'] as String?)?.toUpperCase();
      if (day != null) days.add(day);
      final room = (m['room'] as String?)?.trim() ?? '';
      if (room.isNotEmpty && room != 'TBA' && !rooms.contains(room)) {
        rooms.add(room);
      }
      final time = _formatTimeRange(
        m['start_time'] as String?,
        m['end_time'] as String?,
      );
      if (time.isNotEmpty && !times.contains(time)) times.add(time);
    }
    final orderedDays = [
      for (final d in _meetingDayOrder)
        if (days.contains(d)) _meetingDayLabels[d]!,
    ];
    return (
      room: rooms.join(', '),
      days: orderedDays,
      timeRange: times.join(' · '),
    );
  }

  /// Changes the email of the Parent Portal account linked to [studentId]
  /// (see supabase/add_guardian_email_edit_and_enrollment_year_default.sql).
  /// Returns false when the student has no linked guardian account yet — the
  /// caller then creates one instead.
  Future<bool> updateGuardianEmail({
    required String studentId,
    required String email,
  }) async {
    try {
      final result = await _client.rpc('update_student_guardian_email',
          params: {'p_student_id': studentId, 'p_email': email});
      return result == 'updated';
    } on PostgrestException catch (e) {
      throw RegistrarRepositoryException(e.message);
    }
  }

  /// Calls the `enroll_section_students` RPC (see
  /// supabase/add_enroll_section_rpc.sql). Returns how many students were
  /// newly enrolled.
  Future<int> enrollSectionStudents(String classSectionId) async {
    final result = await _client.rpc(
      'enroll_section_students',
      params: {'p_class_section_id': classSectionId},
    );
    return result as int;
  }

  /// Active enrollments -> class_sections -> subjects/sections, left-joined
  /// (client-side — see below) against grades. Every actively-enrolled
  /// student gets a row even with no grade yet (defaults to 5.0 — the
  /// worst end of the 1.00-5.00 scale, where 1.00 is best — which
  /// GradeRemark.fromGrade reports as Failing — "not yet graded" reads the
  /// same as "not yet passing" until a real grade is entered, which is the
  /// honest state rather than inventing a placeholder passing grade).
  ///
  /// `grades` cannot be embedded from `enrollments` via PostgREST (`grades`
  /// has no FK back to `enrollments` — it FKs `students`/`class_sections`
  /// individually, not `enrollments`), so this fetches `enrollments` (the
  /// roster — every currently-active enrollment gets a row, graded or not)
  /// and `grades` (existing grades only) as two separate queries and merges
  /// them client-side, keyed on `student_id|class_section_id`.
  Future<List<GradeRecordModel>> fetchGradeRecords() async {
    final enrollmentRows = await _client
        .from('enrollments')
        .select('''
          student_id,
          class_section_id,
          students ( student_number, profiles ( first_name, last_name ) ),
          class_sections ( term, subjects ( title ), sections ( name, year_level ) )
        ''')
        .eq('status', 'Active')
        .order('student_id')
        .order('class_section_id');

    final gradeRows = await _client
        .from('grades')
        .select('student_id, class_section_id, grade');

    // A subject with no grade of its own shows the student's GWA (GPA upload
    // or manual entry) — that is what the Grades tab's read-only Grade
    // column is fed by; 5.00 only when neither exists.
    final gwaByStudent = await _fetchLatestGwaByStudent();

    final gradeByKey = <String, double>{};
    for (final row in gradeRows as List<dynamic>) {
      final r = row as Map<String, dynamic>;
      final key = '${r['student_id']}|${r['class_section_id']}';
      gradeByKey[key] = (r['grade'] as num).toDouble();
    }

    final records = (enrollmentRows as List<dynamic>).map((e) {
      final row = e as Map<String, dynamic>;
      final studentId = row['student_id'] as String;
      final classSectionId = row['class_section_id'] as String;
      final student = row['students'] as Map<String, dynamic>?;
      final profile = student?['profiles'] as Map<String, dynamic>?;
      final classSection = row['class_sections'] as Map<String, dynamic>?;
      final section = classSection?['sections'] as Map<String, dynamic>?;
      final subject = classSection?['subjects'] as Map<String, dynamic>?;
      final term = classSection?['term'] as String? ?? '';
      final key = '$studentId|$classSectionId';
      final grade = gradeByKey[key] ?? gwaByStudent[studentId] ?? 5.0;

      return GradeRecordModel(
        id: key,
        studentName: _fullName(
          profile?['first_name'] as String?,
          profile?['last_name'] as String?,
        ),
        studentId: student?['student_number'] as String? ?? '',
        gradeSection: section?['name'] as String? ?? '',
        subject: subject?['title'] as String? ?? '',
        grade: grade,
        remark: GradeRemark.fromGrade(grade),
        educationLevel: 'College',
        semester: term.startsWith('2') ? '2nd' : '1st',
      );
    }).toList();

    // A student with a GWA but no active subject enrollment (typical right
    // after a batch enrollment) has no row above, so their GWA would never
    // show on the Grades tab: give them one overall row.
    final enrolled = {
      for (final e in enrollmentRows) e['student_id'] as String,
    };
    final gwaOnly = gwaByStudent.keys.where((id) => !enrolled.contains(id));
    if (gwaOnly.isNotEmpty) {
      final wanted = gwaOnly.toSet();
      final studentRows = await _client
          .from('students')
          .select('id, student_number, profiles ( first_name, last_name ), sections ( name )');
      for (final s in studentRows as List<dynamic>) {
        final row = s as Map<String, dynamic>;
        final id = row['id'] as String;
        if (!wanted.contains(id)) continue;
        final profile = row['profiles'] as Map<String, dynamic>?;
        final section = row['sections'] as Map<String, dynamic>?;
        final grade = gwaByStudent[id]!;
        records.add(GradeRecordModel(
          id: 'gwa|$id',
          studentName: _fullName(
            profile?['first_name'] as String?,
            profile?['last_name'] as String?,
          ),
          studentId: row['student_number'] as String? ?? '',
          gradeSection: section?['name'] as String? ?? '',
          subject: 'General Weighted Average',
          grade: grade,
          remark: GradeRemark.fromGrade(grade),
          educationLevel: 'College',
          semester: '1st',
        ));
      }
    }
    return records;
  }

  /// Upsert — a registrar re-saving an already-graded student updates the
  /// existing row rather than violating the (student_id, class_section_id)
  /// unique constraint.
  Future<void> saveGrade({
    required String studentId,
    required String classSectionId,
    required double grade,
  }) async {
    await _client.from('grades').upsert(
      {
        'student_id': studentId,
        'class_section_id': classSectionId,
        'grade': grade,
      },
      onConflict: 'student_id,class_section_id',
    );
  }

  /// A student's active `enrollments`, joined through to their
  /// class_sections/subjects/sections/profiles — see
  /// docs/superpowers/specs/2026-09-04-irregular-students-schema-design.md
  /// for why a student can have an enrollment whose section differs from
  /// [homeSectionName] ("irregular" for that one subject). [homeSectionName]
  /// is compared by name (not id) since RegistrarStudentModel only carries
  /// the display name, not the raw `section_id`.
  Future<List<StudentEnrollmentModel>> fetchStudentEnrollments({
    required String studentId,
    required String homeSectionName,
  }) async {
    final rows = await _client.from('enrollments').select('''
          id,
          class_sections (
            subjects ( title ),
            sections ( name ),
            profiles ( first_name, last_name )
          )
        ''').eq('student_id', studentId).eq('status', 'Active');

    return (rows as List<dynamic>).map((e) {
      final row = e as Map<String, dynamic>;
      final classSection = row['class_sections'] as Map<String, dynamic>?;
      final subject = classSection?['subjects'] as Map<String, dynamic>?;
      final section = classSection?['sections'] as Map<String, dynamic>?;
      final professor = classSection?['profiles'] as Map<String, dynamic>?;
      final sectionName = section?['name'] as String? ?? '';
      return StudentEnrollmentModel(
        enrollmentId: row['id'] as String,
        subjectTitle: subject?['title'] as String? ?? '',
        sectionName: sectionName,
        professorName: _fullName(
          professor?['first_name'] as String?,
          professor?['last_name'] as String?,
        ),
        isIrregular: sectionName.isNotEmpty && sectionName != homeSectionName,
      );
    }).toList();
  }

  /// Every class_sections offering of [subjectId], from ANY section — not
  /// scoped to a particular student's home section, since offering that
  /// full choice is the entire mechanism for enrolling a student
  /// irregularly (see [fetchStudentEnrollments]'s own doc comment).
  ///
  /// Matches by TITLE against every subject sharing it, not just
  /// [subjectId] alone — duplicate subject rows (same title, different id/
  /// code) can exist when a CFL/Room Schedule import's title-match against
  /// an already-coded subject misses and falls back to creating a new
  /// AUTO-coded row (see resolveSubjectId's own doc comment; confirmed as
  /// the cause of a real "no offerings exist for this subject" report — the
  /// Subject dropdown here lists every subjects row undeduplicated, so
  /// picking the "wrong" duplicate of a title showed zero offerings even
  /// though the other duplicate had some). Looking up by title means an
  /// offering committed under either duplicate still shows up regardless
  /// of which one was picked from the dropdown.
  Future<List<ClassSectionOffering>> fetchClassSectionOfferings(
    String subjectId,
  ) async {
    final chosen = await _client
        .from('subjects')
        .select('title')
        .eq('id', subjectId)
        .maybeSingle();
    final title = chosen?['title'] as String?;
    if (title == null) return const [];

    final sameTitleSubjects =
        await _client.from('subjects').select('id').ilike('title', title);
    final subjectIds = [
      for (final s in sameTitleSubjects as List) s['id'] as String,
    ];
    if (subjectIds.isEmpty) return const [];

    final rows = await _client
        .from('class_sections')
        .select('id, sections ( name ), profiles ( first_name, last_name )')
        .inFilter('subject_id', subjectIds);

    return (rows as List<dynamic>).map((e) {
      final row = e as Map<String, dynamic>;
      final section = row['sections'] as Map<String, dynamic>?;
      final professor = row['profiles'] as Map<String, dynamic>?;
      return ClassSectionOffering(
        id: row['id'] as String,
        sectionName: section?['name'] as String? ?? '',
        professorName: _fullName(
          professor?['first_name'] as String?,
          professor?['last_name'] as String?,
        ),
      );
    }).toList();
  }

  /// Enrolls [studentId] in [classSectionId] — the actual "mark this
  /// student irregular for Subject X" action when that offering belongs
  /// to a different section than the student's own. Upsert: re-enrolling
  /// after a previous drop (status='Dropped') reactivates the same row
  /// rather than violating the (student_id, class_section_id) unique
  /// constraint.
  Future<void> enrollStudent({
    required String studentId,
    required String classSectionId,
  }) async {
    await _client.from('enrollments').upsert(
      {
        'student_id': studentId,
        'class_section_id': classSectionId,
        'status': 'Active',
      },
      onConflict: 'student_id,class_section_id',
    );
  }

  /// Soft-drops an enrollment (status='Dropped') rather than deleting the
  /// row — matches this schema's own `status` convention ('Active' |
  /// 'Dropped').
  Future<void> dropEnrollment(String enrollmentId) async {
    await _client
        .from('enrollments')
        .update({'status': 'Dropped'}).eq('id', enrollmentId);
  }

  /// Withdraws a student: soft-drops every one of their Active enrollments.
  /// That is what the ML retrain labels as a dropout (a student whose
  /// enrollments are *all* Dropped), and each row can still be restored
  /// with [enrollStudent].
  Future<void> dropStudent(String studentId) async {
    await _client
        .from('enrollments')
        .update({'status': 'Dropped'})
        .eq('student_id', studentId)
        .eq('status', 'Active');
  }

  String _fullName(String? first, String? last) {
    return '${(first ?? '').trim()} ${(last ?? '').trim()}'.trim();
  }

  String _formatDate(DateTime date) => '${date.month}-${date.day}-${date.year}';

  /// Formats two Postgres `time` values (e.g. `08:30:00`) as `8:30 AM -
  /// 10:00 AM`. Falls back to whatever raw text is present (or empty) when
  /// either side doesn't parse, rather than throwing on unexpected input.
  String _formatTimeRange(String? start, String? end) {
    final s = _formatTime(start);
    final e = _formatTime(end);
    if (s == null && e == null) return '';
    return '${s ?? ''} - ${e ?? ''}';
  }

  String? _formatTime(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final parts = raw.split(':');
    if (parts.length < 2) return raw;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return raw;
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour % 12 == 0 ? 12 : hour % 12;
    return '$displayHour:${minute.toString().padLeft(2, '0')} $period';
  }
}
