import 'package:guidance_counselor_module/pages/referrals/referrals_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Reads and updates `public.student_referrals`
/// (supabase/add_guidance_referrals.sql) for the Guidance Associate's
/// Referrals tab, and schedules meetings from them
/// (supabase/add_referral_meetings.sql). Students create self referrals
/// through the `submit_student_referral` RPC (see StudentPortalRepository);
/// an approved endorsement becomes a referral in the database.
class ReferralsRepository {
  ReferralsRepository(this._client);

  final SupabaseClient _client;

  static const _select = '''
id, student_id, source, concern, details, urgency, status, counselor_note,
created_at,
students!student_referrals_student_id_fkey ( student_number, profiles ( first_name, last_name ) ),
guidance_meetings ( id, scheduled_at, location, invitee, status, guidance_note ),
escalation_reports!student_referrals_endorsement_id_fkey (
  guidance_meetings ( id, scheduled_at, location, invitee, status, guidance_note )
)
''';

  /// Newest first; the tab does its own open/urgent ordering.
  Future<List<GuidanceReferralModel>> fetchAll() async {
    final rows = await _client
        .from('student_referrals')
        .select(_select)
        .order('created_at', ascending: false);
    return (rows as List<dynamic>)
        .map((e) => _toModel(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> update(
    String referralId, {
    required String status,
    String? note,
    String? actorId,
  }) async {
    await _client.from('student_referrals').update({
      'status': status,
      'counselor_note': (note ?? '').trim().isEmpty ? null : note!.trim(),
      if (actorId != null) 'handled_by': actorId,
      'handled_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', referralId);
  }

  /// Invites the student, the parent or both (`student`, `parent`, `both`).
  /// Only a parent invitee gets the SMS.
  Future<void> scheduleMeeting({
    required String referralId,
    required DateTime scheduledAt,
    required String invitee,
    String? location,
  }) async {
    await _client.rpc('schedule_referral_meeting', params: {
      'p_referral_id': referralId,
      'p_scheduled_at': scheduledAt.toUtc().toIso8601String(),
      'p_location': location,
      'p_invitee': invitee,
    });
  }

  Future<void> setMeetingOutcome(String meetingId, String status) async {
    await _client.rpc('set_meeting_outcome',
        params: {'p_meeting_id': meetingId, 'p_status': status});
  }

  /// Confirms a meeting Student Affairs arranged for an endorsement; the
  /// invitees are told then. Pass [scheduledAt] / [location] only when
  /// Guidance changed them (supabase/add_endorsement_meetings.sql).
  Future<void> confirmMeeting(
    String meetingId, {
    DateTime? scheduledAt,
    String? location,
  }) async {
    await _client.rpc('confirm_endorsement_meeting', params: {
      'p_meeting_id': meetingId,
      'p_scheduled_at': scheduledAt?.toUtc().toIso8601String(),
      'p_location': location,
    });
  }

  /// Sends an endorsement meeting back to Student Affairs with a
  /// recommendation; nobody is invited.
  Future<void> returnMeeting(String meetingId, String note) async {
    await _client.rpc('return_endorsement_meeting',
        params: {'p_meeting_id': meetingId, 'p_note': note});
  }

  GuidanceReferralModel _toModel(Map<String, dynamic> row) {
    final student = row['students'] as Map<String, dynamic>?;
    final profile = student?['profiles'] as Map<String, dynamic>?;
    final name =
        '${profile?['first_name'] ?? ''} ${profile?['last_name'] ?? ''}'.trim();

    return GuidanceReferralModel(
      id: row['id'] as String,
      studentId: row['student_id'] as String? ?? '',
      studentName: name.isEmpty ? 'Unknown student' : name,
      studentNumber: student?['student_number'] as String? ?? '',
      source: row['source'] as String? ?? 'self',
      concern: row['concern'] as String? ?? 'other',
      details: row['details'] as String? ?? '',
      urgency: row['urgency'] as String? ?? 'Normal',
      status: row['status'] as String? ?? 'Pending',
      note: row['counselor_note'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
      meetings: [
        ..._meetings(row['guidance_meetings']),
        // An endorsement referral's meetings hang off the endorsement.
        ..._meetings(
            (row['escalation_reports'] as Map<String, dynamic>?)?['guidance_meetings']),
      ],
    );
  }

  List<ReferralMeetingModel> _meetings(Object? raw) => [
        for (final m in (raw as List<dynamic>? ?? const []))
          ReferralMeetingModel(
            id: (m as Map<String, dynamic>)['id'] as String,
            scheduledAt: DateTime.parse(m['scheduled_at'] as String).toLocal(),
            location: m['location'] as String?,
            invitee: m['invitee'] as String? ?? 'both',
            status: m['status'] as String? ?? 'Proposed',
            guidanceNote: m['guidance_note'] as String?,
          ),
      ];
}
