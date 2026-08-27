// ---------------------------------------------------------------------------
// Data models — Supabase (`discipline_cases`) ready.
// fromJson()/toJson() map directly onto snake_case Postgres columns so rows
// can be streamed straight into these models once the backend is wired up.
// ---------------------------------------------------------------------------

class DisciplineSummaryMetricsModel {
  const DisciplineSummaryMetricsModel({
    this.pendingQueueCount = 0,
    this.escalatedCount = 0,
    this.processedTodayCount = 0,
    this.avgResponseTimeMinutes = 0.0,
  });

  final int pendingQueueCount;
  final int escalatedCount;
  final int processedTodayCount;
  final double avgResponseTimeMinutes;

  factory DisciplineSummaryMetricsModel.fromJson(Map<String, dynamic> json) {
    return DisciplineSummaryMetricsModel(
      pendingQueueCount: json['pending_queue_count'] as int? ?? 0,
      escalatedCount: json['escalated_count'] as int? ?? 0,
      processedTodayCount: json['processed_today_count'] as int? ?? 0,
      avgResponseTimeMinutes:
          (json['avg_response_time_minutes'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'pending_queue_count': pendingQueueCount,
      'escalated_count': escalatedCount,
      'processed_today_count': processedTodayCount,
      'avg_response_time_minutes': avgResponseTimeMinutes,
    };
  }
}

class DisciplineCaseModel {
  const DisciplineCaseModel({
    required this.id,
    required this.studentName,
    required this.studentNumber,
    required this.programGradeSection,
    required this.violationType,
    this.isEscalated = false,
    this.slaRemaining,
    required this.submittedBy,
    required this.submitterRole,
    required this.incidentDateTime,
    this.priorViolationsCount = 0,
    required this.description,
    this.offenseId,
    this.penaltyImposed,
    this.archivedAt,
    this.admissionSlipId,
  });

  final String id;
  final String studentName;
  final String studentNumber;
  final String programGradeSection;
  final String violationType;
  final bool isEscalated;

  /// Countdown label as supplied by the backend, e.g. `"02:20"`. `null` means
  /// no SLA deadline is attached to this case.
  final String? slaRemaining;
  final String submittedBy;

  /// Role of whoever filed the case, e.g. "Faculty Member", "Security
  /// Personnel" — shown alongside [submittedBy] in the case detail panel.
  final String submitterRole;
  final DateTime incidentDateTime;
  final int priorViolationsCount;
  final String description;

  /// `student_violations.offense_id` — which `handbook_offenses` row this
  /// case is filed under. `null` for mock/demo cases with no backing row.
  /// Modify uses this (via a dropdown of offense options) to actually
  /// change the offense, since there's no free-text violation-type column
  /// to edit directly.
  final String? offenseId;

  /// `student_violations.penalty_imposed` — free-text penalty/notes entered
  /// by the officer for this specific case (distinct from
  /// `handbook_offenses.penalty_info`, the offense's standard penalty).
  final String? penaltyImposed;

  /// `student_violations.archived_at` — set when an officer "deletes" this
  /// report from [ViolationPreviewPanel]. Archived cases drop out of the
  /// active queue immediately and are permanently deleted 7 days after this
  /// timestamp (see `DisciplineRepository.fetchArchivedViolations`). `null`
  /// for an active (non-archived) case.
  final DateTime? archivedAt;

  /// `student_violations.admission_slip_id` — links this case to the other
  /// violations filed in the same kiosk submission, if any. `null` for
  /// cases not tied to an admission slip (e.g. a faculty Conduct Report).
  /// Used to group multiple violations from one submission into a single
  /// ticket in [ValidationQueueCard]; each case still carries its own
  /// independent status/actions.
  final String? admissionSlipId;

  DisciplineCaseModel copyWith({
    String? violationType,
    String? submitterRole,
    String? description,
    bool? isEscalated,
    String? offenseId,
    String? penaltyImposed,
    int? priorViolationsCount,
  }) {
    return DisciplineCaseModel(
      id: id,
      studentName: studentName,
      studentNumber: studentNumber,
      programGradeSection: programGradeSection,
      violationType: violationType ?? this.violationType,
      isEscalated: isEscalated ?? this.isEscalated,
      slaRemaining: slaRemaining,
      submittedBy: submittedBy,
      submitterRole: submitterRole ?? this.submitterRole,
      incidentDateTime: incidentDateTime,
      priorViolationsCount: priorViolationsCount ?? this.priorViolationsCount,
      description: description ?? this.description,
      offenseId: offenseId ?? this.offenseId,
      penaltyImposed: penaltyImposed ?? this.penaltyImposed,
      admissionSlipId: admissionSlipId,
    );
  }

  factory DisciplineCaseModel.fromJson(Map<String, dynamic> json) {
    return DisciplineCaseModel(
      id: json['id'] as String,
      studentName: json['student_name'] as String,
      studentNumber: json['student_number'] as String,
      programGradeSection: json['program_grade_section'] as String,
      violationType: json['violation_type'] as String,
      isEscalated: json['is_escalated'] as bool? ?? false,
      slaRemaining: json['sla_remaining'] as String?,
      submittedBy: json['submitted_by'] as String,
      submitterRole: json['submitted_by_role'] as String? ?? '',
      incidentDateTime: DateTime.parse(json['incident_datetime'] as String),
      priorViolationsCount: json['prior_violations_count'] as int? ?? 0,
      description: json['description'] as String? ?? '',
      offenseId: json['offense_id'] as String?,
      penaltyImposed: json['penalty_imposed'] as String?,
      archivedAt: json['archived_at'] == null
          ? null
          : DateTime.parse(json['archived_at'] as String),
      admissionSlipId: json['admission_slip_id'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'student_name': studentName,
      'student_number': studentNumber,
      'program_grade_section': programGradeSection,
      'violation_type': violationType,
      'is_escalated': isEscalated,
      'sla_remaining': slaRemaining,
      'submitted_by': submittedBy,
      'submitted_by_role': submitterRole,
      'incident_datetime': incidentDateTime.toIso8601String(),
      'prior_violations_count': priorViolationsCount,
      'description': description,
      'offense_id': offenseId,
      'penalty_imposed': penaltyImposed,
      'archived_at': archivedAt?.toIso8601String(),
      'admission_slip_id': admissionSlipId,
    };
  }
}
