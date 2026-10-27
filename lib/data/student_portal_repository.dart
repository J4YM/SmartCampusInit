import 'package:dashboard_layout/dashboard_layout.dart' show GoodMoralFormData;
import 'package:student_portal_module/models/attendance_models.dart';
import 'package:student_portal_module/models/concern_report_status.dart';
import 'package:student_portal_module/models/good_moral_request_status.dart';
import 'package:student_portal_module/models/referral_request_status.dart';
import 'package:student_portal_module/models/schedule_models.dart';
import 'package:student_portal_module/models/student_risk_snapshot.dart';
import 'package:student_portal_module/models/violation_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'good_moral_prefill.dart' as prefill;

/// Maps one `attendance_records` row (selected with
/// `session_date, status, class_section_id, class_sections ( subject_id,
/// subjects ( title ) )`) to an [AttendanceEntry]. Legacy rows with no class
/// keep null subject fields.
AttendanceEntry attendanceEntryFromRow(Map<String, dynamic> row) {
  final classSection = row['class_sections'] as Map<String, dynamic>?;
  final subject = classSection?['subjects'] as Map<String, dynamic>?;
  final title = (subject?['title'] as String?)?.trim();
  return AttendanceEntry(
    date: DateTime.parse(row['session_date'] as String).toLocal(),
    subjectId: classSection?['subject_id'] as String?,
    subjectName: (title == null || title.isEmpty) ? null : title,
    status: AttendanceStatusX.fromDbValue(row['status'] as String),
  );
}

/// Wires `student_portal_module`'s presentation layer to real Supabase data.
/// See `docs/superpowers/specs/2026-09-09-student-portal-db-wiring-design.md`.
class StudentPortalRepository {
  StudentPortalRepository(this._client);

  final SupabaseClient _client;

  /// `student_violations` joined to `handbook_offenses` and `profiles` for
  /// reported_by, excluding archived rows — matches the same shape
  /// `DisciplineRepository` already queries this table with.
  Future<List<StudentViolationModel>> fetchViolations(String studentId) async {
    final rows = await _client
        .from('student_violations')
        .select('''
          id,
          status,
          created_at,
          incident_notes,
          handbook_offenses ( description, category ),
          profiles!student_violations_reported_by_fkey ( first_name, last_name )
        ''')
        .eq('student_id', studentId)
        .filter('archived_at', 'is', null)
        .order('created_at', ascending: false);

    return (rows as List<dynamic>).map((e) {
      final row = e as Map<String, dynamic>;
      final offense = row['handbook_offenses'] as Map<String, dynamic>?;
      final reporter = row['profiles'] as Map<String, dynamic>?;
      final reporterName = _fullName(
        reporter?['first_name'] as String?,
        reporter?['last_name'] as String?,
      );
      return StudentViolationModel(
        id: row['id'] as String,
        title: offense?['description'] as String? ?? 'Violation',
        category: ViolationCategoryX.fromDbValue(
          offense?['category'] as String? ?? 'Minor',
        ),
        status: ViolationStatusX.fromDbValue(row['status'] as String),
        dateFiled: DateTime.parse(row['created_at'] as String).toLocal(),
        description: row['incident_notes'] as String? ?? '',
        recordedBy: reporterName.isEmpty ? 'Unknown' : reporterName,
      );
    }).toList();
  }

  String _fullName(String? first, String? last) {
    return '${(first ?? '').trim()} ${(last ?? '').trim()}'.trim();
  }

  /// `attendance_records` is per class (`class_section_id`): a student can
  /// have several rows on one day, one per class, each carrying the class's
  /// subject. Legacy rows recorded before per-class attendance have a null
  /// class and so null `subjectId`/`subjectName`. Per-day rollups (worst
  /// status wins) are done by the UI via `aggregateStatus`.
  Future<List<AttendanceEntry>> fetchAttendance(
    String studentId,
    String sectionId, {
    required DateTime from,
    required DateTime to,
  }) async {
    final rows = await _client
        .from('attendance_records')
        .select(
            'session_date, status, class_section_id, class_sections ( subject_id, subjects ( title ) )')
        .eq('student_id', studentId)
        .eq('section_id', sectionId)
        .gte('session_date', from.toIso8601String().substring(0, 10))
        .lte('session_date', to.toIso8601String().substring(0, 10));

    return (rows as List<dynamic>)
        .map((e) => attendanceEntryFromRow(e as Map<String, dynamic>))
        .toList();
  }

