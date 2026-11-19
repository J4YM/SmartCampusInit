import 'package:supabase_flutter/supabase_flutter.dart';

import 'models/parent_availability_round.dart';

class GuidanceInvestigationException implements Exception {
  GuidanceInvestigationException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// `guidance_meetings.invitee`.
enum MeetingInvitee {
  student('student'),
  parent('parent'),
  both('both');

  const MeetingInvitee(this.value);
  final String value;

  static MeetingInvitee parse(String? v) => MeetingInvitee.values
      .firstWhere((e) => e.value == v, orElse: () => MeetingInvitee.both);
}

/// `guidance_meetings.status`.
enum MeetingStatus {
  proposed('Proposed'),
  confirmed('Confirmed'),
  declined('Declined'),
  rescheduleRequested('Reschedule_Requested'),
  completed('Completed'),
  missed('Missed'),
  cancelled('Cancelled');

  const MeetingStatus(this.value);
  final String value;

  static MeetingStatus parse(String? v) => MeetingStatus.values
      .firstWhere((e) => e.value == v, orElse: () => MeetingStatus.proposed);
}

class GuidanceMeeting {
  const GuidanceMeeting({
    required this.id,
    required this.investigationId,
    required this.studentId,
    required this.scheduledAt,
    required this.invitee,
    required this.status,
    this.location,
    this.responseNote,
    this.respondedAt,
  });

  final String id;
  /// Null for a meeting scheduled while approving an escalation report.
  final String? investigationId;
  final String studentId;
  final DateTime scheduledAt;
  final MeetingInvitee invitee;
  final MeetingStatus status;
  final String? location;
  final String? responseNote;
  final DateTime? respondedAt;

  /// Newly proposed, in the future, and nobody has answered yet.
  bool get isAwaitingResponse =>
      status == MeetingStatus.proposed && scheduledAt.isAfter(DateTime.now());

  /// The invitee may still confirm or decline (matches `respond_to_meeting`).
  bool get canRespond =>
      scheduledAt.isAfter(DateTime.now()) &&
      (status == MeetingStatus.proposed ||
          status == MeetingStatus.confirmed ||
          status == MeetingStatus.declined ||
          status == MeetingStatus.rescheduleRequested);

  factory GuidanceMeeting.fromRow(Map<String, dynamic> row) => GuidanceMeeting(
        id: row['id'] as String,
        investigationId: row['investigation_id'] as String?,
        studentId: row['student_id'] as String,
        scheduledAt: DateTime.parse(row['scheduled_at'] as String).toLocal(),
        invitee: MeetingInvitee.parse(row['invitee'] as String?),
        status: MeetingStatus.parse(row['status'] as String?),
        location: row['location'] as String?,
        responseNote: row['response_note'] as String?,
        respondedAt: row['responded_at'] == null
            ? null
            : DateTime.parse(row['responded_at'] as String).toLocal(),
      );
}

class GuidanceInvestigation {
  const GuidanceInvestigation({
    required this.id,
    required this.violationId,
    required this.studentId,
    required this.studentName,
    required this.studentNumber,
    required this.section,
    required this.status,
    required this.createdAt,
    required this.offenseDescription,
    required this.incidentNotes,
    required this.evidencePaths,
    required this.meetings,
    this.offenseCategory,
    this.incidentAt,
    this.findings,
    this.recommendation,
    this.outcome,
    this.sanctioned = false,
  });

  final String id;
  final String violationId;
  final String studentId;
  final String studentName;
  final String studentNumber;
  final String section;

  /// `Open` or `Complete`.
  final String status;
  final DateTime createdAt;
  final String offenseDescription;
  final String? offenseCategory;
  final String incidentNotes;
  final DateTime? incidentAt;
  final List<String> evidencePaths;
  final List<GuidanceMeeting> meetings;
  final String? findings;
  final String? recommendation;

  /// `Proven` or `Not_Proven`; null until the investigation is completed.
  final String? outcome;

  /// A sanction exists for the violation (`sanctions.violation_id` is unique,
  /// so it embeds as one object; a list is accepted too).
  final bool sanctioned;

  static bool _hasSanction(Object? embedded) =>
      embedded is List ? embedded.isNotEmpty : embedded != null;

  bool get isOpen => status == 'Open';

  factory GuidanceInvestigation.fromRow(Map<String, dynamic> row) {
    final student = row['students'] as Map<String, dynamic>?;
    final profile = student?['profiles'] as Map<String, dynamic>?;
    final violation = row['student_violations'] as Map<String, dynamic>?;
    final offense = violation?['handbook_offenses'] as Map<String, dynamic>?;
    final name =
        '${profile?['first_name'] ?? ''} ${profile?['last_name'] ?? ''}'.trim();
    final meetings = [
      for (final m in (row['guidance_meetings'] as List<dynamic>? ?? const []))
        GuidanceMeeting.fromRow(m as Map<String, dynamic>),
    ]..sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt));
    return GuidanceInvestigation(
      id: row['id'] as String,
      violationId: row['violation_id'] as String,
      studentId: row['student_id'] as String,
      studentName: name.isEmpty ? 'Unknown student' : name,
      studentNumber: student?['student_number'] as String? ?? '',
      section: (student?['sections'] as Map<String, dynamic>?)?['name'] as String? ?? '',
      status: row['status'] as String? ?? 'Open',
      createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
      offenseDescription:
          offense?['description'] as String? ?? 'Unspecified offense',
      offenseCategory: offense?['category'] as String?,
      incidentNotes: violation?['incident_notes'] as String? ?? '',
      incidentAt: violation?['incident_at'] == null
          ? null
          : DateTime.parse(violation!['incident_at'] as String).toLocal(),
      evidencePaths: [
        for (final e in (violation?['violation_evidence'] as List<dynamic>? ?? const []))
          (e as Map<String, dynamic>)['storage_path'] as String,
      ],
      meetings: meetings,
      findings: row['findings'] as String?,
      recommendation: row['recommendation'] as String?,
      outcome: row['outcome'] as String?,
      sanctioned: _hasSanction(violation?['sanctions']),
    );
  }
}

