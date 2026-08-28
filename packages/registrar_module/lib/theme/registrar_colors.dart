import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';

/// Theme tokens shared by every tab of the Registrar Dashboard — exact hex
/// values from the Figma "REG | *" frames (node 525:1112 and siblings), not
/// the nearest existing palette, per design fidelity.
///
/// Accent/brand tokens ([navyBlue], [azureBlue], [gray], [dangerRed],
/// [successGreen], [brightRed], [brightBlue], [lightLavender]) stay constant
/// regardless of theme — they're meant to read as accents (or, for [gray],
/// as text on the permanently-navy header) no matter what surface they sit
/// on.
///
/// "Surface family" tokens ([background], [card], [cardBorder], [mutedText],
/// [placeholderText], [statValue], [rowText]) are brightness-aware and
/// require a [BuildContext] so they can respond to [ThemeMode] toggles.
abstract final class RegistrarColors {
  static const navyBlue = Color(0xFF15253F);
  static const azureBlue = Color(0xFF345892);
  static const gray = Color(0xFFE6E6E6);
  static const dangerRed = Color(0xFFCD4855);
  static const successGreen = Color(0xFF137333);
  static const brightRed = Color(0xFFFF0004);
  static const brightBlue = Color(0xFF0062FF);
  static const lightLavender = Color(0xFFF1E9FF);

  static Color background(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF111111) : const Color(0xFFF0F5F8);

  static Color card(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF16191D) : Colors.white;

  static Color cardBorder(BuildContext context) => context.isDarkMode
      ? const Color(0x0D334155) // rgba(51,65,85,0.05)
      : const Color(0x0D000000); // rgba(0,0,0,0.05)

  static Color mutedText(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF8F8F8F);

  static Color placeholderText(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF64748B) : const Color(0xFF939FB0);

  static Color statValue(BuildContext context) =>
      context.isDarkMode ? const Color(0xFFF1F5F9) : const Color(0xFF3F3F3F);

  static Color rowText(BuildContext context) =>
      context.isDarkMode ? const Color(0xFFF1F5F9) : const Color(0xFF343A40);
}
