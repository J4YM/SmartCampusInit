import 'package:discipline_officer_module/discipline_officer_module.dart'
    show NotificationItemModel;

/// Notices when a notification NEW to the signed-in person arrives and rings
/// [onNew] — the one place every dashboard's bell shares, so each sent
/// notification makes its sound whichever dashboard is open.
///
/// Fed by the notifications repository on every read (the initial load, the
/// realtime push and the poll alike). Per person (role + user id) it
/// remembers the ids it has already seen:
///
///  - the first read after sign-in only seeds that set — opening the app to
///    twenty old unread notifications does not ring twenty times;
///  - after that, an unread notification whose id has not been seen rings
///    once, however many arrive together;
///  - a notification that was already read elsewhere never rings.
abstract final class NotificationAlert {
  /// What to do when something new arrived. The app points it at the sound;
  /// null (the default, and in tests) rings nothing.
  static void Function()? onNew;

  static final Map<String, Set<String>> _seen = {};

  /// Looks at [items], this person's current notifications. Returns true when
  /// at least one was new (and [onNew] was called).
  static bool observe(String personKey, List<NotificationItemModel> items) {
    final previous = _seen[personKey];
    _seen[personKey] = {...?previous, for (final n in items) n.id};
    if (previous == null) return false; // first read: just remember them

    final hasNew =
        items.any((n) => !n.isRead && !previous.contains(n.id));
    if (hasNew) onNew?.call();
    return hasNew;
  }

  /// Forgets everyone — on sign-out, so the next sign-in starts with a quiet
  /// first read instead of ringing for what arrived while signed out.
  static void reset() => _seen.clear();
}
