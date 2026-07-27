import 'package:flutter/material.dart';

/// Design tokens for the STI College Baliuag login screen.
abstract final class AppColors {
  // Background & overlay
  static const Color overlayBlue = Color(0xFF15253F);

  // Branding panel (left)
  static const Color brandYellow = Color(0xFFFACC15);
  static const Color white = Color(0xFFFFFFFF);
  static const Color brandGradientStart = Color(0xFF1E3A8A);
  static const Color brandGradientEnd = Color(0xFF1E293B);

  // Outer card frame
  static const Color cardFrame = Color(0xFFFFFFFF);
  static const Color cardShadow = Color(0x33000000);

  // Form panel (right)
  static const Color formBackground = Color(0xFFFFFFFF);
  static const Color titleText = Color(0xFF000000);
  static const Color subtitleText = Color(0xFF666666);

  // Inputs
  static const Color inputFill = Color(0xFFF3F4F6);
  static const Color inputLabel = Color(0xFF1F1F1F);
  static const Color inputText = Color(0xFF1F1F1F);
  static const Color inputHint = Color(0xFF9CA3AF);
  static const Color credentialsError = Color(0xFFB3261E);

  // Options row
  static const Color rememberMeText = Color(0xFF444444);
  static const Color forgotPassword = Color(0xFF345892);
  static const Color checkboxIcon = Color(0xFF1D1B20);

  // Actions
  static const Color loginButton = Color(0xFF345892);
  static const Color buttonText = Color(0xFFFFFFFF);

  // Divider & SSO
  static const Color dividerLine = Color(0xFFE0E0E0);
  static const Color dividerText = Color(0xFF888888);
  static const Color microsoftBorder = Color(0xFFD9D9D9);
  static const Color microsoftText = Color(0xFF000000);

  // Microsoft logo squares
  static const Color msRed = Color(0xFFF1511B);
  static const Color msGreen = Color(0xFF80CC28);
  static const Color msBlue = Color(0xFF00ADEF);
  static const Color msYellow = Color(0xFFFBBC09);
}

/// Layout dimensions for the login card and its panels.
abstract final class AppDimensions {
  static const double cardRadius = 24;
  static const double cardFramePadding = 7;
  static const double panelRadius = 18;
  static const double panelGap = 12;

  /// Bounded width of the card's inner two-panel row (desktop layout).
  static const double cardContentWidth = 860;

  /// Branding : form panel width ratio is [brandingFlex] : [formFlex]
  /// (~1.2 : 1), so the branding panel reads visibly wider.
  static const int brandingFlex = 6;
  static const int formFlex = 5;

  static const double brandingPanelPaddingH = 44;
  static const double brandingPanelPaddingV = 40;

  /// Narrower side padding widens the visible field/button width by ~20-30%.
  static const double formPanelPaddingH = 28;
  static const double formPanelPaddingV = 24;

  static const double fieldHeight = 48;
  static const double fieldRadius = 8;

  static const double buttonHeight = 48;
  static const double buttonRadius = 8;

  static const double responsiveBreakpoint = 800;

  static const double mobileBannerHeight = 220;
  static const double mobileFormPaddingH = 24;
  static const double mobileFormPaddingV = 24;

  /// Scales mobile card contents down slightly for better fit on small screens.
  static const double mobileContentScale = 0.9;

  static double mobileScale(double value) => value * mobileContentScale;

  static const double mobileCardHorizontalPadding = 24;
}
