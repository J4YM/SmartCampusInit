import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';

/// Theme tokens shared by every tab of the Discipline Officer Dashboard —
/// exact hex values from the Figma "DC Dashboard" frames (Violations: node
/// 408:527, Good Moral Requests: node 409:708, Good Moral Student List:
/// node 411:1097), matching the same token set used by `professor_module`'s
/// theme so every dashboard in this system shares one visual language. This
/// is the canonical reference for future dashboard tabs: colors, spacing,
/// and typography should all trace back to values like these rather than
/// being approximated per-widget.
///
/// Brand/accent tokens ([navyBlue], [azureBlue], the Validate/Modify/Deny
/// button colors, and the banner *border* accents) stay constant across
/// light/dark — they're meant to read as accents regardless of surface.
/// "Surface family" tokens (backgrounds, borders, body text) are functions
/// of [BuildContext] so they respond to [BrightnessX.isDarkMode].
abstract final class DisciplineOfficerColors {
  static const navyBlue = Color(0xFF15253F);
  static Color background(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF111111) : const Color(0xFFF0F5F8);
  static const azureBlue = Color(0xFF345892);
  static Color mutedText(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF8F8F8F);
  static Color placeholderText(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF939FB0);
  static Color gray(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF334155) : const Color(0xFFE6E6E6);
  static Color card(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF16191D) : Colors.white;
  static Color cardBorder(BuildContext context) => context.isDarkMode
      ? const Color(0x0D334155) // rgba(51,65,85,0.05)
      : const Color(0x0D000000); // rgba(0,0,0,0.05)
  static Color cardBorderLight(BuildContext context) => context.isDarkMode
      ? const Color(0xFF334155)
      : const Color(0x1A000000); // rgba(0,0,0,0.1)
  static Color selectedRow(BuildContext context) => context.isDarkMode
      ? const Color(0x40345892) // rgba(52,88,146,0.25) — richer for dark card
      : const Color(0x26345892); // rgba(52,88,146,0.15)
  static Color statValue(BuildContext context) =>
      context.isDarkMode ? const Color(0xFFF1F5F9) : const Color(0xFF3F3F3F);

  /// Primary body text sitting directly on [card]/[background] surfaces.
  static Color rowText(BuildContext context) =>
      context.isDarkMode ? const Color(0xFFF1F5F9) : const Color(0xFF000000);

  static Color violationBannerBg(BuildContext context) => context.isDarkMode
      ? const Color(0x4DFF0004) // rgba(255,0,4,0.30)
      : const Color(0x26FF0004); // rgba(255,0,4,0.15)
  static const violationBannerBorder = Color(0xFFFF0004);

  // Good Moral "Clearance Status" banner.
  static Color infoBannerBg(BuildContext context) => context.isDarkMode
      ? const Color(0x4D0062FF) // rgba(0,98,255,0.30)
      : const Color(0x260062FF); // rgba(0,98,255,0.15)
  static const infoBannerBorder = Color(0xFF0062FF);

  static const validateGreen = Color(0xFF35AE50);
  static const validateMuted = Color(0xFFB8E3C1);
  static const modifyBlue = Color(0xFF345892);
  static const modifyMuted = Color(0xFFB9C6DA);
  static const denyRed = Color(0xFFCD4855);
  static const denyMuted = Color(0xFFF0C3C7);
}
