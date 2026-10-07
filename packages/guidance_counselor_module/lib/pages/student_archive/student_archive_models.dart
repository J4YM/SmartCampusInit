/// A student row in the Student Archive tab's searchable list.
class ArchiveStudentModel {
  const ArchiveStudentModel({
    required this.id,
    required this.name,
    required this.studentNumber,
    this.section = '',
  });

  final String id;
  final String name;
  final String studentNumber;
  final String section;
}

/// Categories of a confidential archival log entry
/// (`counseling_archive_logs.log_type`).
enum ArchiveLogType {
  counseling('counseling', 'Counseling session'),
  parentConference('parent_conference', 'Parent conference'),
  intervention('intervention', 'Intervention'),
  referral('referral', 'Referral'),
  other('other', 'Other');

  const ArchiveLogType(this.dbValue, this.label);

  final String dbValue;
  final String label;

  static ArchiveLogType fromDb(String? value) => ArchiveLogType.values
      .firstWhere((t) => t.dbValue == value, orElse: () => ArchiveLogType.other);
}

/// One confidential archival log entry about a student.
class ArchiveLogModel {
  const ArchiveLogModel({
    required this.id,
    required this.type,
    required this.occurredOn,
    required this.title,
    required this.notes,
    this.createdByName,
    this.createdAt,
  });

  final String id;
  final ArchiveLogType type;
  final DateTime occurredOn;
  final String title;
  final String notes;
  final String? createdByName;
  final DateTime? createdAt;
}

/// What the counselor fills in when adding a log.
class ArchiveLogDraft {
  const ArchiveLogDraft({
    required this.type,
    required this.occurredOn,
    required this.title,
    required this.notes,
  });

  final ArchiveLogType type;
  final DateTime occurredOn;
  final String title;
  final String notes;
}
