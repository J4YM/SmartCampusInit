import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/intervention_models.dart';
import '../theme/parent_portal_colors.dart';
import '../theme/parent_portal_spacing.dart';
import '../util/date_format.dart';
import 'status_badge.dart';

/// Full text of one intervention message — opened from tapping its compact
/// row on the dashboard card (or in the "View all" list). A bottom sheet on
/// mobile, a centered dialog on desktop — see [showResponsiveSheet].
///
/// Takes [isDarkMode] explicitly for the same reason as
/// `showViolationDetailSheet`: the caller's own `State.context` sits above
/// the portal's local Theme and can't be trusted for brightness.
Future<void> showInterventionDetailSheet(
  BuildContext context,
  InterventionMessageModel message, {
  required bool isDarkMode,
}) {
  final theme = ThemeData(
    useMaterial3: true,
    brightness: isDarkMode ? Brightness.dark : Brightness.light,
  ).withPoppins();
  return showResponsiveSheet(
    context: context,
    backgroundColor: isDarkMode ? const Color(0xFF191A1F) : Colors.white,
    handleColor: isDarkMode ? const Color(0xFF22242B) : const Color(0xFFF1F5F9),
    builder: (sheetContext) => Theme(
      data: theme,
      child: _InterventionDetailSheet(message: message),
    ),
  );
}

class _InterventionDetailSheet extends StatelessWidget {
  const _InterventionDetailSheet({required this.message});

  final InterventionMessageModel message;

  @override
  Widget build(BuildContext context) {
    final m = message;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        ParentPortalSpacing.xl,
        ParentPortalSpacing.lg,
        ParentPortalSpacing.xl,
        MediaQuery.of(context).viewInsets.bottom + ParentPortalSpacing.xxl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppPopupHeader(
            title: m.title,
            subtitle: '${m.sentBy} · ${formatMonthDayYear(m.createdAt)}',
            onClose: () => Navigator.of(context).pop(),
          ),
          const SizedBox(height: ParentPortalSpacing.lg),
          Wrap(
            spacing: ParentPortalSpacing.xs,
            runSpacing: ParentPortalSpacing.xs,
            children: [
              StatusBadge(
                label: m.kind.label,
                foreground: ParentPortalColors.excusedFg(context),
                background: ParentPortalColors.excusedBg(context),
                icon: m.kind.icon,
              ),
              if (m.actionRequired)
                StatusBadge(
                  label: 'Action needed',
                  foreground: ParentPortalColors.pendingFg(context),
                  background: ParentPortalColors.pendingBg(context),
                  icon: Icons.priority_high_rounded,
                ),
            ],
          ),
          const SizedBox(height: ParentPortalSpacing.lg),
          Text(
            m.message,
            style: GoogleFonts.poppins(
              fontSize: context.isMobileWidth ? 12 : 13.5,
              height: 1.5,
              color: ParentPortalColors.textPrimary(context),
            ),
          ),
        ],
      ),
    );
  }
}
