import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';

import '../theme/student_portal_colors.dart';
import '../theme/student_portal_spacing.dart';

/// Rounded, softly-shadowed card shell reused across the portal's tabs —
/// the rounder 20px radius (vs. the staff dashboards' flatter 12px cards)
/// is part of what makes this shell read as a distinct, more "app-like"
/// surface.
class PortalSurfaceCard extends StatelessWidget {
  const PortalSurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(StudentPortalSpacing.lg),
    this.margin,
  });

  final Widget child;
  final EdgeInsets padding;
  final EdgeInsets? margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: StudentPortalColors.surface(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: StudentPortalColors.cardBorder(context)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(context.isDarkMode ? 0.25 : 0.04),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}
