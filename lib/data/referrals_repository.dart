import 'package:guidance_counselor_module/pages/referrals/referrals_view.dart'
    show StudentReferralModel;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Reads and updates `public.student_referrals`
/// (supabase/add_student_referrals.sql) for the Guidance Counselor's
/// Referrals tab. Students create referrals through the
/// `submit_student_referral` RPC (see StudentPortalRepository), never here.
class ReferralsRepository {
  ReferralsRepository(this._client);

  final SupabaseClient _client;

  static const _select = '''
id, student_id, is_self, concern, details, urgency, status, counselor_note,
created_at,
students!student_referrals_student_id_fkey ( student_number, profiles ( first_name, last_name ) ),
referrer:profiles!student_referrals_referred_by_fkey ( first_name, last_name )
''';

  /// Newest first; the tab does its own open/urgent ordering.
  Future<List<StudentReferralModel>> fetchAll() async {
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

  StudentReferralModel _toModel(Map<String, dynamic> row) {
    String fullName(Map<String, dynamic>? p) =>
        '${p?['first_name'] ?? ''} ${p?['last_name'] ?? ''}'.trim();

    final student = row['students'] as Map<String, dynamic>?;
    final studentName =
        fullName(student?['profiles'] as Map<String, dynamic>?);
    final referrerName = fullName(row['referrer'] as Map<String, dynamic>?);

    return StudentReferralModel(
      id: row['id'] as String,
      studentName: studentName.isEmpty ? 'Unknown student' : studentName,
      studentNumber: student?['student_number'] as String? ?? '',
      referredByName: referrerName.isEmpty ? 'Unknown student' : referrerName,
      isSelf: row['is_self'] as bool? ?? true,
      concern: row['concern'] as String? ?? 'other',
      details: row['details'] as String? ?? '',
      urgency: row['urgency'] as String? ?? 'Normal',
      status: row['status'] as String? ?? 'Pending',
      counselorNote: row['counselor_note'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
    );
  }
}