  /// The school days in [from]..[to] the student tapped in but never tapped
  /// out (`missed_tap_outs`, supabase/replace_auto_tap_out.sql), as plain
  /// dates. Empty when the table is not migrated yet or cannot be read.
  Future<Set<DateTime>> fetchMissedTapOutDays(
    String studentId, {
    required DateTime from,
    required DateTime to,
  }) async {
    try {
      final rows = await _client
          .from('missed_tap_outs')
          .select('school_day')
          .eq('student_id', studentId)
          .gte('school_day', from.toIso8601String().substring(0, 10))
          .lte('school_day', to.toIso8601String().substring(0, 10));
      return {
        for (final r in rows as List<dynamic>)
          if (DateTime.tryParse(
                  (r as Map<String, dynamic>)['school_day'] as String? ?? '')
              case final d?)
            DateTime(d.year, d.month, d.day),
      };
    } catch (_) {
      return const {};
    }
  }

  /// Active enrollments -> class_sections -> subjects, for the "My
  /// Schedule" card. See
  /// docs/superpowers/specs/2026-09-04-irregular-students-schema-design.md
  /// for the schema this reads (built, but populated only via the Enroll
  /// Section tool — see registrar_repository.dart's
  /// enrollSectionStudents).
  Future<List<StudentScheduleEntryModel>> fetchSchedule(String studentId) async {
    final rows = await _client
        .from('enrollments')
        .select('''
          class_sections (
            id, subject_id, room, schedule_days, start_time, end_time,
            subjects ( title ),
            profiles ( first_name, last_name ),
            class_section_meetings ( day, start_time, end_time, room )
          )
        ''')
        .eq('student_id', studentId)
        .eq('status', 'Active');

    return (rows as List<dynamic>)
        .map((e) => (e as Map<String, dynamic>)['class_sections'] as Map<String, dynamic>?)
        .whereType<Map<String, dynamic>>()
        .map((cs) {
      final subject = cs['subjects'] as Map<String, dynamic>?;
      final professor = cs['profiles'] as Map<String, dynamic>?;
      final first = (professor?['first_name'] as String?) ?? '';
      final last = (professor?['last_name'] as String?) ?? '';
      // The schedule import writes real day/time/room to
      // class_section_meetings and leaves the class_sections columns above
      // empty, so those meetings are what the portal must show.
      final meetings = [
        for (final m in (cs['class_section_meetings'] as List<dynamic>?) ?? const [])
          ScheduleMeetingModel(
            day: (m as Map<String, dynamic>)['day'] as String? ?? '',
            startTime: m['start_time'] as String? ?? '',
            endTime: m['end_time'] as String? ?? '',
            room: m['room'] as String? ?? '',
          ),
      ]..sort((a, b) {
          final byTime = a.startTime.compareTo(b.startTime);
          return byTime != 0 ? byTime : a.day.compareTo(b.day);
        });
      return StudentScheduleEntryModel(
        id: cs['id'] as String,
        subjectId: cs['subject_id'] as String?,
        subjectTitle: subject?['title'] as String? ?? 'Subject',
        professorName: '$first $last'.trim(),
        room: cs['room'] as String? ?? '',
        days: ((cs['schedule_days'] as List<dynamic>?) ?? const [])
            .cast<String>(),
        startTime: cs['start_time'] as String? ?? '',
        endTime: cs['end_time'] as String? ?? '',
        meetings: meetings,
      );
    }).toList();
  }

