/// One student referral (supabase/add_student_referrals.sql) as the
/// Discipline Officer sees it: who it is about, who filed it, and where it
/// stands. Staff see the referrer; the referred student never does.
class StudentReferralModel {
  const StudentReferralModel({
    required this.id,
    required this.studentName,
    required this.studentNumber,
    required this.referredByName,
    required this.isSelf,
    required this.concern,
    required this.details,
    required this.urgency,
    required this.status,
    required this.createdAt,
    this.counselorNote,
  });

  final String id;
  final String studentName;
  final String studentNumber;
  final String referredByName;
  final bool isSelf;

  /// `student_referrals.concern` key, e.g. `emotional`.
  final String concern;
  final String details;
  final String urgency;

  /// `Pending`, `In_Progress` or `Closed`.
  final String status;
  final DateTime createdAt;

  /// The note the referring student reads on their own dashboard
  /// (`student_referrals.counselor_note`).
  final String? counselorNote;

  bool get isUrgent => urgency == 'Urgent';
  bool get isOpen => status != 'Closed';

  String get concernLabel => switch (concern) {
        'academic' => 'Academic difficulties',
        'attendance' => 'Attendance',
        'behavior' => 'Behavior',
        'emotional' => 'Emotional / mental well-being',
        'family' => 'Family or home situation',
        'bullying' => 'Bullying',
        'safety' => 'Safety',
        _ => 'Other',
      };

  String get statusLabel => switch (status) {
        'In_Progress' => 'In progress',
        'Closed' => 'Closed',
        _ => 'Pending',
      };
}
