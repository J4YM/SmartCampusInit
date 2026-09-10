import 'package:student_portal_module/models/attendance_models.dart';
import 'package:student_portal_module/models/violation_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
}
