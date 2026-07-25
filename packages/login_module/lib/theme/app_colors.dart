import 'package:flutter/material.dart';

/// Figma-extracted design tokens for the STI College Baliuag login screen.
abstract final class AppColors {
  // Brand & overlay
  static const Color brandYellow = Color(0xFFFBD709);
  static const Color overlayBlue = Color(0xFF15253F);
  static const Color white = Color(0xFFFFFFFF);

  // Card & headings
  static const Color cardBackground = Color(0xFFFFFFFF);
  static const Color cardHeader = Color(0xFF343A40);

  // Inputs
  static const Color fieldBorder = Color(0xFF79747E);
  static const Color fieldText = Color(0xFF49454F);
  static const Color credentialsError = Color(0xFFB3261E);

  // Options row
  static const Color rememberMe = Color(0xFF000000);
  static const Color forgetPassword = Color(0xFF345892);
  static const Color checkboxIcon = Color(0xFF1D1B20);

  // Actions
  static const Color loginButton = Color(0xFF345892);
  static const Color buttonText = Color(0xFFFFFFFF);
  static const Color dividerLine = Color(0xFF000000);
  static const Color microsoftBorder = Color(0xFF000000);
  static const Color microsoftText = Color(0xFF000000);

  // Microsoft logo squares (Figma vectors)
  static const Color msRed = Color(0xFFF1511B);
  static const Color msGreen = Color(0xFF80CC28);
  static const Color msBlue = Color(0xFF00ADEF);
  static const Color msYellow = Color(0xFFFBBC09);
}

/// Figma-extracted layout dimensions.
abstract final class AppDimensions {
  static const double cardWidth = 400;
  static const double cardRadius = 20;
  static const double cardPaddingH = 20;
  static const double cardPaddingV = 30;

  static const double fieldWidth = 340;
  static const double fieldHeight = 56;
  static const double fieldRadius = 10;

  static const double buttonWidth = 340;
  static const double buttonHeight = 56;
  static const double buttonRadius = 10;

  static const double microsoftBorderWidth = 0.8;
  static const double dividerThickness = 0.5;

  static const double headingFontSize = 90;
  static const double headingLineHeight = 60;
  static const double subtitleScale = 0.6;
  static const double cardTitleFontSize = 24;

  static const double responsiveBreakpoint = 800;
  static const double mobileBannerScale = 0.85;
  static const double mobileBannerBaseHeight = 280;
  static double get mobileBannerHeight => mobileBannerBaseHeight * mobileBannerScale;
  static const double mobileBannerPaddingH = 28;
  static const double mobileFormPaddingH = 24;
  static const double mobileFormPaddingV = 24;

  /// Scales mobile card contents down (~15%) for better fit on small screens.
  static const double mobileContentScale = 0.85;

  static double mobileScale(double value) => value * mobileContentScale;

  static const double desktopHorizontalPadding = 240;
}
