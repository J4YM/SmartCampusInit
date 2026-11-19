import 'package:discipline_officer_module/discipline_officer_module.dart'
    show ConcernCaseFile, ConcernReportModel;
import 'package:supabase_flutter/supabase_flutter.dart';

class ConcernReportsException implements Exception {
  ConcernReportsException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Reads and updates `public.concern_reports`
/// (supabase/add_concern_reports.sql) for the Discipline Officer's Concerns
/// tab. Students create concern reports through the `submit_concern_report`
/// RPC (see StudentPortalRepository), never here.
class ConcernReportsRepository {
  ConcernReportsRepository(this._client);

  final SupabaseClient _client;

  static const _select = '''
id, student_id, about_student_id, concern, details, urgency, status,
handler_note, created_at, violation_id,
students!concern_reports_student_id_fkey ( student_number, profiles ( first_name, last_name ) ),
about:students!concern_reports_about_student_id_fkey ( student_number, profiles ( first_name, last_name ) )
''';

  /// Newest first; the tab does its own open/urgent ordering.
  Future<List<ConcernReportModel>> fetchAll() async {
    final rows = await _client
        .from('concern_reports')
        .select(_select)
        .order('created_at', ascending: false);
    return (rows as List<dynamic>)
        .map((e) => _toModel(e as Map<String, dynamic>))
        .toList();
  }

  /// Starts an investigation about [studentId] from the concern (the officer
  /// names the student; the reporter's form never does). Records the incident
  /// quietly and returns the investigation id. See
  /// supabase/add_concern_investigations.sql.
  Future<String> sendToInvestigation({
    required String concernId,
    required String studentId,
    required String offenseId,
    required String description,
    required DateTime occurredAt,
    String? location,
    bool notifyParent = false,
  }) async {
    try {
      final id = await _client.rpc('send_concern_to_investigation', params: {
        'p_concern_id': concernId,
        'p_student_id': studentId,
        'p_offense_id': offenseId,
        'p_description': description,
        'p_occurred_at': occurredAt.toUtc().toIso8601String(),
        'p_location': location,
        'p_notify_parent': notifyParent,
      });
      return id as String;
    } on PostgrestException catch (e) {
      throw ConcernReportsException(e.message);
    }
  }

  /// What came back for a concern: endorsement meetings and the investigation's
  /// findings.
  Future<ConcernCaseFile> fetchCaseFile(String concernId) async {
    try {
      final raw = await _client
          .rpc('concern_case_file', params: {'p_concern_id': concernId});
      return ConcernCaseFile.fromJson(raw as Map<String, dynamic>);
    } on PostgrestException catch (e) {
      throw ConcernReportsException(e.message);
    }
  }

  Future<void> update(
    String concernId, {
    required String status,
    String? note,
    String? actorId,
  }) async {
    await _client.from('concern_reports').update({
      'status': status,
      'handler_note': (note ?? '').trim().isEmpty ? null : note!.trim(),
      if (actorId != null) 'handled_by': actorId,
      'handled_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', concernId);
  }

  ConcernReportModel _toModel(Map<String, dynamic> row) {
    String fullName(Map<String, dynamic>? p) =>
        '${p?['first_name'] ?? ''} ${p?['last_name'] ?? ''}'.trim();

    final student = row['students'] as Map<String, dynamic>?;
    final studentName =
        fullName(student?['profiles'] as Map<String, dynamic>?);
    final about = row['about'] as Map<String, dynamic>?;
    final aboutName = fullName(about?['profiles'] as Map<String, dynamic>?);

    return ConcernReportModel(
      id: row['id'] as String,
      studentName: studentName.isEmpty ? 'Unknown student' : studentName,
      studentNumber: student?['student_number'] as String? ?? '',
      aboutStudentName: aboutName.isEmpty ? null : aboutName,
      aboutStudentNumber: about?['student_number'] as String?,
      concern: row['concern'] as String? ?? 'other',
      details: row['details'] as String? ?? '',
      urgency: row['urgency'] as String? ?? 'Normal',
      status: row['status'] as String? ?? 'Pending',
      handlerNote: row['handler_note'] as String?,
      violationId: row['violation_id'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
    );
  }
}
