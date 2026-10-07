import 'package:discipline_officer_module/discipline_officer_module.dart'
    show EscalationDraft, EscalationReportModel;
import 'package:supabase_flutter/supabase_flutter.dart';

class EscalationRepositoryException implements Exception {
  EscalationRepositoryException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Reads/writes `public.escalation_reports` (supabase/add_escalation_reports.sql):
/// the Student Affairs -> Guidance Counselor approval flow that gates every
/// parent SMS / email about a student's conduct.
class EscalationRepository {
  EscalationRepository(this._client);

  final SupabaseClient _client;

  static const _select = '''
id, student_id, violation_ids, title, summary, message, channels, source,
status, created_by_name, decided_by_name, decided_at, decision_note,
created_at,
students ( student_number, profiles ( first_name, last_name ) )
''';

  /// Newest first. Pass [pendingOnly] for the counselor's approval queue.
  Future<List<EscalationReportModel>> fetchReports({bool pendingOnly = false}) async {
    try {
      var query = _client.from('escalation_reports').select(_select);
      if (pendingOnly) query = query.eq('status', 'Pending_GC');
      final rows = await query.order('created_at', ascending: false);
      return (rows as List<dynamic>)
          .map((e) => _toModel(e as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      throw EscalationRepositoryException(e.message);
    }
  }

  /// Files a report as `Pending_GC`; a database trigger notifies the
  /// Guidance Counselor role.
  Future<void> issue(
    EscalationDraft draft, {
    String? officerId,
    String? officerName,
  }) async {
    try {
      final student = await _client
          .from('students')
          .select('id')
          .eq('student_number', draft.studentNumber)
          .maybeSingle();
      if (student == null) {
        throw EscalationRepositoryException(
            'No student with number ${draft.studentNumber}.');
      }
      await _client.from('escalation_reports').insert({
        'student_id': student['id'],
        'violation_ids': draft.violationIds,
        'summary': draft.summary,
        'message': draft.message,
        'channels': draft.channels,
        'source': 'officer',
        'created_by': officerId,
        'created_by_name': officerName,
      });
    } on PostgrestException catch (e) {
      throw EscalationRepositoryException(e.message);
    }
  }

  /// Guidance Counselor decision. Approving sends the parent notification
  /// (SMS via the existing trigger, email via the outbox); [message]
  /// optionally replaces the officer's draft.
  Future<void> decide(
    String reportId, {
    required bool approve,
    String? note,
    String? message,
    String? actorName,
  }) async {
    try {
      await _client.rpc('decide_escalation_report', params: {
        'p_id': reportId,
        'p_approve': approve,
        'p_note': note,
        'p_message': message,
        'p_actor_name': actorName,
      });
    } on PostgrestException catch (e) {
      throw EscalationRepositoryException(e.message);
    }
  }

  EscalationReportModel _toModel(Map<String, dynamic> row) {
    final student = row['students'] as Map<String, dynamic>?;
    final profile = student?['profiles'] as Map<String, dynamic>?;
    final name =
        '${profile?['first_name'] ?? ''} ${profile?['last_name'] ?? ''}'.trim();
    final decidedAt = row['decided_at'] as String?;
    return EscalationReportModel(
      id: row['id'] as String,
      studentName: name.isEmpty ? 'Unknown student' : name,
      studentNumber: student?['student_number'] as String? ?? '',
      title: row['title'] as String? ?? '',
      summary: row['summary'] as String? ?? '',
      message: row['message'] as String? ?? '',
      channels: ((row['channels'] as List<dynamic>?) ?? const []).cast<String>(),
      source: row['source'] as String? ?? 'officer',
      status: row['status'] as String? ?? 'Pending_GC',
      createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
      violationCount: ((row['violation_ids'] as List<dynamic>?) ?? const []).length,
      createdByName: row['created_by_name'] as String?,
      decidedByName: row['decided_by_name'] as String?,
      decidedAt: decidedAt == null ? null : DateTime.parse(decidedAt).toLocal(),
      decisionNote: row['decision_note'] as String?,
    );
  }
}
