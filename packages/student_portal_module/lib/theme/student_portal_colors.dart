import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';

/// Design tokens for the student-facing portal.
///
/// Deliberately a *different shell* from the staff dashboards (no full-bleed
/// navy header + dark sidebar) — an asymmetric "bento" dashboard with
/// rounded cards, so the system reads as "student app" vs. "staff console"
/// at a glance. The brand blue itself is the same one used everywhere else
/// in the app (`ColorScheme.fromSeed(seedColor: 0xFF2563EB)` in
/// `lib/main.dart`) — it only brightens to a lighter tint in dark mode, the
/// same way it would need to for contrast against a near-black ground —
/// plus the same status-badge convention every dashboard already uses
/// (green/amber/orange/red escalation), so it still reads as one system.
abstract final class StudentPortalColors {
  /// Brand blue in light mode — matches the app-wide seed color and every
  /// dashboard's primary accent exactly.
  static const Color brandPrimary = Color(0xFF2563EB);

  /// The theme-correct accent — brightens to `#5B8DEF` in dark mode for
  /// contrast against the near-black ground, same hue family as
  /// [brandPrimary]. Prefer this over the raw [brandPrimary] constant
  /// anywhere the color sits on a themed surface rather than a fixed white.
  static Color accent(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF5B8DEF) : brandPrimary;

  static Color pageBackground(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF0E0E0E) : const Color(0xFFF4F6FA);

  static Color surface(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF191A1F) : Colors.white;

  static Color surfaceMuted(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF22242B) : const Color(0xFFF1F5F9);

  static Color cardBorder(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF22242B) : const Color(0x141E293B);

  /// A stronger border than [cardBorder] — used for things that read as
  /// controls (day marks, dropdown outlines) rather than card edges.
  static Color borderStrong(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF2E313A) : const Color(0x241E293B);

  /// Tinted wash of [accent] — the hero ring's track corner and the active
  /// state behind selected controls (today's day cell, unread avatars).
  static Color primarySoft(BuildContext context) =>
      accent(context).withOpacity(context.isDarkMode ? 0.16 : 0.10);

  static Color textPrimary(BuildContext context) =>
      context.isDarkMode ? const Color(0xFFF5F5F5) : const Color(0xFF1E293B);

  static Color textSecondary(BuildContext context) =>
      context.isDarkMode ? const Color(0xFFA1A1AA) : const Color(0xFF64748B);

  static Color textMuted(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF71717A) : const Color(0xFF94A3B8);

  // --- Attendance status tokens --------------------------------------
  // Icon glyph per status (see AttendanceStatusX.icon) matches Professor
  // Dashboard's Attendance table exactly (check/cancel/watch_later/info),
  // so a status reads identically everywhere in the app. Dark-mode values
  // brighten for contrast against the near-black ground rather than
  // reusing the light-mode hue at the same lightness.
  static Color presentFg(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF4ADE80) : const Color(0xFF15803D);
  static Color presentBg(BuildContext context) =>
      context.isDarkMode ? const Color(0x244ADE80) : const Color(0xFFDCFCE7);

  static Color absentFg(BuildContext context) =>
      context.isDarkMode ? const Color(0xFFF87171) : const Color(0xFFDC2626);
  static Color absentBg(BuildContext context) =>
      context.isDarkMode ? const Color(0x24F87171) : const Color(0xFFFEE2E2);

  // Late aliases the same amber used for a Pending violation — both read
  // as "caution" — rather than the portal inventing a second yellow/orange
  // hue of its own.
  static Color lateFg(BuildContext context) => pendingFg(context);
  static Color lateBg(BuildContext context) => pendingBg(context);

  // Excused aliases the app's own brand blue/info tint — the same blue
  // Professor Dashboard's Attendance table uses for its "excused" info
  // icon — rather than the portal's old, unrelated purple.
  static Color excusedFg(BuildContext context) => accent(context);
  static Color excusedBg(BuildContext context) => primarySoft(context);

  // --- Violation tokens (mirrors handbook_offenses severity convention) --
  // Minor/Major alias the same hues as Present/Absent — one escalation
  // ladder reused across attendance and conduct.
  static Color minorFg(BuildContext context) => presentFg(context);
  static Color minorBg(BuildContext context) => presentBg(context);
  static Color majorFg(BuildContext context) => absentFg(context);
  static Color majorBg(BuildContext context) => absentBg(context);

  static Color recordedFg(BuildContext context) =>
      context.isDarkMode ? const Color(0xFFCBD5E1) : const Color(0xFF334155);
  static Color recordedBg(BuildContext context) =>
      context.isDarkMode ? const Color(0x24CBD5E1) : const Color(0xFFE2E8F0);

  static Color pendingFg(BuildContext context) =>
      context.isDarkMode ? const Color(0xFFFBBF24) : const Color(0xFFB45309);
  static Color pendingBg(BuildContext context) =>
      context.isDarkMode ? const Color(0x29FBBF24) : const Color(0xFFFEF3C7);
}
