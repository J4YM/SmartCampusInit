class OfflineStudent {
  const OfflineStudent({
    required this.id,
    required this.rfidUid,
    required this.fullName,
    required this.studentNumber,
    required this.gradeSection,
    this.course,
  });

  /// `students.id`.
  final String id;

  /// `students.rfid_uid`; empty when the student has no card assigned.
  final String rfidUid;
  final String fullName;
  final String studentNumber;
  final String gradeSection;
  final String? course;
}

class OfflineStaff {
  const OfflineStaff({
    required this.id,
    required this.rfidCardId,
    required this.fullName,
    required this.role,
  });

  final String id;
  final String rfidCardId;
  final String fullName;
  final String role;
}

class OfflineOffense {
  const OfflineOffense({required this.id, required this.label, this.category});
  final String id;
  final String label;
  final String? category;
}

class OfflineTeacher {
  const OfflineTeacher({required this.id, required this.fullName});
  final String id;
  final String fullName;
}

class ReferenceData {
  const ReferenceData({
    required this.students,
    required this.staff,
    required this.offenses,
    required this.teachers,
  });

  final List<OfflineStudent> students;
  final List<OfflineStaff> staff;
  final List<OfflineOffense> offenses;
  final List<OfflineTeacher> teachers;
}

/// Everything `submit_admission_slip` needs; stored as JSON in the outbox.
class SlipSubmission {
  const SlipSubmission({
    required this.slipId,
    required this.studentId,
    required this.reportedBy,
    required this.offenseIds,
    this.isEscalated = false,
    this.notes,
    this.professorId,
  });

  final String slipId;
  final String studentId;
  final String reportedBy;
  final List<String> offenseIds;
  final bool isEscalated;
  final String? notes;
  final String? professorId;

  Map<String, dynamic> toJson() => {
        'slipId': slipId,
        'studentId': studentId,
        'reportedBy': reportedBy,
        'offenseIds': offenseIds,
        'isEscalated': isEscalated,
        'notes': notes,
        'professorId': professorId,
      };

  factory SlipSubmission.fromJson(Map<String, dynamic> j) => SlipSubmission(
        slipId: j['slipId'] as String,
        studentId: j['studentId'] as String,
        reportedBy: j['reportedBy'] as String,
        offenseIds: (j['offenseIds'] as List<dynamic>).cast<String>(),
        isEscalated: j['isEscalated'] as bool? ?? false,
        notes: j['notes'] as String?,
        professorId: j['professorId'] as String?,
      );
}

class SyncStatus {
  const SyncStatus({
    required this.online,
    required this.pending,
    required this.rejected,
  });

  final bool online;
  final int pending;
  final int rejected;

  @override
  bool operator ==(Object other) =>
      other is SyncStatus &&
      other.online == online &&
      other.pending == pending &&
      other.rejected == rejected;

  @override
  int get hashCode => Object.hash(online, pending, rejected);
}

/// One outbox row as shown in the kiosk diagnostics dialog.
class OutboxDiagnostic {
  const OutboxDiagnostic({
    required this.id,
    required this.type,
    required this.status,
    required this.attempts,
    required this.createdAt,
    this.lastError,
  });

  final int id;

  /// `'tap'` or `'slip'`.
  final String type;

  /// `'pending'` or `'rejected'`.
  final String status;
  final int attempts;
  final DateTime createdAt;
  final String? lastError;
}

/// One rejected outbox item, reported to the server so IT Technician / Admin
/// can review and dismiss it from their dashboards.
class FailureReport {
  const FailureReport({
    required this.clientKey,
    required this.kind,
    required this.occurredAt,
    required this.reason,
    this.rfidUid,
    this.studentId,
    this.studentName,
    this.payload,
  });

  /// Stable per-item key (see `failureKey`): reporting twice is a no-op, and a
  /// dismissal is matched back to the right local row by it.
  final String clientKey;

  /// `'tap'` or `'slip'`.
  final String kind;

  /// When the tap / report happened on the kiosk.
  final DateTime occurredAt;

  /// The server's refusal message, verbatim.
  final String reason;
  final String? rfidUid;
  final String? studentId;

  /// From the kiosk's cache; null when the card or student is unknown.
  final String? studentName;
  final Map<String, dynamic>? payload;
}
