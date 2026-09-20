import 'package:parent_portal_module/models/attendance_models.dart';
import 'package:parent_portal_module/models/good_moral_request_status.dart';
import 'package:parent_portal_module/models/schedule_models.dart';
import 'package:parent_portal_module/models/violation_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Wires `parent_portal_module`'s presentation layer to real Supabase data.
/// See `docs/superpowers/specs/2026-09-09-student-portal-db-wiring-design.md`.
class ParentPortalRepository {
  ParentPortalRepository(this._client);

  final SupabaseClient _client;

  /// The `students.id` of the child linked to [parentId] via
  /// `parent_student_links` — every other fetch here is keyed by that id, so
  /// the Parent Portal shows exactly what the Student Portal would show that
  /// student. `null` when this parent has no linked child yet. With several
  /// links, the first one is used.
  Future<String?> fetchLinkedStudentId(String parentId) async {
    final row = await _client
        .from('parent_student_links')
        .select('student_id')
        .eq('parent_id', parentId)
        .limit(1)
        .maybeSingle();
    return row?['student_id'] as String?;
  }

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
          profiles ( first_name, last_name )
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
        dateFiled: DateTime.parse(row['created_at'] as String),
        description: row['incident_notes'] as String? ?? '',
        recordedBy: reporterName.isEmpty ? 'Unknown' : reporterName,
      );
    }).toList();
  }

  String _fullName(String? first, String? last) {
    return '${(first ?? '').trim()} ${(last ?? '').trim()}'.trim();
  }

  /// `attendance_records` is section-level (one status per student per
  /// section per day) — NOT per-subject. See this repo's
  /// docs/superpowers/specs/2026-09-04-irregular-students-schema-design.md,
  /// which explicitly defers true per-subject attendance (tap-in/tap-out +
  /// per-subject validation) to a future, not-yet-built sub-project. Each
  /// returned `AttendanceEntry` has `subjectId`/`subjectName` left null
  /// (see the nullable-field task) rather than inventing a fake subject.
  Future<List<AttendanceEntry>> fetchAttendance(
    String studentId,
    String sectionId, {
    required DateTime from,
    required DateTime to,
  }) async {
    final rows = await _client
        .from('attendance_records')
        .select('session_date, status')
        .eq('student_id', studentId)
        .eq('section_id', sectionId)
        .gte('session_date', from.toIso8601String().substring(0, 10))
        .lte('session_date', to.toIso8601String().substring(0, 10));

    return (rows as List<dynamic>).map((e) {
      final row = e as Map<String, dynamic>;
      return AttendanceEntry(
        date: DateTime.parse(row['session_date'] as String),
        subjectId: null,
        subjectName: null,
        status: AttendanceStatusX.fromDbValue(row['status'] as String),
      );
    }).toList();
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
            id, room, schedule_days, start_time, end_time,
            subjects ( title ),
            profiles ( first_name, last_name )
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
      return StudentScheduleEntryModel(
        id: cs['id'] as String,
        subjectTitle: subject?['title'] as String? ?? 'Subject',
        professorName: '$first $last'.trim(),
        room: cs['room'] as String? ?? '',
        days: ((cs['schedule_days'] as List<dynamic>?) ?? const [])
            .cast<String>(),
        startTime: cs['start_time'] as String? ?? '',
        endTime: cs['end_time'] as String? ?? '',
      );
    }).toList();
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
  }) async {
    await _client.from('good_moral_requests').insert({
      'student_id': studentId,
      'document_type': documentType,
      'purpose': purpose,
      'requested_by': requestedBy,
      'remarks': remarks,
    });
  }

  /// The requester's own past Good Moral (or other document) requests, most
  /// recent first — for the "My Document Requests" status list.
  Future<List<GoodMoralRequestStatus>> fetchMyGoodMoralRequests(
    String studentId,
  ) async {
    final rows = await _client
        .from('good_moral_requests')
        .select('id, document_type, purpose, status, request_date')
        .eq('student_id', studentId)
        .order('request_date', ascending: false);

    return (rows as List<dynamic>).map((e) {
      final row = e as Map<String, dynamic>;
      return GoodMoralRequestStatus(
        id: row['id'] as String,
        documentType: row['document_type'] as String,
        purpose: row['purpose'] as String,
        status: row['status'] as String? ?? 'Pending',
        requestDate: DateTime.parse(row['request_date'] as String),
      );
    }).toList();
  }
}
