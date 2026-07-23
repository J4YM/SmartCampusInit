import 'package:flutter/material.dart';

abstract final class AppColors {
  static const Color sidebarBackground = Color(0xFF15253F);
  static const Color sidebarText = Color(0xFFE6E6E6);
  static const Color sidebarMuted = Color(0xB3E6E6E6);
  static const Color sidebarDivider = Color(0x33E6E6E6);
  static const Color sidebarActive = Color(0x1FE6E6E6);
  // Text-only tokens for the sidebar's Poppins typography hierarchy.
  static const Color sidebarSubText = Color(0xFFCBD5E1);
  static const Color sidebarStandaloneText = Color(0xFFE2E8F0);
  static const Color sidebarEmailText = Color(0xFF94A3B8);
  static const Color mainBackground = Color(0xFFF4F6FA);
  static const Color contentText = Color(0xFF1F2937);
  static const Color contentMuted = Color(0xFF6B7280);
}

abstract final class AppDimensions {
  static const double sidebarWidth = 312;
}
