import 'package:registrar_module/registrar_module.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RegistrarRepositoryException implements Exception {
  RegistrarRepositoryException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Backs the Registrar dashboard's Overview/Student Records/RFID Management
/// tabs with real `students`/`profiles`/`sections` data. Grades and Class
/// Schedule stay on [RegistrarMockData] — there's no `grade_records` or
/// `class_schedules` table yet (a bigger schema piece, tracked separately).
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

  String _fullName(String? first, String? last) {
    return '${(first ?? '').trim()} ${(last ?? '').trim()}'.trim();
  }

  String _formatDate(DateTime date) => '${date.month}-${date.day}-${date.year}';
}
