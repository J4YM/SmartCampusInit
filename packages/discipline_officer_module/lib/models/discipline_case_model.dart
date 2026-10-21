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

/// One thing done on a case — who did it and when (`violation_actions`).
class ViolationActionEntry {
  const ViolationActionEntry({
    required this.action,
    required this.actorName,
    required this.at,
    this.actorRole,
    this.detail,
  });

  /// e.g. "Report filed", "Classified", "Sanction recorded: Warning".
  final String action;
  final String actorName;

  /// The actor's role value (`Discipline_Officer`, `Teacher`, …); null for the
  /// system (the expiry job).
  final String? actorRole;
  final DateTime at;
  final String? detail;

  /// "Discipline Officer", "Teacher", … ("" for the system).
  String get actorRoleLabel => (actorRole ?? '').replaceAll('_', ' ');
}

/// Where a violation case is in the Discipline Officer workflow.
enum CaseStage {
  /// Filed by a professor/security; the DO has not picked an offense yet.
  reported,

  /// Offense chosen; awaiting the DO's path: auto-record, escalate or sanction.
  classified,

  /// With the guidance counselor (`Under_Investigation`).
  withGuidance,

  /// Counselor filed findings; ready for the DO's sanction.
  investigationComplete,

  /// A sanction is recorded; the case is closed (`Resolved`).
  sanctioned,
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
    this.professorName,
    required this.incidentDateTime,
    this.priorViolationsCount = 0,
    required this.description,
    this.offenseId,
    this.penaltyImposed,
    this.archivedAt,
    this.expiredAt,
    this.admissionSlipId,
    this.offenseCategory,
    this.status,
    this.professorDecision,
    this.professorDecisionNote,
    this.professorFiled = false,
    this.isClassified = true,
    this.suggestedEscalation = false,
    this.evidencePaths = const [],
    this.filedAt,
    this.handbookPenalty,
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

  /// The professor/adviser the student picked on the kiosk self-report
  /// (`student_violations.professor_id`). `null` when none was chosen. The
  /// reporter of a kiosk report is always the fixed kiosk system profile, so
  /// without this the report never says which professor it concerns.
  final String? professorName;
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
  /// active queue immediately and stay in the archive until the officer
  /// restores, validates or permanently deletes them (see
  /// `DisciplineRepository.fetchArchivedViolations`). `null` for an active
  /// (non-archived) case.
  final DateTime? archivedAt;

  /// `student_violations.expired_at` — set when the 72-hour rule auto-archived
  /// this report while it was still open (see add_violation_72h_expiry.sql).
  /// `null` for a report that was archived manually.
  final DateTime? expiredAt;

  /// `student_violations.admission_slip_id` — links this case to the other
  /// violations filed in the same kiosk submission, if any. `null` for
  /// cases not tied to an admission slip (e.g. a faculty Conduct Report).
  /// Used to group multiple violations from one submission into a single
  /// ticket in [ValidationQueueCard]; each case still carries its own
  /// independent status/actions.
  final String? admissionSlipId;

  /// `handbook_offenses.category` (e.g. "Minor", "Major_A") — the severity
  /// bucket the Violation Queue's Minor/Major filter reads. `null` for
  /// mock/demo cases, which fall back to the "Minor –"/"Major –" prefix
  /// baked into [violationType].
  final String? offenseCategory;

  /// `student_violations.status` — `Pending`, `Under_Investigation` or
  /// `Resolved`. Backs the Students Violation History tab's Status column;
  /// `null` for mock/demo cases, which read as pending.
  final String? status;

  /// `student_violations.professor_decision` — `Confirmed` or `Denied` once
  /// the professor named on a kiosk self-report has answered, `null` while
  /// they haven't (or when no professor is named). Advisory only: it never
  /// changes [status] or the 72-hour expiry; the officer still decides.
  final String? professorDecision;

  /// The professor's optional note with their decision.
  final String? professorDecisionNote;

  /// True when the named professor filed the report themselves
  /// (`reported_by == professor_id`), which counts as implicitly confirmed
  /// and can't be decided on.
  final bool professorFiled;

  /// False while `student_violations.offense_id` is null: a professor/security
  /// report the DO has not classified yet. Mock/demo cases default to true.
  final bool isClassified;

  /// An automatic rule (3+ minors, sensitive wording, major offense) suggests
  /// escalating this case. Only a badge; the DO decides.
  final bool suggestedEscalation;

  /// Storage paths (bucket `violation-evidence`) of the reporter's photos.
  final List<String> evidencePaths;

