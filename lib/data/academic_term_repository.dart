import 'package:supabase_flutter/supabase_flutter.dart';

/// The school year / semester the system is currently running in — see
/// supabase/add_academic_term_migration.sql.
class AcademicTerm {
  const AcademicTerm({
    required this.id,
    required this.schoolYear,
    required this.term,
    required this.isCurrent,
    required this.startedAt,
    this.closedAt,
    this.archivedCounts = const {},
  });

  factory AcademicTerm.fromRow(Map<String, dynamic> row) {
    final counts = row['archived_counts'];
    return AcademicTerm(
      id: row['id'] as String,
      schoolYear: row['school_year'] as String? ?? '',
      term: row['term'] as String? ?? '',
      isCurrent: row['is_current'] as bool? ?? false,
      startedAt: DateTime.tryParse(row['started_at'] as String? ?? '')?.toLocal() ??
          DateTime.now(),
      closedAt: DateTime.tryParse(row['closed_at'] as String? ?? '')?.toLocal(),
      archivedCounts: counts is Map
          ? {
              for (final e in counts.entries)
                e.key.toString(): (e.value as num?)?.toInt() ?? 0,
            }
          : const {},
    );
  }

  final String id;
  final String schoolYear;
  final String term;
  final bool isCurrent;
  final DateTime startedAt;
  final DateTime? closedAt;
  final Map<String, int> archivedCounts;

  String get label => '$schoolYear · $term';
}

class TermMigrationResult {
  const TermMigrationResult({
    required this.archived,
    required this.skipped,
    required this.studentsDeactivated,
  });

  final Map<String, int> archived;
  final List<String> skipped;
  final int studentsDeactivated;

  int get archivedTotal => archived.values.fold(0, (a, b) => a + b);
}

class AcademicTermRepositoryException implements Exception {
  AcademicTermRepositoryException(this.message);
  final String message;

  @override
  String toString() => message;
}

class AcademicTermRepository {
  AcademicTermRepository(this._client);

  final SupabaseClient _client;

  /// Newest first; the current term (if any) is the row with `isCurrent`.
  Future<List<AcademicTerm>> fetchTerms() async {
    try {
      final rows = await _client
          .from('academic_terms')
          .select()
          .order('started_at', ascending: false);
      return (rows as List<dynamic>)
          .map((e) => AcademicTerm.fromRow(e as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      throw AcademicTermRepositoryException(e.message);
    }
  }

  /// Number of students confirmed as enrolled for [termId].
  Future<int> countConfirmedStudents(String termId) async {
    try {
      final rows = await _client
          .from('student_term_enrollments')
          .select('student_id')
          .eq('term_id', termId);
      return (rows as List<dynamic>).length;
    } on PostgrestException catch (e) {
      throw AcademicTermRepositoryException(e.message);
    }
  }

  Future<TermMigrationResult> startNewTerm({
    required String schoolYear,
    required String term,
    String? startedBy,
  }) async {
    try {
      final result = await _client.rpc('start_new_academic_term', params: {
        'p_school_year': schoolYear,
        'p_term': term,
        'p_started_by': startedBy,
      }) as Map<String, dynamic>;
      final archived = result['archived'] as Map<String, dynamic>? ?? const {};
      return TermMigrationResult(
        archived: {
          for (final e in archived.entries) e.key: (e.value as num).toInt(),
        },
        skipped: [
          for (final s in result['skipped'] as List<dynamic>? ?? const [])
            s.toString(),
        ],
        studentsDeactivated:
            (result['students_deactivated'] as num?)?.toInt() ?? 0,
      );
    } on PostgrestException catch (e) {
      throw AcademicTermRepositoryException(e.message);
    }
  }

  /// Marks [studentIds] as enrolled for the current term and re-activates
  /// their accounts. Returns how many accounts were re-activated.
  Future<int> confirmEnrollment(
    List<String> studentIds, {
    String source = 'registrar',
  }) async {
    if (studentIds.isEmpty) return 0;
    try {
      final n = await _client.rpc('confirm_student_enrollment', params: {
        'p_student_ids': studentIds,
        'p_source': source,
      });
      return (n as num?)?.toInt() ?? 0;
    } on PostgrestException catch (e) {
      throw AcademicTermRepositoryException(e.message);
    }
  }

  /// Permanently deletes closed terms together with the records archived
  /// under them (`term_archive_records` and `student_term_enrollments` go with
  /// the term row, `on delete cascade`). The current term is never touched.
  /// Returns how many terms were deleted.
  Future<int> deleteClosedTerms(List<String> termIds) async {
    if (termIds.isEmpty) return 0;
    try {
      final rows = await _client
          .from('academic_terms')
          .delete()
          .inFilter('id', termIds)
          .eq('is_current', false)
          .select('id');
      return (rows as List<dynamic>).length;
    } on PostgrestException catch (e) {
      throw AcademicTermRepositoryException(e.message);
    }
  }

  /// One page (0-indexed) of the rows archived from [sourceTable] when
  /// [termId] closed, plus how many were archived in total.
  Future<({List<Map<String, dynamic>> rows, int total})> fetchArchiveRows({
    required String termId,
    required String sourceTable,
    int page = 0,
    int pageSize = 25,
  }) async {
    try {
      final from = page * pageSize;
      final response = await _client
          .from('term_archive_records')
          .select('row_data')
          .eq('term_id', termId)
          .eq('source_table', sourceTable)
          .order('archived_at')
          .range(from, from + pageSize - 1)
          .count(CountOption.exact);
      return (
        rows: [
          for (final r in response.data as List<dynamic>)
            Map<String, dynamic>.from(
              (r as Map<String, dynamic>)['row_data'] as Map,
            ),
        ],
        total: response.count,
      );
    } on PostgrestException catch (e) {
      throw AcademicTermRepositoryException(e.message);
    }
  }
}
