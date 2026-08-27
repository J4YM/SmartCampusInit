import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';

abstract final class AppColors {
  // The sidebar is a permanent dark-navy accent bar in both app themes
  // (matching the discipline officer / guidance counselor dashboards'
  // convention of an always-dark left nav) — it does not itself flip with
  // light/dark mode, only the main content canvas does.
  static const Color sidebarBackground = Color(0xFF15253F);
  static const Color sidebarText = Color(0xFFE6E6E6);
  static const Color sidebarMuted = Color(0xB3E6E6E6);
  static const Color sidebarDivider = Color(0x33E6E6E6);
  static const Color sidebarActive = Color(0x1FE6E6E6);
  // Text-only tokens for the sidebar's Poppins typography hierarchy.
  static const Color sidebarSubText = Color(0xFFCBD5E1);
  static const Color sidebarStandaloneText = Color(0xFFE2E8F0);
  static const Color sidebarEmailText = Color(0xFF94A3B8);

  static Color mainBackground(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF0F172A) : const Color(0xFFF4F6FA);
  static Color contentText(BuildContext context) =>
      context.isDarkMode ? const Color(0xFFF1F5F9) : const Color(0xFF1F2937);
  static Color contentMuted(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF6B7280);

  static Color topNavBackground(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF16191D) : Colors.white;
  static Color topNavBorder(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF334155) : const Color(0xFFE5E7EB);
  static Color topNavIcon(BuildContext context) =>
      context.isDarkMode ? const Color(0xFFE2E8F0) : const Color(0xFF475569);
  static Color topNavIconHover(BuildContext context) =>
      context.isDarkMode ? const Color(0x1FE2E8F0) : const Color(0xFFF1F5F9);
}

abstract final class AppDimensions {
  static const double sidebarWidth = 260;

  /// Icon-only rail width when the sidebar is collapsed via the top navbar's
  /// hamburger button.
  static const double sidebarCollapsedWidth = 80;
}
