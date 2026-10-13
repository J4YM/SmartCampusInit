import 'dart:async';

import 'package:flutter/foundation.dart';

/// Whether a new notification makes a sound — the person's own switch, shown
/// in every dashboard's profile menu (and in the Admin's Settings).
///
/// The choice is global to the device, like the light/dark theme, and is saved
/// by the host app: at start-up it sets [enabled]'s value to what was saved
/// last time and [persist] to the function that saves a change. Until then
/// (widget tests, demos) it is simply an in-memory switch that starts on.
abstract final class NotificationSoundSettings {
  /// Listen to this to show the current state; set it through [set].
  static final ValueNotifier<bool> enabled = ValueNotifier<bool>(true);

  /// Saves a change somewhere that outlives the app. Errors are swallowed: a
  /// failed save must never break toggling the switch.
  static Future<void> Function(bool value)? persist;

  static void set(bool value) {
    if (enabled.value == value) return;
    enabled.value = value;
    final save = persist;
    if (save == null) return;
    unawaited(save(value).catchError((Object e) {
      debugPrint('Could not save the notification sound setting: $e');
    }));
  }

  static void toggle() => set(!enabled.value);
}
