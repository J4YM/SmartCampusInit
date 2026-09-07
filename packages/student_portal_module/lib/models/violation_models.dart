import 'package:flutter/material.dart';

import '../theme/student_portal_colors.dart';

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
    return value.toLowerCase() == 'pending'
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
  });

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
