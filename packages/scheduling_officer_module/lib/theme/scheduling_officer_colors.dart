import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';

/// Theme tokens for the Scheduling Officer dashboard — a single simple
/// page, so this stays much smaller than a multi-tab module's own colors
/// file (e.g. RegistrarColors). Reuses the same navy/azure accents other
/// staff dashboards already use, for visual consistency across the app
/// rather than inventing a new brand color for one page.
abstract final class SchedulingOfficerColors {
  static const navyBlue = Color(0xFF15253F);
  static const azureBlue = Color(0xFF345892);
  static const successGreen = Color(0xFF137333);
  static const warningAmber = Color(0xFF92400E);

  static Color background(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF0E0E0E) : const Color(0xFFF0F5F8);

  static Color card(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF191A1F) : Colors.white;

  static Color cardBorder(BuildContext context) => context.isDarkMode
      ? const Color(0xFF22242B)
      : const Color(0x0D000000);

  static Color mutedText(BuildContext context) =>
      context.isDarkMode ? const Color(0xFFA1A1AA) : const Color(0xFF8F8F8F);

  static Color rowText(BuildContext context) =>
      context.isDarkMode ? const Color(0xFFF5F5F5) : const Color(0xFF343A40);
}
