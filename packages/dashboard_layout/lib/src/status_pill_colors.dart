import 'package:flutter/material.dart';

import 'brightness_x.dart';
import 'danger_color.dart';

/// Fill + label colors for the status pills ("Active", "Inactive",
/// "Suspended", "Promoted" …) so every dashboard's pill reads the same and none
/// of them glows on a dark card.
///
/// Each returns `(background, foreground)`. Light mode keeps the familiar pale
/// tint with a deep label; dark mode swaps the pale fill (which was a bright
/// slab on a near-black card) for a deep, low-saturation tint with a softened
/// label.
abstract final class StatusPillColors {
  /// Active / approved / promoted.
  static (Color, Color) success(BuildContext context) => context.isDarkMode
      ? (const Color(0xFF1C3427), const Color(0xFF7BC596))
      : (const Color(0xFFDCFCE7), const Color(0xFF15803D));

  /// Inactive / not promoted / no longer applies.
  static (Color, Color) neutral(BuildContext context) => context.isDarkMode
      ? (const Color(0xFF2A2C35), const Color(0xFFA1A1AA))
      : (const Color(0xFFF1F5F9), const Color(0xFF64748B));

  /// Suspended / failed / rejected.
  static (Color, Color) danger(BuildContext context) => context.isDarkMode
      ? (const Color(0xFF3A2327), const Color(0xFFE0707C))
      : (const Color(0xFFFEE2E2), kDangerTextColor);
}
