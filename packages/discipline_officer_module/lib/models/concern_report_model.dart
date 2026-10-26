/// One concern report (supabase/add_concern_reports.sql) as Student Affairs
/// sees it: the student who filed it, what it is about and where it stands.
/// [aboutStudentName] is only set on reports migrated from an old classmate
/// referral; the form no longer asks for another student.
class ConcernReportModel {
  const ConcernReportModel({
    required this.id,
    required this.studentName,
    required this.studentNumber,
    required this.concern,
    required this.details,
    required this.urgency,
    required this.status,
    required this.createdAt,
    this.aboutStudentName,
    this.handlerNote,
  });

  final String id;

  /// The student who filed the report.
  final String studentName;
  final String studentNumber;
  final String? aboutStudentName;

  /// `concern_reports.concern` key, e.g. `bullying`.
  final String concern;
  final String details;
  final String urgency;

  /// `Pending`, `In_Progress` or `Closed`.
  final String status;
  final DateTime createdAt;

  /// The note the reporting student reads on their own dashboard
  /// (`concern_reports.handler_note`).
  final String? handlerNote;

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
