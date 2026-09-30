import 'package:supabase_flutter/supabase_flutter.dart';

import 'grade_import/grade_import_row.dart';

/// Resolves/commits one [GradeImportRow] at a time against
/// `student_gpa_records` — the Supabase half of the GPA batch import,
/// mirroring EnrollmentImportRepository's own split from its pure-Dart
/// parser (grade_import/grade_file_parser.dart).
class GradeImportRepository {
  GradeImportRepository(this._client);
  final SupabaseClient _client;

  /// Matches [row] against `students.student_number` (the same raw format
  /// the batch enrollment upload keys on) and upserts one GPA snapshot for
  /// (student, [schoolYear], [term]) — re-uploading the same term updates
  /// that term's row in place rather than duplicating it.
  ///
  /// Returns false (skip, not an error) when no student with this number
  /// exists yet: this GPA report can genuinely predate that student's own
  /// batch-enrollment upload for the term (the registrar's real workflow
  /// already has this ordering gap for CFL/Room Schedule data — see
  /// EnrollmentImportRunner's own doc comment), so there's nothing to
  /// attach the record to yet rather than a data problem to surface as an
  /// error.
  Future<bool> upsertGpaRecord(
    GradeImportRow row, {
    required String schoolYear,
    required String term,
  }) async {
    final student = await _client
        .from('students')
        .select('id')
        .eq('student_number', row.studentNumber)
        .maybeSingle();
    if (student == null) return false;
    final studentId = student['id'] as String;

    await _client.from('student_gpa_records').upsert(
      {
        'student_id': studentId,
        'school_year': schoolYear,
        'term': term,
        'cumulative_gpa': row.cumulativeGpa,
        'current_term_gpa': row.currentTermGpa,
        'failed_courses_count': row.failedCoursesCount ?? 0,
        'transfer_units': row.transferUnits,
        'units_taken_cumulative': row.cumulativeUnitsTaken,
        'units_taken_current_term': row.currentTermUnitsTaken,
      },
      onConflict: 'student_id,school_year,term',
    );
    return true;
  }
}
