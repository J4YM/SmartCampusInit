import 'package:flutter/material.dart';

/// Design tokens aligned with Tailwind-style palette from the kiosk mockup.
abstract final class KioskColors {
  static const Color headerNavy = Color(0xFF00158A);
  static const Color gradientTop = Color(0xFFF0F4FF);
  static const Color gradientBottom = Color(0xFFFFFFFF);
  static const Color cardWhite = Color(0xFFFFFFFF);
  static const Color alertBg = Color(0xFFEEF2FF);
  static const Color alertBorder = Color(0xFF3B82F6);
  static const Color alertTitle = Color(0xFF1E40AF);
  static const Color alertBody = Color(0xFF2563EB);
  static const Color textPrimary = Color(0xFF111827);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textMuted = Color(0xFF9CA3AF);
  static const Color itemBorder = Color(0xFFE5E7EB);
  static const Color checkboxBorder = Color(0xFFD1D5DB);
  static const Color disabledButton = Color(0xFF9CA3AF);
  static const Color enabledButton = Color(0xFF00158A);

  // Badge pairs (background, foreground)
  static const Color uniformBadgeBg = Color(0xFFDBEAFE);
  static const Color uniformBadgeFg = Color(0xFF1D4ED8);
  static const Color groomingBadgeBg = Color(0xFFFCE7F3);
  static const Color groomingBadgeFg = Color(0xFFBE185D);
  static const Color punctualityBadgeBg = Color(0xFFFFEDD5);
  static const Color punctualityBadgeFg = Color(0xFFC2410C);
  static const Color otherBadgeBg = Color(0xFFF3F4F6);
  static const Color otherBadgeFg = Color(0xFF374151);
}
