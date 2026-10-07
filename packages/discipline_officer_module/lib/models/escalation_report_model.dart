/// One row of `escalation_reports` (supabase/add_escalation_reports.sql): a
/// Student Affairs escalation of a student's violations to the parent,
/// awaiting / carrying the Guidance Counselor's decision.
class EscalationReportModel {
  const EscalationReportModel({
    required this.id,
    required this.studentName,
    required this.studentNumber,
    required this.title,
    required this.summary,
    required this.message,
    required this.channels,
    required this.source,
    required this.status,
    required this.createdAt,
    this.violationCount = 0,
    this.createdByName,
    this.decidedByName,
    this.decidedAt,
    this.decisionNote,
  });

  final String id;
  final String studentName;
  final String studentNumber;
  final String title;

  /// The officer's internal report to the counselor.
  final String summary;

  /// What the parent receives (the counselor may edit it on approval).
  final String message;

  /// `sms` and/or `email`.
  final List<String> channels;

  /// `officer` or `auto` (the automatic 3-violations / major-offense flag).
  final String source;

  /// `Pending_GC`, `Approved` or `Rejected`.
  final String status;
  final DateTime createdAt;
  final int violationCount;
  final String? createdByName;
  final String? decidedByName;
  final DateTime? decidedAt;
  final String? decisionNote;

  bool get isPending => status == 'Pending_GC';
  bool get isApproved => status == 'Approved';
  bool get isAuto => source == 'auto';

  String get statusLabel => switch (status) {
        'Approved' => 'Approved',
        'Rejected' => 'Rejected',
        _ => 'Awaiting Guidance',
      };

  String get channelsLabel =>
      channels.map((c) => c == 'sms' ? 'SMS' : 'Email').join(' + ');
}

/// What the Discipline Officer fills in when issuing an escalation report.
class EscalationDraft {
  const EscalationDraft({
    required this.studentNumber,
    required this.violationIds,
    required this.summary,
    required this.message,
    required this.channels,
  });

  final String studentNumber;
  final List<String> violationIds;
  final String summary;
  final String message;
  final List<String> channels;
}
