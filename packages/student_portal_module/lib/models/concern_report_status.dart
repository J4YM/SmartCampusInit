// packages/student_portal_module/lib/models/concern_report_status.dart

/// What a concern report is about — matches concern_reports.concern (see
/// supabase/add_concern_reports.sql).
enum ConcernType {
  attendance('Attendance'),
  behavior('Behavior'),
  bullying('Bullying'),
  safety('Safety'),
  academic('Academic difficulties'),
  other('Something else');

  const ConcernType(this.label);
  final String label;

  static ConcernType fromDb(String? value) => ConcernType.values
      .firstWhere((c) => c.name == value, orElse: () => ConcernType.other);
}

/// One of the student's own concern reports to Student Affairs and where it
/// stands — `Pending`, `In_Progress` or `Closed` (concern_reports.status).
class ConcernReportStatus {
  const ConcernReportStatus({
    required this.id,
    required this.concern,
    required this.urgency,
    required this.status,
    required this.createdAt,
    this.handlerNote,
  });

  final String id;
  final ConcernType concern;
  final String urgency;
  final String status;
  final DateTime createdAt;
  final String? handlerNote;

  bool get isClosed => status == 'Closed';
  bool get isUrgent => urgency == 'Urgent';

  String get statusLabel => switch (status) {
        'In_Progress' => 'In progress',
        'Closed' => 'Closed',
        _ => 'Pending',
      };
}
