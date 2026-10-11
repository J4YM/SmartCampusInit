import 'package:dashboard_layout/dashboard_layout.dart' show ThemeModeStore;
import 'package:flutter/foundation.dart';

import 'app_state_persistence.dart';

/// Connects the dashboards' light/dark switch to this device's storage: the
/// saved choice becomes what every dashboard starts in, and each later change
/// is saved. Call once at start-up, before `runApp`, so the first frame is
/// already in the right theme.
///
/// Never throws — if storage is unavailable the dashboards start light and
/// keep the choice in memory for the session (it just isn't saved).
Future<void> restoreThemeMode() async {
  try {
    final persistence = await AppStatePersistence.instance();
    final saved = persistence.themeMode;
    if (saved != null) ThemeModeStore.current = saved;
    ThemeModeStore.persist = persistence.setThemeMode;
  } catch (e) {
    debugPrint('Could not restore the saved theme mode: $e');
    // Still switch the store on, so the choice at least survives a sign-out
    // within this session.
    ThemeModeStore.persist = (_) async {};
  }
}
