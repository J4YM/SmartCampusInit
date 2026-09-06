import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/violation_models.dart';
import '../theme/student_portal_colors.dart';
import '../theme/student_portal_spacing.dart';
import '../util/date_format.dart';
import 'status_badge.dart';

/// A bottom sheet on mobile, a centered dialog on desktop — see
/// [showResponsiveSheet].
Future<void> showViolationDetailSheet(
  BuildContext context,
  StudentViolationModel violation,
) {
  return showResponsiveSheet(
    context: context,
    backgroundColor: StudentPortalColors.surface(context),
    handleColor: StudentPortalColors.surfaceMuted(context),
    builder: (sheetContext) => _ViolationDetailSheet(violation: violation),
  );
}

class _ViolationDetailSheet extends StatelessWidget {
  const _ViolationDetailSheet({required this.violation});

  final StudentViolationModel violation;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        StudentPortalSpacing.xl,
        StudentPortalSpacing.sm,
        StudentPortalSpacing.xl,
        MediaQuery.of(context).viewInsets.bottom + StudentPortalSpacing.xxl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: StudentPortalSpacing.xs,
            children: [
              StatusBadge(
                label: violation.category.label,
                foreground: violation.category.foreground(context),
                background: violation.category.background(context),
              ),
              StatusBadge(
                label: violation.status.label,
                foreground: violation.status.foreground(context),
                background: violation.status.background(context),
                icon: violation.status.icon,
              ),
            ],
          ),
          const SizedBox(height: StudentPortalSpacing.sm),
          Text(
            violation.title,
            style: GoogleFonts.poppins(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: StudentPortalColors.textPrimary(context),
            ),
          ),
          const SizedBox(height: StudentPortalSpacing.xs),
          Text(
            '${violation.recordedBy} · ${formatMonthDayYear(violation.dateFiled)}',
            style: GoogleFonts.inter(
              fontSize: 12,
              color: StudentPortalColors.textSecondary(context),
            ),
          ),
          const SizedBox(height: StudentPortalSpacing.lg),
          Text(
            violation.description,
            style: GoogleFonts.inter(
              fontSize: 13.5,
              height: 1.5,
              color: StudentPortalColors.textPrimary(context),
            ),
          ),
        ],
      ),
    );
  }
}