class GuidanceInvestigationRepository {
  GuidanceInvestigationRepository(this._client);

  final SupabaseClient _client;

  static const _investigationSelect = '''
id, violation_id, student_id, status, findings, recommendation, outcome, created_at,
students ( student_number, profiles ( first_name, last_name ), sections ( name ) ),
student_violations ( incident_notes, incident_at,
  handbook_offenses ( description, category ),
  violation_evidence ( storage_path ), sanctions ( id ) ),
guidance_meetings ( id, investigation_id, student_id, scheduled_at, location,
  invitee, status, response_note, responded_at )
''';

  /// Investigations visible to the signed-in counselor (RLS), open first.
  Future<List<GuidanceInvestigation>> fetchAssigned() async {
    try {
      final rows = await _client
          .from('guidance_investigations')
          .select(_investigationSelect)
          .order('created_at', ascending: false);
      final list = [
        for (final r in rows as List<dynamic>)
          GuidanceInvestigation.fromRow(r as Map<String, dynamic>),
      ];
      list.sort((a, b) {
        if (a.isOpen != b.isOpen) return a.isOpen ? -1 : 1;
        return b.createdAt.compareTo(a.createdAt);
      });
      return list;
    } on PostgrestException catch (e) {
      throw GuidanceInvestigationException(e.message);
    }
  }

  /// Meetings a student (or their linked parent) is invited to; RLS limits
  /// the rows to the signed-in user's own.
  Future<List<GuidanceMeeting>> fetchMeetingsForStudent(String studentId) async {
    try {
      final rows = await _client
          .from('guidance_meetings')
          .select()
          .eq('student_id', studentId)
          .order('scheduled_at', ascending: false);
      return [
        for (final r in rows as List<dynamic>)
          GuidanceMeeting.fromRow(r as Map<String, dynamic>),
      ];
    } on PostgrestException catch (e) {
      throw GuidanceInvestigationException(e.message);
    }
  }

  Future<void> schedule({
    required String investigationId,
    required DateTime scheduledAt,
    required MeetingInvitee invitee,
    String? location,
  }) =>
      _rpc('schedule_guidance_meeting', {
        'p_investigation_id': investigationId,
        'p_scheduled_at': scheduledAt.toUtc().toIso8601String(),
        'p_location': location,
        'p_invitee': invitee.value,
      });

  /// [parentId] identifies a credential parent, who has no Supabase Auth
  /// session (see supabase/add_parent_credential_access.sql). Left out for
  /// everyone else, whose session already says who they are.
  Future<void> respond(
    String meetingId, {
    required bool accept,
    String? note,
    String? parentId,
  }) =>
      _rpc('respond_to_meeting', {
        'p_meeting_id': meetingId,
        'p_accept': accept,
        'p_note': note,
        if (parentId != null) 'p_parent_id': parentId,
      });

  Future<void> setOutcome(String meetingId, MeetingStatus status) =>
      _rpc('set_meeting_outcome', {
        'p_meeting_id': meetingId,
        'p_status': status.value,
      });

  /// [outcome] is `Proven` or `Not_Proven`
  /// (supabase/add_investigation_outcome.sql).
  Future<void> complete({
    required String investigationId,
    required String findings,
    required String outcome,
    String? recommendation,
  }) =>
      _rpc('complete_investigation', {
        'p_investigation_id': investigationId,
        'p_findings': findings,
        'p_outcome': outcome,
        'p_recommendation': recommendation,
      });

  /// Changes the verdict of a completed investigation while no sanction has
  /// been recorded. (`setOutcome` is the meeting outcome, so this is named
  /// apart.)
  Future<void> setInvestigationOutcome(String investigationId, String outcome) =>
      _rpc('set_investigation_outcome', {
        'p_investigation_id': investigationId,
        'p_outcome': outcome,
      });

  /// The signed-in parent's availability requests still waiting on them
  /// (RLS limits rows to their own children).
  Future<List<ParentAvailabilityRound>> fetchMyOpenRounds() async {
    try {
      final rows = await _client
          .from('meeting_availability_rounds')
          .select('''
id, escalation_report_id, student_id, round_no, status, requested_at,
offered_at, meeting_id,
meeting_availability_slots ( id, slot_at, status )
''')
          .eq('status', 'Open')
          .order('requested_at', ascending: false);
      return [
        for (final r in rows as List<dynamic>)
          ParentAvailabilityRound.fromJson(r as Map<String, dynamic>),
      ];
    } on PostgrestException catch (e) {
      throw GuidanceInvestigationException(e.message);
    }
  }

  /// The parent offers the times they are free (minute precision, sent as
  /// UTC).
  ///
  /// [parentId] identifies a credential parent (no Supabase Auth session); see
  /// supabase/add_parent_credential_access.sql.
  Future<void> submitParentAvailability(
    String roundId,
    List<DateTime> slots, {
    String? parentId,
  }) =>
      _rpc('submit_parent_availability', {
        'p_round_id': roundId,
        'p_slots': [for (final s in slots) s.toUtc().toIso8601String()],
        if (parentId != null) 'p_parent_id': parentId,
      });

  Future<void> _rpc(String fn, Map<String, dynamic> params) async {
    try {
      await _client.rpc(fn, params: params);
    } on PostgrestException catch (e) {
      throw GuidanceInvestigationException(e.message);
    }
  }
}
