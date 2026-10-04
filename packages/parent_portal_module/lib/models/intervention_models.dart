import 'package:flutter/material.dart';

/// What an intervention message is about — drives its icon and tint.
enum InterventionKind { attendance, academic, conduct, wellbeing, general }

extension InterventionKindX on InterventionKind {
  String get label {
    switch (this) {
      case InterventionKind.attendance:
        return 'Attendance';
      case InterventionKind.academic:
        return 'Academic';
      case InterventionKind.conduct:
        return 'Conduct';
      case InterventionKind.wellbeing:
        return 'Well-being';
      case InterventionKind.general:
        return 'General';
    }
  }

  IconData get icon {
    switch (this) {
      case InterventionKind.attendance:
        return Icons.event_busy_rounded;
      case InterventionKind.academic:
        return Icons.menu_book_rounded;
      case InterventionKind.conduct:
        return Icons.gavel_rounded;
      case InterventionKind.wellbeing:
        return Icons.favorite_border_rounded;
      case InterventionKind.general:
        return Icons.campaign_outlined;
    }
  }

  static InterventionKind fromDbValue(String? value) {
    switch ((value ?? '').toLowerCase()) {
      case 'attendance':
        return InterventionKind.attendance;
      case 'academic':
        return InterventionKind.academic;
      case 'conduct':
        return InterventionKind.conduct;
      case 'wellbeing':
      case 'well-being':
        return InterventionKind.wellbeing;
      default:
        return InterventionKind.general;
    }
  }
}

/// A message from the school about an intervention for the parent's child —
/// e.g. a Guidance Counselor asking for a conference after repeated
/// absences. Backed by `parent_interventions` (see
/// supabase/add_parent_interventions_schema.sql).
class InterventionMessageModel {
  const InterventionMessageModel({
    required this.id,
    required this.title,
    required this.message,
    required this.sentBy,
    required this.createdAt,
    this.kind = InterventionKind.general,
    this.actionRequired = false,
    this.isRead = false,
  });

  final String id;
  final String title;
  final String message;

  /// Who sent it, e.g. "Guidance Counselor — Ms. Reyes".
  final String sentBy;
  final DateTime createdAt;
  final InterventionKind kind;

  /// The school is asking the parent to do something (reply, attend a
  /// meeting, …) rather than just informing them.
  final bool actionRequired;
  final bool isRead;

  InterventionMessageModel copyWith({bool? isRead}) => InterventionMessageModel(
        id: id,
        title: title,
        message: message,
        sentBy: sentBy,
        createdAt: createdAt,
        kind: kind,
        actionRequired: actionRequired,
        isRead: isRead ?? this.isRead,
      );

  factory InterventionMessageModel.fromJson(Map<String, dynamic> json) {
    return InterventionMessageModel(
      id: json['id'] as String,
      title: json['title'] as String,
      message: json['message'] as String? ?? '',
      sentBy: json['sent_by'] as String? ?? 'School',
      createdAt: DateTime.parse(json['created_at'] as String),
      kind: InterventionKindX.fromDbValue(json['kind'] as String?),
      actionRequired: json['action_required'] as bool? ?? false,
      isRead: json['read_at'] != null,
    );
  }
}
