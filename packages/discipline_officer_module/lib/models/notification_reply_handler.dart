import 'notification_item_model.dart';

/// Answers a technical-issue notification: sends [message] as the signed-in
/// person's reply to the report [item] is about. Throws on failure.
typedef NotificationReplySender = Future<void> Function(
    NotificationItemModel item, String message);

/// The app-wide reply sender every notification popup falls back to.
///
/// A notification's details popup renders through the root navigator's
/// overlay, outside any one dashboard's widget subtree — so the signed-in
/// person's reply behaviour cannot be handed down by an ancestor widget. The
/// host app sets [current] when someone signs in (and clears it on sign-out);
/// the shared bell dropdown and "View all notifications" page then offer Reply
/// on EVERY dashboard that can receive a technical-issue message, with no
/// per-dashboard wiring. A dashboard may still pass its own
/// `onReplyToNotification`, which wins.
abstract final class NotificationReplyHandler {
  static NotificationReplySender? current;
}
