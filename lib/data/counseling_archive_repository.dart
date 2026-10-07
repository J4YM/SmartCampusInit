import 'package:guidance_counselor_module/pages/student_archive/student_archive_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CounselingArchiveException implements Exception {
  CounselingArchiveException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Reads/writes `public.counseling_archive_logs`
/// (supabase/add_counseling_archive_logs.sql) — the Guidance Counselor's
/// confidential per-student archival logs. Access is enforced by row-level
/// security, not just by this app; see that file for who can read/write.
class CounselingArchiveRepository {
  CounselingArchiveRepository(this._client);

  final SupabaseClient _client;

  /// Up to [limit] students, filtered by name or student number. Filtering
  /// is client-side because PostgREST can't OR across the embedded
  /// `profiles` row; fine at this school's roster size.
  Future<List<ArchiveStudentModel>> searchStudents(
    String query, {
    int limit = 40,
  }) async {
    try {
      final rows = await _client
          .from('students')
          .select('id, student_number, profiles ( first_name, last_name ), sections ( name )')
          .order('student_number')
          .limit(1000);
      final needle = query.trim().toLowerCase();
      final result = <ArchiveStudentModel>[];
      for (final raw in rows as List<dynamic>) {
        final row = raw as Map<String, dynamic>;
        final profile = row['profiles'] as Map<String, dynamic>?;
        final name =
            '${profile?['first_name'] ?? ''} ${profile?['last_name'] ?? ''}'.trim();
        final number = row['student_number'] as String? ?? '';
        if (needle.isNotEmpty &&
            !name.toLowerCase().contains(needle) &&
            !number.toLowerCase().contains(needle)) {
          continue;
        }
        result.add(ArchiveStudentModel(
          id: row['id'] as String,
          name: name.isEmpty ? number : name,
          studentNumber: number,
          section: (row['sections'] as Map<String, dynamic>?)?['name'] as String? ?? '',
        ));
        if (result.length >= limit) break;
      }
      return result;
    } on PostgrestException catch (e) {
      throw CounselingArchiveException(e.message);
    }
  }

  Future<List<ArchiveLogModel>> fetchLogs(String studentId) async {
    try {
      final rows = await _client
          .from('counseling_archive_logs')
          .select('id, log_type, occurred_on, title, notes, created_by_name, created_at')
          .eq('student_id', studentId)
          .order('occurred_on', ascending: false)
          .order('created_at', ascending: false);
      return (rows as List<dynamic>).map((raw) {
        final r = raw as Map<String, dynamic>;
        return ArchiveLogModel(
          id: r['id'] as String,
          type: ArchiveLogType.fromDb(r['log_type'] as String?),
          occurredOn: DateTime.parse(r['occurred_on'] as String),
          title: r['title'] as String? ?? '',
          notes: r['notes'] as String? ?? '',
          createdByName: r['created_by_name'] as String?,
          createdAt: DateTime.tryParse(r['created_at'] as String? ?? '')?.toLocal(),
        );
      }).toList();
    } on PostgrestException catch (e) {
      throw CounselingArchiveException(e.message);
    }
  }

  Future<void> addLog({
    required String studentId,
    required ArchiveLogDraft draft,
    String? counselorId,
    String? counselorName,
  }) async {
    try {
      final d = draft.occurredOn;
      await _client.from('counseling_archive_logs').insert({
        'student_id': studentId,
        'log_type': draft.type.dbValue,
        'occurred_on':
            '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
        'title': draft.title,
        'notes': draft.notes,
        'created_by': counselorId,
        'created_by_name': counselorName,
      });
    } on PostgrestException catch (e) {
      throw CounselingArchiveException(e.message);
    }
  }

  Future<void> deleteLog(String logId) async {
    try {
      await _client.from('counseling_archive_logs').delete().eq('id', logId);
    } on PostgrestException catch (e) {
      throw CounselingArchiveException(e.message);
    }
  }
}
