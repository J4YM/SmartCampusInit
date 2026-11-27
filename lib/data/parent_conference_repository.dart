import 'package:supabase_flutter/supabase_flutter.dart';

import '../documents/parent_conference_report_pdf.dart';

/// Loads what the Parent Conference Report prints for one meeting.
class ParentConferenceRepository {
  ParentConferenceRepository(this._client);

  final SupabaseClient _client;

  Future<ParentConferenceData> fetch(String meetingId) async {
    Map<String, dynamic> row;
    try {
      row = await _row(meetingId, withConfirmation: true);
    } on PostgrestException {
      // parent_attended / summary not migrated yet
      // (supabase/add_defense_revisions.sql): print without them.
      row = await _row(meetingId, withConfirmation: false);
    }

    final student = row['students'] as Map<String, dynamic>?;
    final profile = student?['profiles'] as Map<String, dynamic>?;
    final section = student?['sections'] as Map<String, dynamic>?;
    final name = [
      (profile?['first_name'] as String? ?? '').trim(),
      (profile?['last_name'] as String? ?? '').trim(),
    ].where((p) => p.isNotEmpty).join(' ');

    return ParentConferenceData(
      studentName: name.isEmpty ? 'Student' : name,
      studentNumber: student?['student_number'] as String? ?? '',
      section: section?['name'] as String? ?? '',
      scheduledAt: DateTime.parse(row['scheduled_at'] as String).toLocal(),
      location: row['location'] as String?,
      invitee: row['invitee'] as String? ?? 'parent',
      status: row['status'] as String? ?? 'Proposed',
      parentAttended: row['parent_attended'] as bool?,
      summary: row['summary'] as String?,
    );
  }

  Future<Map<String, dynamic>> _row(
    String meetingId, {
    required bool withConfirmation,
  }) {
    return _client
        .from('guidance_meetings')
        .select('scheduled_at, location, invitee, status, '
            '${withConfirmation ? 'parent_attended, summary, ' : ''}'
            'students ( student_number, profiles ( first_name, last_name ), '
            'sections ( name ) )')
        .eq('id', meetingId)
        .single();
  }
}
