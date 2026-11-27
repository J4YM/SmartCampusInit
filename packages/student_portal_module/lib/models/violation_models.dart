import 'package:flutter/material.dart';

import '../theme/student_portal_colors.dart';
import 'sanction_history_entry.dart';

/// Mirrors `handbook_offenses.category` collapsed to the two tiers the
/// student portal shows (the staff-side Discipline Officer module further
/// splits "Major" into A/B/C/D sub-tiers internally).
enum ViolationCategory { minor, major }

extension ViolationCategoryX on ViolationCategory {
  String get label => this == ViolationCategory.minor ? 'Minor' : 'Major';

  Color foreground(BuildContext context) => this == ViolationCategory.minor
      ? StudentPortalColors.minorFg(context)
      : StudentPortalColors.majorFg(context);

  Color background(BuildContext context) => this == ViolationCategory.minor
      ? StudentPortalColors.minorBg(context)
      : StudentPortalColors.majorBg(context);

  static ViolationCategory fromDbValue(String value) {
    return value.toLowerCase().startsWith('major')
        ? ViolationCategory.major
        : ViolationCategory.minor;
  }
}

/// Mirrors `student_violations.status` — whether the Discipline Officer has
/// finished logging this case (`Recorded`) or it's still being reviewed
/// (`Pending`).
enum ViolationStatus { recorded, pending }

extension ViolationStatusX on ViolationStatus {
  String get label => this == ViolationStatus.recorded ? 'Recorded' : 'Pending';

  Color foreground(BuildContext context) => this == ViolationStatus.recorded
      ? StudentPortalColors.recordedFg(context)
      : StudentPortalColors.pendingFg(context);

  Color background(BuildContext context) => this == ViolationStatus.recorded
      ? StudentPortalColors.recordedBg(context)
      : StudentPortalColors.pendingBg(context);

  IconData get icon => this == ViolationStatus.recorded
      ? Icons.fact_check_rounded
      : Icons.hourglass_top_rounded;

  static ViolationStatus fromDbValue(String value) {
    // 'Under_Investigation' and 'Investigation_Complete' (findings filed,
    // not yet sanctioned) are actively-open cases, same as 'Pending' — only
    // 'Resolved' (sanctioned) is actually closed/recorded.
    final v = value.toLowerCase();
    return (v == 'pending' ||
            v == 'under_investigation' ||
            v == 'investigation_complete')
        ? ViolationStatus.pending
        : ViolationStatus.recorded;
  }
}

/// One row from `student_violations`, reduced to what the student portal
/// needs to display.
class StudentViolationModel {
  const StudentViolationModel({
    required this.id,
    required this.title,
    required this.category,
    required this.status,
    required this.dateFiled,
    required this.description,
    required this.recordedBy,
    this.offenseNumber = 1,
    this.behaviorCategory,
    this.sanction,
  });

  /// 1st / 2nd / 3rd... offense within this violation's Minor-or-Major group,
  /// counted over the student's non-archived violations by date filed.
  final int offenseNumber;

  /// e.g. "Uniform / Dress Code" (null when the violation is unclassified).
  final String? behaviorCategory;

  /// The sanction that closed this violation (null while it is still open).
  final SanctionHistoryEntry? sanction;

  /// "1st Offense", "2nd Offense", "3rd Offense", "4th Offense"...
  String get offenseLabel => '${ordinal(offenseNumber)} Offense';

  static String ordinal(int n) {
    final mod100 = n % 100;
    if (mod100 >= 11 && mod100 <= 13) return '${n}th';
    switch (n % 10) {
      case 1:
        return '${n}st';
      case 2:
        return '${n}nd';
      case 3:
        return '${n}rd';
      default:
        return '${n}th';
    }
  }

  StudentViolationModel copyWith({
    int? offenseNumber,
    SanctionHistoryEntry? sanction,
  }) {
    return StudentViolationModel(
      id: id,
      title: title,
      category: category,
      status: status,
      dateFiled: dateFiled,
      description: description,
      recordedBy: recordedBy,
      offenseNumber: offenseNumber ?? this.offenseNumber,
      behaviorCategory: behaviorCategory,
      sanction: sanction ?? this.sanction,
    );
  }

  /// Numbers each violation within its Minor / Major group, oldest first.
  static List<StudentViolationModel> withOffenseNumbers(
    List<StudentViolationModel> violations,
  ) {
    final oldestFirst = [...violations]
      ..sort((a, b) => a.dateFiled.compareTo(b.dateFiled));
    final counts = <ViolationCategory, int>{};
    final numbers = <String, int>{};
    for (final v in oldestFirst) {
      final next = (counts[v.category] ?? 0) + 1;
      counts[v.category] = next;
      numbers[v.id] = next;
    }
    return [for (final v in violations) v.copyWith(offenseNumber: numbers[v.id])];
  }

  final String id;
  final String title;
  final ViolationCategory category;
  final ViolationStatus status;
  final DateTime dateFiled;
  final String description;

  /// Who filed/is handling this case, e.g. "Student Affairs & Services".
  final String recordedBy;

  factory StudentViolationModel.fromJson(Map<String, dynamic> json) {
    return StudentViolationModel(
      id: json['id'] as String,
      title: json['title'] as String,
      category: ViolationCategoryX.fromDbValue(json['category'] as String),
      status: ViolationStatusX.fromDbValue(json['status'] as String),
      dateFiled: DateTime.parse(json['date_filed'] as String),
      description: json['description'] as String? ?? '',
      recordedBy: json['recorded_by'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'category': category.name,
      'status': status.name,
      'date_filed': dateFiled.toIso8601String(),
      'description': description,
      'recorded_by': recordedBy,
    };
  }
}

/// Display label for a `behavior_category` value, e.g.
/// `Uniform_Dress_Code` -> "Uniform / Dress Code".
String behaviorCategoryLabel(String value) {
  switch (value) {
    case 'Academic_Integrity':
      return 'Academic Integrity';
    case 'Attendance_Tardiness':
      return 'Attendance / Tardiness';
    case 'Uniform_Dress_Code':
      return 'Uniform / Dress Code';
    case 'Property_Damage':
      return 'Property / Facility Damage';
    case 'Disruptive_Conduct':
      return 'Behavioral / Disruptive Conduct';
    case 'Digital_Device_Policy':
      return 'Digital / Device Policy';
    default:
      return 'Other';
  }
}
