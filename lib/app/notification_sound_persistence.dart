import 'package:dashboard_layout/dashboard_layout.dart'
    show NotificationSoundSettings;
import 'package:flutter/foundation.dart';

import 'app_state_persistence.dart';
import 'notification_alert.dart';
import 'notification_sound.dart';

/// Connects the notification sound to this device's storage and to the alert
/// detector: restores the saved on/off choice, saves each later change, and
/// points [NotificationAlert.onNew] at the sound — which stays silent while
/// the person has it switched off.
///
/// Never throws — if storage is unavailable the sound simply starts on and the
/// choice lasts for the session.
Future<void> setUpNotificationSound() async {
  NotificationAlert.onNew = () {
    if (NotificationSoundSettings.enabled.value) playNotificationSound();
  };
  try {
    final persistence = await AppStatePersistence.instance();
    NotificationSoundSettings.enabled.value =
        persistence.notificationSoundEnabled;
    NotificationSoundSettings.persist = persistence.setNotificationSoundEnabled;
  } catch (e) {
    debugPrint('Could not restore the notification sound setting: $e');
  }
}
