import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/violation_models.dart';
import '../theme/parent_portal_colors.dart';
import '../theme/parent_portal_spacing.dart';
import '../util/date_format.dart';
import 'status_badge.dart';

/// A bottom sheet on mobile, a centered dialog on desktop — see
/// [showResponsiveSheet].
///
/// Takes [isDarkMode] explicitly instead of reading `context.isDarkMode`
/// itself — see the matching doc comment on `showDayDetailSheet` for why:
/// depending on the caller, `context` may sit above the local Theme it
/// actually needs (`_ParentPortalHomePageState`'s own `State.context`) or
/// below a correctly-applied one (`ViolationsPage`, wrapped in a Theme by
/// its own caller) — a caller-supplied bool sidesteps the ambiguity
/// entirely instead of guessing which case applies here.
Future<void> showViolationDetailSheet(
  BuildContext context,
  StudentViolationModel violation, {
  required bool isDarkMode,
}) {
  final theme = ThemeData(
    useMaterial3: true,
    brightness: isDarkMode ? Brightness.dark : Brightness.light,
  );
  return showResponsiveSheet(
    context: context,
    backgroundColor: isDarkMode ? const Color(0xFF191A1F) : Colors.white,
    handleColor:
        isDarkMode ? const Color(0xFF22242B) : const Color(0xFFF1F5F9),
    builder: (sheetContext) => Theme(
      data: theme,
      child: _ViolationDetailSheet(violation: violation),
    ),
  );
}

class _ViolationDetailSheet extends StatelessWidget {
  const _ViolationDetailSheet({required this.violation});

  final StudentViolationModel violation;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        ParentPortalSpacing.xl,
        ParentPortalSpacing.sm,
        ParentPortalSpacing.xl,
        MediaQuery.of(context).viewInsets.bottom + ParentPortalSpacing.xxl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: ParentPortalSpacing.xs,
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
          const SizedBox(height: ParentPortalSpacing.sm),
          Text(
            violation.title,
            style: GoogleFonts.poppins(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: ParentPortalColors.textPrimary(context),
            ),
          ),
          const SizedBox(height: ParentPortalSpacing.xs),
          Text(
            '${violation.recordedBy} · ${formatMonthDayYear(violation.dateFiled)}',
            style: GoogleFonts.inter(
              fontSize: 12,
              color: ParentPortalColors.textSecondary(context),
            ),
          ),
          const SizedBox(height: ParentPortalSpacing.lg),
          Text(
            violation.description,
            style: GoogleFonts.inter(
              fontSize: 13.5,
              height: 1.5,
              color: ParentPortalColors.textPrimary(context),
            ),
          ),
        ],
      ),
    );
  }
}
