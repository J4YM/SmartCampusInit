// packages/student_portal_module/lib/models/referral_request_status.dart

/// What a referral is about — matches student_referrals.concern (see
/// supabase/add_student_referrals.sql).
enum ReferralConcern {
  academic('Academic difficulties'),
  attendance('Attendance'),
  behavior('Behavior'),
  emotional('Emotional / mental well-being'),
  family('Family or home situation'),
  bullying('Bullying'),
  safety('Safety'),
  other('Something else');

  const ReferralConcern(this.label);
  final String label;

  static ReferralConcern fromDb(String? value) => ReferralConcern.values
      .firstWhere((c) => c.name == value, orElse: () => ReferralConcern.other);
}

/// One of the student's own referrals and where it stands — `Pending`,
/// `In_Progress` or `Closed` (student_referrals.status). Deliberately carries
/// nothing about the other student on a referral filed for a classmate.
class ReferralRequestStatus {
  const ReferralRequestStatus({
    required this.id,
    required this.isSelf,
    required this.concern,
    required this.urgency,
    required this.status,
    required this.createdAt,
    this.counselorNote,
  });

  final String id;
  final bool isSelf;
  final ReferralConcern concern;
  final String urgency;
  final String status;
  final DateTime createdAt;
  final String? counselorNote;

  bool get isClosed => status == 'Closed';
  bool get isUrgent => urgency == 'Urgent';

  String get statusLabel => switch (status) {
        'In_Progress' => 'In progress',
        'Closed' => 'Closed',
        _ => 'Pending',
      };
}
