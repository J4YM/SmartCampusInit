/// What happened to a concern after the officer acted on it
/// (`concern_case_file` in supabase/add_concern_investigations.sql): the
/// endorsement(s) to Guidance with their meetings, and the investigation's
/// findings and sanction once there is one.
class ConcernCaseFile {
  const ConcernCaseFile({this.endorsements = const [], this.investigation});

  final List<CaseEndorsement> endorsements;
  final CaseInvestigation? investigation;

  bool get isEmpty => endorsements.isEmpty && investigation == null;

  factory ConcernCaseFile.fromJson(Map<String, dynamic> json) => ConcernCaseFile(
        endorsements: [
          for (final e in (json['endorsements'] as List<dynamic>? ?? const []))
            CaseEndorsement.fromJson(e as Map<String, dynamic>),
        ],
        investigation: json['investigation'] == null
            ? null
            : CaseInvestigation.fromJson(
                json['investigation'] as Map<String, dynamic>),
      );
}

class CaseEndorsement {
  const CaseEndorsement({
    required this.id,
    required this.status,
    this.decisionNote,
    this.summary,
    this.decidedAt,
    this.meetings = const [],
  });

  final String id;

  /// `Pending_GC`, `Approved` or `Rejected`.
  final String status;
  final String? decisionNote;
  final String? summary;
  final DateTime? decidedAt;
  final List<CaseMeeting> meetings;

  factory CaseEndorsement.fromJson(Map<String, dynamic> json) => CaseEndorsement(
        id: json['id'] as String,
        status: json['status'] as String? ?? 'Pending_GC',
        decisionNote: json['decision_note'] as String?,
        summary: json['summary'] as String?,
        decidedAt: _time(json['decided_at']),
        meetings: [
          for (final m in (json['meetings'] as List<dynamic>? ?? const []))
            CaseMeeting.fromJson(m as Map<String, dynamic>),
        ],
      );
}

class CaseMeeting {
  const CaseMeeting({
    required this.id,
    required this.scheduledAt,
    required this.status,
    this.responseNote,
    this.guidanceNote,
    this.location,
  });

  final String id;
  final DateTime scheduledAt;
  final String status;
  final String? responseNote;

  /// Guidance's recommendation when it returned the meeting to Student Affairs.
  final String? guidanceNote;
  final String? location;

  factory CaseMeeting.fromJson(Map<String, dynamic> json) => CaseMeeting(
        id: json['id'] as String,
        scheduledAt: DateTime.parse(json['scheduled_at'] as String).toLocal(),
        status: json['status'] as String? ?? '',
        responseNote: json['response_note'] as String?,
        guidanceNote: json['guidance_note'] as String?,
        location: json['location'] as String?,
      );
}

class CaseInvestigation {
  const CaseInvestigation({
    required this.id,
    required this.status,
    this.outcome,
    this.findings,
    this.recommendation,
    this.completedAt,
    this.sanctionType,
    this.sanctionDescription,
  });

  final String id;

  /// `Open` or `Complete`.
  final String status;

  /// `Proven` or `Not_Proven` once the investigation is complete.
  final String? outcome;
  final String? findings;
  final String? recommendation;
  final DateTime? completedAt;
  final String? sanctionType;
  final String? sanctionDescription;

  factory CaseInvestigation.fromJson(Map<String, dynamic> json) {
    final sanction = json['sanction'] as Map<String, dynamic>?;
    return CaseInvestigation(
      id: json['id'] as String,
      status: json['status'] as String? ?? 'Open',
      outcome: json['outcome'] as String?,
      findings: json['findings'] as String?,
      recommendation: json['recommendation'] as String?,
      completedAt: _time(json['completed_at']),
      sanctionType: sanction?['type'] as String?,
      sanctionDescription: sanction?['description'] as String?,
    );
  }
}

DateTime? _time(Object? v) =>
    v is String ? DateTime.parse(v).toLocal() : null;
