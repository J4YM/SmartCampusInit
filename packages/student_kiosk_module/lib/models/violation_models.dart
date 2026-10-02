import 'package:flutter/material.dart';

import '../theme/kiosk_colors.dart';

class ViolationItemData {
  const ViolationItemData({required this.title, required this.code});

  final String title;
  final String code;
}

/// One "Teacher / Adviser" dropdown option — a real `profiles` row
/// (`role = 'Teacher'`) once a connected host supplies them, matching
/// `RegistrarRepository.fetchTeachers()`'s own `TeacherOption` shape
/// without this presentation-only module depending on the data layer
/// directly (same convention as [ViolationItemData]/[ViolationCategoryData]
/// mirroring `handbook_offenses`).
class TeacherOptionData {
  const TeacherOptionData({required this.id, required this.fullName});

  final String id;
  final String fullName;
}

class ViolationCategoryData {
  const ViolationCategoryData({
    required this.badgeLabel,
    required this.badgeBackground,
    required this.badgeForeground,
    required this.items,
  });

  /// A real `handbook_offenses.category` tier (`Minor`, `Major_A` …
  /// `Major_D`) with its kiosk badge label and severity colors — shared by
  /// the student self-report and Security report kiosk screens so both
  /// label and color each tier identically.
  factory ViolationCategoryData.handbook(
    String category,
    List<ViolationItemData> items,
  ) {
    final (label, background, foreground) = switch (category) {
      'Minor' => (
          'Minor Offense',
          KioskColors.minorBadgeBg,
          KioskColors.minorBadgeFg
        ),
      'Major_A' => (
          'Major Offense — Category A',
          KioskColors.majorABadgeBg,
          KioskColors.majorABadgeFg
        ),
      'Major_B' => (
          'Major Offense — Category B',
          KioskColors.majorBBadgeBg,
          KioskColors.majorBBadgeFg
        ),
      'Major_C' => (
          'Major Offense — Category C',
          KioskColors.majorCBadgeBg,
          KioskColors.majorCBadgeFg
        ),
      'Major_D' => (
          'Major Offense — Category D',
          KioskColors.majorDBadgeBg,
          KioskColors.majorDBadgeFg
        ),
      _ => (category, KioskColors.otherBadgeBg, KioskColors.otherBadgeFg),
    };
    return ViolationCategoryData(
      badgeLabel: label,
      badgeBackground: background,
      badgeForeground: foreground,
      items: items,
    );
  }

  /// Display order of the real `handbook_offenses.category` tiers, least to
  /// most severe.
  static const handbookCategoryOrder = [
    'Minor',
    'Major_A',
    'Major_B',
    'Major_C',
    'Major_D',
  ];

  final String badgeLabel;
  final Color badgeBackground;
  final Color badgeForeground;
  final List<ViolationItemData> items;
}
