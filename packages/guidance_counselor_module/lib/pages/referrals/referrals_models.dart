/// A meeting scheduled from a referral (`guidance_meetings.referral_id`, see
/// supabase/add_referral_meetings.sql) and the invitee's answer to it.
class ReferralMeetingModel {
  const ReferralMeetingModel({
    required this.id,
    required this.scheduledAt,
    required this.invitee,
    required this.status,
    this.location,
    this.guidanceNote,
  });

  final String id;
  final DateTime scheduledAt;

  /// `student`, `parent` or `both`.
  final String invitee;

  /// `Proposed`, `Confirmed`, `Declined`, `Reschedule_Requested`, `Completed`,
  /// `Missed` or `Cancelled`.
  final String status;
  final String? location;

  /// Guidance's recommendation when it returned an endorsement meeting.
  final String? guidanceNote;

  /// An endorsement meeting Student Affairs arranged that waits for Guidance
  /// to confirm it before anyone is invited.
  bool get isAwaitingGuidance => status == 'Awaiting_Guidance';

  /// Still waiting to happen: the invitee has not been, and it was not closed.
  bool get isOpen => const {
        'Awaiting_Guidance',
        'Proposed',
        'Confirmed',
        'Declined',
        'Reschedule_Requested',
      }.contains(status);

  bool get isUpcoming => isOpen && scheduledAt.isAfter(DateTime.now());

  String get inviteeLabel => switch (invitee) {
        'student' => 'Student',
        'parent' => 'Parent',
        _ => 'Student & parent',
      };

  String get statusLabel => switch (status) {
        'Awaiting_Guidance' => 'Awaiting your confirmation',
        'Returned' => 'Returned to Student Affairs',
        'Proposed' => 'Awaiting reply',
        'Reschedule_Requested' => 'Reschedule requested',
        _ => status,
      };
}

/// One referral to Guidance (`student_referrals`): a student's own self
/// referral, or an endorsement from Student Affairs that Guidance accepted.
class GuidanceReferralModel {
  const GuidanceReferralModel({
    required this.id,
    required this.studentId,
    required this.studentName,
    required this.studentNumber,
    required this.source,
    required this.concern,
    required this.details,
    required this.urgency,
    required this.status,
    required this.createdAt,
    this.note,
    this.meetings = const [],
  });

  final String id;
  final String studentId;
  final String studentName;
  final String studentNumber;

  /// `self` (the student asked) or `endorsement` (Student Affairs).
  final String source;
  final String concern;
  final String details;
  final String urgency;

  /// `Pending`, `In_Progress` or `Closed`.
  final String status;
  final DateTime createdAt;

  /// The note the student reads on a self referral.
  final String? note;
  final List<ReferralMeetingModel> meetings;

  bool get isEndorsement => source == 'endorsement';
  bool get isUrgent => urgency == 'Urgent';
  bool get isOpen => status != 'Closed';

  /// The next meeting still to happen, soonest first.
  ReferralMeetingModel? get nextMeeting {
    final upcoming = meetings.where((m) => m.isUpcoming).toList()
      ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    return upcoming.isEmpty ? null : upcoming.first;
  }

  String get sourceLabel => isEndorsement ? 'From Student Affairs' : 'Self referral';

  String get concernLabel => switch (concern) {
        'academic' => 'Academic difficulties',
        'emotional' => 'Emotional / mental well-being',
        'family' => 'Family or home situation',
        'attendance' => 'Attendance',
        'behavior' => 'Behavior',
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
