import 'package:discipline_officer_module/discipline_officer_module.dart'
    show
        EndorsedViolation,
        EndorsementKind,
        EndorsementMeetingModel,
        EscalationDraft,
        EscalationReportModel;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models/parent_availability_round.dart';

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
created_at, kind, concern_id, other_description, exclude_parent,
guidance_meetings ( id, scheduled_at, location, invitee, status, guidance_note ),
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
        'kind': draft.kind.dbValue,
        if (draft.otherDescription != null)
          'other_description': draft.otherDescription,
        'exclude_parent': draft.excludeParent,
        if (draft.concernId != null) 'concern_id': draft.concernId,
      });
    } on PostgrestException catch (e) {
      throw EscalationRepositoryException(e.message);
    }
  }

  /// An endorsed student's violations (offense, date, status only). Empty for a
  /// student nobody endorsed or for a caller who may not look.
  Future<List<EndorsedViolation>> fetchViolationHistory(
      String studentId) async {
    try {
      final rows = await _client.rpc('endorsement_violation_history',
          params: {'p_student_id': studentId});
      return [
        for (final raw in rows as List<dynamic>)
          _toViolation(raw as Map<String, dynamic>),
      ];
    } on PostgrestException catch (e) {
      throw EscalationRepositoryException(e.message);
    }
  }

  EndorsedViolation _toViolation(Map<String, dynamic> row) {
    final at = row['incident_at'] as String?;
    return EndorsedViolation(
      id: row['violation_id'] as String,
      offense: row['offense'] as String? ?? 'Unspecified offense',
      category: row['category'] as String?,
      status: row['status'] as String? ?? '',
      incidentAt: at == null ? null : DateTime.parse(at).toLocal(),
    );
  }

  /// Guidance Counselor decision. Approving sends the parent notification
  /// (SMS via the existing trigger, email via the outbox); [message]
  /// optionally replaces the officer's draft. A meeting is arranged afterwards
  /// by the Discipline Officer and confirmed by Guidance
  /// (supabase/add_endorsement_meetings.sql).
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

  /// The Discipline Officer arranges a meeting for an endorsement Guidance
  /// accepted ([invitee] is `student`, `parent` or `both`). It waits for
  /// Guidance to confirm before anyone is invited
  /// (supabase/add_endorsement_meetings.sql).
  Future<void> proposeMeeting({
    required String endorsementId,
    required DateTime scheduledAt,
    required String invitee,
    String? location,
  }) async {
    try {
      await _client.rpc('propose_endorsement_meeting', params: {
        'p_escalation_id': endorsementId,
        'p_scheduled_at': scheduledAt.toUtc().toIso8601String(),
        'p_location': location,
        'p_invitee': invitee,
      });
    } on PostgrestException catch (e) {
      throw EscalationRepositoryException(e.message);
    }
  }

  static const _roundSelect = '''
id, escalation_report_id, student_id, round_no, status, requested_at,
offered_at, meeting_id,
meeting_availability_slots ( id, slot_at, status )
''';

  /// Asks the parent for the times they are free; returns the new round id
  /// (supabase/add_parent_availability_scheduling.sql).
  Future<String> requestParentAvailability(String reportId) async {
    try {
      final id = await _client
          .rpc('request_parent_availability', params: {'p_report_id': reportId});
      return id as String;
    } on PostgrestException catch (e) {
      throw EscalationRepositoryException(e.message);
    }
  }

  /// Cancels a request that is still waiting on the parent or on Guidance.
  Future<void> cancelParentAvailability(String roundId) async {
    try {
      await _client
          .rpc('cancel_parent_availability', params: {'p_round_id': roundId});
    } on PostgrestException catch (e) {
      throw EscalationRepositoryException(e.message);
    }
  }

  /// Availability rounds (with their slots) for the given endorsements,
  /// newest first.
  Future<List<ParentAvailabilityRound>> fetchAvailabilityRounds(
      List<String> reportIds) async {
    if (reportIds.isEmpty) return const [];
    try {
      final rows = await _client
          .from('meeting_availability_rounds')
          .select(_roundSelect)
          .inFilter('escalation_report_id', reportIds)
          .order('requested_at', ascending: false);
      return [
        for (final r in rows as List<dynamic>)
          ParentAvailabilityRound.fromJson(r as Map<String, dynamic>),
      ];
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
      kind: EndorsementKind.fromDb(row['kind'] as String?),
      concernId: row['concern_id'] as String?,
      studentId: row['student_id'] as String?,
      otherDescription: row['other_description'] as String?,
      excludeParent: row['exclude_parent'] as bool? ?? false,
      meetings: [
        for (final m in (row['guidance_meetings'] as List<dynamic>? ?? const []))
          EndorsementMeetingModel(
            id: (m as Map<String, dynamic>)['id'] as String,
            scheduledAt: DateTime.parse(m['scheduled_at'] as String).toLocal(),
            location: m['location'] as String?,
            invitee: m['invitee'] as String? ?? 'both',
            status: m['status'] as String? ?? 'Proposed',
            guidanceNote: m['guidance_note'] as String?,
          ),
      ],
    );
  }
}
