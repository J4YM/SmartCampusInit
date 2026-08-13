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

  // Real `handbook_offenses.category` severity-tier badges (Minor -> Major
  // D), escalating green -> amber -> orange -> red -> deep red. Used when
  // the violation list is populated from Supabase instead of the demo
  // categories above.
  static const Color minorBadgeBg = Color(0xFFDCFCE7);
  static const Color minorBadgeFg = Color(0xFF15803D);
  static const Color majorABadgeBg = Color(0xFFFEF3C7);
  static const Color majorABadgeFg = Color(0xFFB45309);
  static const Color majorBBadgeBg = Color(0xFFFFEDD5);
  static const Color majorBBadgeFg = Color(0xFFC2410C);
  static const Color majorCBadgeBg = Color(0xFFFEE2E2);
  static const Color majorCBadgeFg = Color(0xFFDC2626);
  static const Color majorDBadgeBg = Color(0xFFFECACA);
  static const Color majorDBadgeFg = Color(0xFF7F1D1D);
}
