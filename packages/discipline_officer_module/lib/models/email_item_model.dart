/// One row in the header's Email dropdown / full Email list page. No
/// backend exists yet (see `EmailPopover`'s doc comment) — this model has
/// no `fromJson`/`toJson` because there is nothing to (de)serialize
/// against; add them only when a real inbox table/repository lands.
class EmailItemModel {
  const EmailItemModel({
    required this.id,
    required this.from,
    required this.subject,
    required this.body,
    required this.timestamp,
    this.isRead = false,
  });

  final String id;
  final String from;
  final String subject;
  final String body;
  final DateTime timestamp;
  final bool isRead;

  EmailItemModel copyWith({bool? isRead}) {
    return EmailItemModel(
      id: id,
      from: from,
      subject: subject,
      body: body,
      timestamp: timestamp,
      isRead: isRead ?? this.isRead,
    );
  }
}
