import 'package:registrar_module/registrar_module.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// `SubjectOption`/`TeacherOption` are UI-facing models consumed by
// `ClassScheduleView` (packages/registrar_module), so — like every other
// model this repository returns (RegistrarStudentModel, ScheduleEntryModel,
// etc.) — they're defined over there, not here: `registrar_module` cannot
// depend back on this app package, so `class_schedule_view.dart` couldn't
// import them if they lived in this file. Re-exported here so callers that
// only import this repository (e.g. its signature-guard test) can still
// reference the type names directly.
export 'package:registrar_module/registrar_module.dart'
    show SubjectOption, TeacherOption;

class RegistrarRepositoryException implements Exception {
  RegistrarRepositoryException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Backs the Registrar dashboard's Overview/Student Records/RFID Management
/// and Class Schedule tabs with real `students`/`profiles`/`sections`/
/// `subjects`/`class_sections` data. Grades stays on [RegistrarMockData] —
/// there's no `grade_records` table yet (a bigger schema piece, tracked
/// separately).
class RegistrarRepository {
  RegistrarRepository(this._client);

  final SupabaseClient _client;

  static const _studentSelect = '''
id,
student_number,
rfid_uid,
created_at,
enrollment_year,
profiles ( first_name, last_name, email, phone_number, is_active ),
sections ( name, program ),
parent_student_links (
  profiles!parent_student_links_parent_id_fkey ( first_name, last_name )
)
''';

  Future<List<RegistrarStudentModel>> fetchStudents() async {
    final rows = await _client
        .from('students')
        .select(_studentSelect)
        .order('created_at', ascending: false);

    final currentYear = DateTime.now().year;

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
      final createdAt = DateTime.tryParse(row['created_at'] as String? ?? '');
      final enrollmentYear = row['enrollment_year'] as int?;

      return RegistrarStudentModel(
        id: row['id'] as String,
        name: _fullName(
          profile?['first_name'] as String?,
          profile?['last_name'] as String?,
        ),
        studentId: row['student_number'] as String? ?? '',
        program: section?['program'] as String? ?? '',
        section: section?['name'] as String? ?? '',
        // No grades table exists yet — see the doc comment above.
        gpa: null,
        status: (profile?['is_active'] as bool? ?? true)
            ? EnrollmentStatus.active
            : EnrollmentStatus.inactive,
        hasRfid: rfidUid != null && rfidUid.isNotEmpty,
        isNewStudent: enrollmentYear != null && enrollmentYear == currentYear,
        parentGuardian: _fullName(
          parentProfile?['first_name'] as String?,
          parentProfile?['last_name'] as String?,
        ),
        contactNo: profile?['phone_number'] as String? ?? '',
        email: profile?['email'] as String? ?? '',
        enrolledDate: createdAt == null ? '' : _formatDate(createdAt),
      );
    }).toList();
  }

  Future<OverviewStatsModel> fetchOverviewStats() async {
    final students = await fetchStudents();
    final gpas = students.map((s) => s.gpa).whereType<double>().toList();
    return OverviewStatsModel(
      totalStudents: students.length,
      averageGpa: gpas.isEmpty
          ? null
          : gpas.reduce((a, b) => a + b) / gpas.length,
      rfidPending: students.where((s) => !s.hasRfid).length,
    );
  }

  Future<List<SubjectOption>> fetchSubjects() async {
    final rows = await _client
        .from('subjects')
        .select('id, code, title')
        .order('code');
    return (rows as List<dynamic>).map((e) {
      final row = e as Map<String, dynamic>;
      return SubjectOption(
        id: row['id'] as String,
        code: row['code'] as String,
        title: row['title'] as String,
      );
    }).toList();
  }

  Future<List<TeacherOption>> fetchTeachers() async {
    final rows = await _client
        .from('profiles')
        .select('id, first_name, last_name')
        .eq('role', 'Teacher')
        .order('last_name');
    return (rows as List<dynamic>).map((e) {
      final row = e as Map<String, dynamic>;
      final first = (row['first_name'] as String?) ?? '';
      final last = (row['last_name'] as String?) ?? '';
      return TeacherOption(
        id: row['id'] as String,
        fullName: '$first $last'.trim(),
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

  static const _classSectionSelect = '''
id,
room,
schedule_days,
start_time,
end_time,
subjects ( title ),
sections ( name ),
profiles ( first_name, last_name )
''';

  /// Populates the Class Schedule tab's table with real `class_sections`
  /// offerings.
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
      final days =
          (row['schedule_days'] as List<dynamic>?)?.cast<String>() ??
              const <String>[];
      return ScheduleEntryModel(
        id: row['id'] as String,
        subject: subject?['title'] as String? ?? '',
        gradeSection: section?['name'] as String? ?? '',
        teacher: _fullName(
          professor?['first_name'] as String?,
          professor?['last_name'] as String?,
        ),
        room: row['room'] as String? ?? '',
        days: days,
        timeRange: _formatTimeRange(
          row['start_time'] as String?,
          row['end_time'] as String?,
        ),
      );
    }).toList();
  }

  /// Best-effort default section for a newly [createClassSection]d row. The
  /// Class Schedule form's Education Level/Year Level/Section pills aren't
  /// wired to real `sections` rows yet (only Subject/Teacher became real
  /// dropdowns in this task — see class_schedule_view.dart, which also
  /// greys those pills out and captions them as not-yet-wired so this
  /// doesn't read as a working control). This picks the first section
  /// alphabetically as a stand-in until a dedicated Section picker lands.
  /// Returns the section's id and name — the caller surfaces the name in
  /// its success message so a wrong/arbitrary section is never a silent,
  /// undetectable write. Returns null when no sections exist.
  Future<({String id, String name})?> fetchDefaultSection() async {
    final rows = await _client
        .from('sections')
        .select('id, name')
        .order('name')
        .limit(1);
    final list = rows as List<dynamic>;
    if (list.isEmpty) return null;
    final row = list.first as Map<String, dynamic>;
    return (id: row['id'] as String, name: row['name'] as String? ?? '');
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
