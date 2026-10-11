import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;

/// Where the light/dark choice lives between dashboards, sign-outs and app
/// restarts. Every dashboard owns its own page-local theme switch, and each
/// one is torn down on sign-out — without this, the next sign-in would always
/// start light again.
///
/// The app (not this package) decides how the choice is stored: at start-up it
/// sets [current] to what it saved last time and [persist] to the function
/// that saves it (see `lib/app/theme_mode_persistence.dart`).
///
/// Until the app opts in by setting [persist] — in a widget test, a package
/// demo — the store is inert: every dashboard starts light and a toggle is
/// local to it, exactly as before. (A process-wide choice would otherwise leak
/// from one test into the next.)
abstract final class ThemeModeStore {
  /// The mode a dashboard starts in. Once the app has opted in, updated on
  /// every change, so a dashboard opened after another one was signed out of
  /// picks up the same choice.
  static ThemeMode current = ThemeMode.light;

  /// Saves the choice somewhere that outlives the app; setting it is what
  /// switches the store on. Errors are swallowed: a failed save must never
  /// break toggling the theme.
  static Future<void> Function(ThemeMode mode)? persist;

  static void remember(ThemeMode mode) {
    final save = persist;
    if (save == null) return;
    current = mode;
    unawaited(save(mode).catchError((Object e) {
      debugPrint('Could not save the theme mode: $e');
    }));
  }
}

/// A dashboard's theme switch: a `ValueNotifier<ThemeMode>` that starts at the
/// saved choice ([ThemeModeStore.current]) and saves every change, so the
/// light/dark choice survives sign-out and restart. Use it wherever a
/// dashboard used to hold `ValueNotifier(ThemeMode.light)`.
class PersistedThemeModeNotifier extends ValueNotifier<ThemeMode> {
  PersistedThemeModeNotifier() : super(ThemeModeStore.current) {
    addListener(_save);
  }

  void _save() => ThemeModeStore.remember(value);

  @override
  void dispose() {
    removeListener(_save);
    super.dispose();
  }
}
