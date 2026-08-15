import 'package:flutter/material.dart';

/// Shared "is this build in dark mode" check for every dashboard module —
/// each module wraps its Scaffold in a `Theme` driven by its own local
/// `ValueNotifier<ThemeMode>` (toggled from the header's profile popover),
/// so `Theme.of(context).brightness` is always the live, current mode.
extension BrightnessX on BuildContext {
  bool get isDarkMode => Theme.of(this).brightness == Brightness.dark;
}