  /// When the report was filed (`created_at`); [incidentDateTime] is when it
  /// actually happened.
  final DateTime? filedAt;

  /// `handbook_offenses.penalty_info` for the classified offense: the handbook's
  /// standard penalty, offered as the default sanction text.
  final String? handbookPenalty;

  CaseStage get stage {
    switch (status) {
      case 'Resolved':
        return CaseStage.sanctioned;
      case 'Investigation_Complete':
        return CaseStage.investigationComplete;
      case 'Under_Investigation':
        return CaseStage.withGuidance;
    }
    return isClassified ? CaseStage.classified : CaseStage.reported;
  }

  /// The DO may record a sanction right now.
  bool get canSanction =>
      stage == CaseStage.classified || stage == CaseStage.investigationComplete;

  /// The case is with Guidance: sanctioning needs a written override reason.
  bool get canOverrideSanction => stage == CaseStage.withGuidance;

  /// Passed 72 weekday hours unactioned (flagged, still in the active queue).
  ///
  /// Only a case still waiting on the officer expires (`Pending`, or a legacy
  /// row with no status): once escalated or sanctioned the marker is gone,
  /// matching expire_stale_violations().
  bool get isExpired =>
      expiredAt != null &&
      archivedAt == null &&
      (status == null || status == 'Pending');

  DisciplineCaseModel copyWith({
    String? violationType,
    String? submitterRole,
    String? description,
    bool? isEscalated,
    String? offenseId,
    String? penaltyImposed,
    int? priorViolationsCount,
    String? offenseCategory,
    String? status,
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
      professorName: professorName,
      incidentDateTime: incidentDateTime,
      priorViolationsCount: priorViolationsCount ?? this.priorViolationsCount,
      description: description ?? this.description,
      offenseId: offenseId ?? this.offenseId,
      penaltyImposed: penaltyImposed ?? this.penaltyImposed,
      admissionSlipId: admissionSlipId,
      offenseCategory: offenseCategory ?? this.offenseCategory,
      status: status ?? this.status,
      archivedAt: archivedAt,
      expiredAt: expiredAt,
      professorDecision: professorDecision,
      professorDecisionNote: professorDecisionNote,
      professorFiled: professorFiled,
      isClassified: (offenseId ?? this.offenseId) != null || isClassified,
      suggestedEscalation: suggestedEscalation,
      evidencePaths: evidencePaths,
      filedAt: filedAt,
      handbookPenalty: handbookPenalty,
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
      professorName: json['professor_name'] as String?,
      incidentDateTime: DateTime.parse(json['incident_datetime'] as String),
      priorViolationsCount: json['prior_violations_count'] as int? ?? 0,
      description: json['description'] as String? ?? '',
      offenseId: json['offense_id'] as String?,
      penaltyImposed: json['penalty_imposed'] as String?,
      archivedAt: json['archived_at'] == null
          ? null
          : DateTime.parse(json['archived_at'] as String),
      expiredAt: json['expired_at'] == null
          ? null
          : DateTime.parse(json['expired_at'] as String),
      admissionSlipId: json['admission_slip_id'] as String?,
      offenseCategory: json['offense_category'] as String?,
      status: json['status'] as String?,
      professorDecision: json['professor_decision'] as String?,
      professorDecisionNote: json['professor_decision_note'] as String?,
      professorFiled: json['professor_filed'] as bool? ?? false,
      isClassified: json['is_classified'] as bool? ?? true,
      suggestedEscalation: json['suggested_escalation'] as bool? ?? false,
      evidencePaths:
          (json['evidence_paths'] as List<dynamic>?)?.cast<String>() ?? const [],
      filedAt: json['filed_at'] == null
          ? null
          : DateTime.parse(json['filed_at'] as String),
      handbookPenalty: json['handbook_penalty'] as String?,
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
      'professor_name': professorName,
      'incident_datetime': incidentDateTime.toIso8601String(),
      'prior_violations_count': priorViolationsCount,
      'description': description,
      'offense_id': offenseId,
      'penalty_imposed': penaltyImposed,
      'archived_at': archivedAt?.toIso8601String(),
      'expired_at': expiredAt?.toIso8601String(),
      'admission_slip_id': admissionSlipId,
      'offense_category': offenseCategory,
      'status': status,
      'professor_decision': professorDecision,
      'professor_decision_note': professorDecisionNote,
      'professor_filed': professorFiled,
      'is_classified': isClassified,
      'suggested_escalation': suggestedEscalation,
      'evidence_paths': evidencePaths,
      'filed_at': filedAt?.toIso8601String(),
      'handbook_penalty': handbookPenalty,
    };
  }
}
