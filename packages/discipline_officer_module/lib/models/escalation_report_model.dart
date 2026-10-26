/// What an endorsement asks Guidance for
/// (`escalation_reports.kind`, supabase/add_endorsements.sql).
enum EndorsementKind {
  counseling('counseling', 'Counseling'),
  parentIntervention('parent_intervention', 'Parent intervention'),
  both('both', 'Counseling and parent intervention');

  const EndorsementKind(this.dbValue, this.label);

  final String dbValue;
  final String label;

  /// The parent is messaged (SMS / email) once Guidance approves.
  bool get notifiesParent => this != counseling;

  /// Rows from before endorsements existed have no kind: they were parent
  /// interventions.
  static EndorsementKind fromDb(String? value) => values.firstWhere(
        (k) => k.dbValue == value,
        orElse: () => EndorsementKind.parentIntervention,
      );
}

/// One row of `escalation_reports` (supabase/add_escalation_reports.sql), shown
/// as an endorsement: Student Affairs asking the Guidance Associate to step in
/// for a student, awaiting / carrying Guidance's decision. It is not tied to a
/// violation ([violationCount] may be 0).
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
    this.kind = EndorsementKind.parentIntervention,
    this.concernId,
    this.studentId,
  });

  final String id;
  final String studentName;
  final String studentNumber;
  final String title;

  /// The officer's internal report to the counselor.
  final String summary;

  /// What the parent receives (the counselor may edit it on approval). Empty
  /// for a counseling-only endorsement.
  final String message;

  /// `sms` and/or `email`; empty for a counseling-only endorsement.
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
  final EndorsementKind kind;

  /// The student concern this endorsement came from, if any.
  final String? concernId;

  /// `students.id`, used to read the student's violation history.
  final String? studentId;

  bool get isPending => status == 'Pending_GC';
  bool get isApproved => status == 'Approved';
  bool get isAuto => source == 'auto';

  String get statusLabel => switch (status) {
        'Approved' => 'Approved',
        'Rejected' => 'Declined',
        _ => 'Awaiting Guidance',
      };

  String get channelsLabel => channels.isEmpty
      ? 'No parent message'
      : channels.map((c) => c == 'sms' ? 'SMS' : 'Email').join(' + ');
}

/// What the Discipline Officer fills in when endorsing a student.
class EscalationDraft {
  const EscalationDraft({
    required this.studentNumber,
    required this.violationIds,
    required this.summary,
    required this.message,
    required this.channels,
    this.kind = EndorsementKind.parentIntervention,
    this.concernId,
  });

  final String studentNumber;

  /// Empty when the endorsement is not about any violation.
  final List<String> violationIds;
  final String summary;

  /// Ignored unless [kind] notifies the parent.
  final String message;
  final List<String> channels;
  final EndorsementKind kind;

  /// Set when the endorsement answers a student concern.
  final String? concernId;
}

/// One line of an endorsed student's violation history: what, when and where
/// it stands. Never a sanction, override reason or finding.
class EndorsedViolation {
  const EndorsedViolation({
    required this.id,
    required this.offense,
    required this.status,
    this.category,
    this.incidentAt,
  });

  final String id;
  final String offense;
  final String status;
  final String? category;
  final DateTime? incidentAt;
}
