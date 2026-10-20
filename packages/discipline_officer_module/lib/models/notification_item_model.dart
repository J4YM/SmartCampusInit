/// One row in the header's Notifications dropdown. Supabase-ready.
class NotificationItemModel {
  const NotificationItemModel({
    required this.id,
    required this.title,
    required this.message,
    required this.timestamp,
    this.isRead = false,
    this.reportId,
    this.isUrgent = false,
  });

  final String id;
  final String title;
  final String message;
  final DateTime timestamp;
  final bool isRead;

  /// Needs attention now (`notifications.urgent`), e.g. a violation report that
  /// expired after 72 weekday hours. Raises an on-screen alert as well as the
  /// sound.
  final bool isUrgent;

  /// The technical issue report this notification is about — set on messages
  /// that came out of a technical issue (a reply from IT, a new report for
  /// IT), null on every other notification. It is what lets the details popup
  /// offer a Reply.
  final String? reportId;

  /// The titles the technical-issue flow gives its notifications (see
  /// `add_technical_issue_comment` / `report_technical_issue`).
  static const technicalIssueTitles = {
    'Update on your technical issue report', // IT answered the reporter
    'New reply on a technical issue report', // the reporter answered IT
    'New technical issue reported', // a new report, to IT
  };

  /// True for a message that came out of a technical issue — the ones that
  /// can be replied to. Recognised by its [reportId] when the notification
  /// carries one, and by its title for messages from before that link
  /// existed (the report is then looked up when the reply is sent).
  bool get isTechnicalIssue =>
      reportId != null || technicalIssueTitles.contains(title);

  factory NotificationItemModel.fromJson(Map<String, dynamic> json) {
    return NotificationItemModel(
      id: json['id'] as String,
      title: json['title'] as String,
      message: json['message'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      isRead: json['is_read'] as bool? ?? false,
      reportId: json['report_id'] as String?,
      isUrgent: json['urgent'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'message': message,
      'timestamp': timestamp.toIso8601String(),
      'is_read': isRead,
      if (reportId != null) 'report_id': reportId,
      if (isUrgent) 'urgent': true,
    };
  }

  NotificationItemModel copyWith({bool? isRead}) {
    return NotificationItemModel(
      id: id,
      title: title,
      message: message,
      timestamp: timestamp,
      isRead: isRead ?? this.isRead,
      reportId: reportId,
      isUrgent: isUrgent,
    );
  }
}
