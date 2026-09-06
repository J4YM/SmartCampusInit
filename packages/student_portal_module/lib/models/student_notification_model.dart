/// Who sent a message/notification to the student — shown as a small tag on
/// each card so a Student Affairs notice reads differently from a
/// professor's.
enum NotificationSenderRole {
  studentAffairsOffice,
  professor,
  registrar,
  system
}

extension NotificationSenderRoleX on NotificationSenderRole {
  String get label {
    switch (this) {
      case NotificationSenderRole.studentAffairsOffice:
        return 'Student Affairs Office';
      case NotificationSenderRole.professor:
        return 'Professor';
      case NotificationSenderRole.registrar:
        return 'Registrar';
      case NotificationSenderRole.system:
        return 'System';
    }
  }

  static NotificationSenderRole fromDbValue(String value) {
    switch (value) {
      case 'professor':
        return NotificationSenderRole.professor;
      case 'registrar':
        return NotificationSenderRole.registrar;
      case 'system':
        return NotificationSenderRole.system;
      case 'student_affairs_office':
      default:
        return NotificationSenderRole.studentAffairsOffice;
    }
  }
}

/// One row in the student's message/notification feed. Supabase-shaped —
/// maps onto the same `notifications` table every other module reads,
/// scoped to this student's `user_id` with an added `sender_name`/
/// `sender_role` pair so the portal can show who it's from.
class StudentNotificationModel {
  const StudentNotificationModel({
    required this.id,
    required this.senderName,
    required this.senderRole,
    required this.title,
    required this.message,
    required this.timestamp,
    this.isRead = false,
  });

  final String id;
  final String senderName;
  final NotificationSenderRole senderRole;
  final String title;
  final String message;
  final DateTime timestamp;
  final bool isRead;

  factory StudentNotificationModel.fromJson(Map<String, dynamic> json) {
    return StudentNotificationModel(
      id: json['id'] as String,
      senderName: json['sender_name'] as String,
      senderRole:
          NotificationSenderRoleX.fromDbValue(json['sender_role'] as String),
      title: json['title'] as String,
      message: json['message'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      isRead: json['is_read'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sender_name': senderName,
      'sender_role': senderRole.name,
      'title': title,
      'message': message,
      'timestamp': timestamp.toIso8601String(),
      'is_read': isRead,
    };
  }

  StudentNotificationModel copyWith({bool? isRead}) {
    return StudentNotificationModel(
      id: id,
      senderName: senderName,
      senderRole: senderRole,
      title: title,
      message: message,
      timestamp: timestamp,
      isRead: isRead ?? this.isRead,
    );
  }
}