  /// "BS Information Technology · 4th Year · Section 4A" for the portal
  /// header, from the student's own `students` row (null if it can't be read).
  Future<String?> fetchProgramLine(String studentId) async {
    final row = await _client
        .from('students')
        .select('course, year_level, sections ( name )')
        .eq('id', studentId)
        .maybeSingle();
    if (row == null) return null;
    final course = (row['course'] as String?)?.trim() ?? '';
    final year = row['year_level'] as int?;
    final section = ((row['sections'] as Map<String, dynamic>?)?['name'] as String?)?.trim();
    String ordinal(int n) => switch (n) {
          1 => '1st',
          2 => '2nd',
          3 => '3rd',
          _ => '${n}th',
        };
    final parts = [
      if (course.isNotEmpty) course,
      if (year != null) '${ordinal(year)} Year',
      if (section != null && section.isNotEmpty) 'Section $section',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  /// Inserts a new `good_moral_requests` row for the student/parent's own
  /// request — see
  /// supabase/add_good_moral_status_and_insert_policies.sql for the
  /// INSERT policies that let a student/parent create their own request
  /// (defaults `status` to 'Pending').
  Future<void> submitGoodMoralRequest({
    required String studentId,
    required String documentType,
    required String purpose,
    required String requestedBy,
    String? remarks,
    Map<String, dynamic>? formData,
  }) async {
    await _client.from('good_moral_requests').insert({
      'student_id': studentId,
      'document_type': documentType,
      'purpose': purpose,
      'requested_by': requestedBy,
      'remarks': remarks,
      if (formData != null) 'form_data': formData,
    });
  }

  /// The Good Moral slip filled in from the student's own record: name,
  /// student number, section, contact number and the year they started.
  /// The school holds no address, middle name or last-attended term, so those
  /// stay blank for the student to write. Null when the record cannot be read.
  Future<GoodMoralFormData?> fetchGoodMoralPrefill(String studentId) =>
      prefill.fetchGoodMoralPrefill(_client, studentId);

  /// Sends a request the Discipline Office returned back with the edited slip
  /// (supabase/add_good_moral_form_data.sql). The earlier submission is kept
  /// in the request's history.
  Future<void> resubmitGoodMoralRequest({
    required String requestId,
    required String purpose,
    String? remarks,
    required Map<String, dynamic> formData,
  }) async {
    await _client.rpc('resubmit_good_moral_request', params: {
      'p_request_id': requestId,
      'p_purpose': purpose,
      'p_remarks': remarks,
      'p_form_data': formData,
    });
  }

  /// Files a self referral to Guidance (supabase/add_guidance_referrals.sql).
  /// Only Guidance reads it.
  Future<void> submitReferral({
    required String studentId,
    required ReferralConcern concern,
    required String details,
    bool urgent = false,
  }) async {
    await _client.rpc('submit_student_referral', params: {
      'p_referrer_id': studentId,
      'p_concern': concern.name,
      'p_details': details,
      'p_urgent': urgent,
    });
  }

  /// The student's own self referrals and their status, most recent first.
  Future<List<ReferralRequestStatus>> fetchMyReferrals(String studentId) async {
    final rows = await _client
        .rpc('my_student_referrals', params: {'p_referrer_id': studentId});
    return (rows as List<dynamic>).map((e) {
      final row = e as Map<String, dynamic>;
      return ReferralRequestStatus(
        id: row['id'] as String,
        concern: ReferralConcern.fromDb(row['concern'] as String?),
        urgency: row['urgency'] as String? ?? 'Normal',
        status: row['status'] as String? ?? 'Pending',
        counselorNote: row['counselor_note'] as String?,
        createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
      );
    }).toList();
  }

  /// Files a concern report to Student Affairs
  /// (supabase/add_concern_reports.sql).
  Future<void> submitConcernReport({
    required String studentId,
    required ConcernType concern,
    required String details,
    bool urgent = false,
  }) async {
    await _client.rpc('submit_concern_report', params: {
      'p_reporter_id': studentId,
      'p_concern': concern.name,
      'p_details': details,
      'p_urgent': urgent,
    });
  }

  /// The student's own concern reports and their status, most recent first.
  Future<List<ConcernReportStatus>> fetchMyConcernReports(
      String studentId) async {
    final rows = await _client
        .rpc('my_concern_reports', params: {'p_reporter_id': studentId});
    return (rows as List<dynamic>).map((e) {
      final row = e as Map<String, dynamic>;
      return ConcernReportStatus(
        id: row['id'] as String,
        concern: ConcernType.fromDb(row['concern'] as String?),
        urgency: row['urgency'] as String? ?? 'Normal',
        status: row['status'] as String? ?? 'Pending',
        handlerNote: row['handler_note'] as String?,
        createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
      );
    }).toList();
  }

  /// The requester's own past Good Moral (or other document) requests, most
  /// recent first — for the "My Document Requests" status list.
  Future<List<GoodMoralRequestStatus>> fetchMyGoodMoralRequests(
    String studentId,
  ) async {
    final rows = await _client
        .from('good_moral_requests')
        .select(
            'id, document_type, purpose, status, request_date, flag_note, form_data')
        .eq('student_id', studentId)
        .order('request_date', ascending: false);

    return (rows as List<dynamic>).map((e) {
      final row = e as Map<String, dynamic>;
      return GoodMoralRequestStatus(
        id: row['id'] as String,
        documentType: row['document_type'] as String,
        purpose: row['purpose'] as String,
        status: row['status'] as String? ?? 'Pending',
        requestDate: DateTime.parse(row['request_date'] as String).toLocal(),
        flagNote: row['flag_note'] as String?,
        formData: row['form_data'] is Map
            ? Map<String, dynamic>.from(row['form_data'] as Map)
            : null,
      );
    }).toList();
  }

  /// The student's own most recent saved risk assessment, or null if none
  /// exists. Reads the stored `risk_assessments` row only — the ML model is
  /// never invoked from the student side.
  Future<StudentRiskSnapshot?> fetchLatestRisk(String studentId) async {
    final row = await _client
        .from('risk_assessments')
        .select('risk_level, dropout_probability, key_factors, '
            'recommendations, risk_reasoning, computed_at')
        .eq('student_id', studentId)
        .order('computed_at', ascending: false)
        .limit(1)
        .maybeSingle();
    return row == null ? null : StudentRiskSnapshot.fromRow(row);
  }
}
