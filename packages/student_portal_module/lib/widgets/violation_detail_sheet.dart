import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/sanction_history_entry.dart';
import '../models/violation_models.dart';
import '../theme/student_portal_colors.dart';
import '../theme/student_portal_spacing.dart';
import '../util/date_format.dart';
import 'status_badge.dart';

/// A bottom sheet on mobile, a centered dialog on desktop — see
/// [showResponsiveSheet].
///
/// Takes [isDarkMode] explicitly instead of reading `context.isDarkMode`
/// itself — see the matching doc comment on `showDayDetailSheet` for why:
/// depending on the caller, `context` may sit above the local Theme it
/// actually needs (`_StudentPortalHomePageState`'s own `State.context`) or
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
  ).withPoppins();
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
        StudentPortalSpacing.xl,
        StudentPortalSpacing.lg,
        StudentPortalSpacing.xl,
        MediaQuery.of(context).viewInsets.bottom + StudentPortalSpacing.xxl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppPopupHeader(
            title: violation.title,
            subtitle:
                '${violation.recordedBy} · ${formatDateTimeLabel(violation.dateFiled)}',
            onClose: () => Navigator.of(context).pop(),
          ),
          const SizedBox(height: StudentPortalSpacing.lg),
          Wrap(
            spacing: StudentPortalSpacing.xs,
            runSpacing: StudentPortalSpacing.xs,
            children: [
              StatusBadge(
                label: violation.offenseLabel,
                foreground: StudentPortalColors.textPrimary(context),
                background: StudentPortalColors.surfaceMuted(context),
              ),
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
              if (violation.behaviorCategory != null)
                StatusBadge(
                  label: violation.behaviorCategory!,
                  foreground: StudentPortalColors.textSecondary(context),
                  background: StudentPortalColors.surfaceMuted(context),
                ),
            ],
          ),
          const SizedBox(height: StudentPortalSpacing.lg),
          Text(
            violation.description,
            style: GoogleFonts.poppins(
              fontSize: context.isMobileWidth ? 12 : 13.5,
              height: 1.5,
              color: StudentPortalColors.textPrimary(context),
            ),
          ),
          if (violation.sanction != null) ...[
            const SizedBox(height: StudentPortalSpacing.lg),
            _SanctionBlock(sanction: violation.sanction!),
          ],
        ],
      ),
    );
  }
}

/// The sanction that closed the case: type, what was decided, the dates
/// (start and end for a suspension) and whether it is pending, being served
/// or completed.
class _SanctionBlock extends StatelessWidget {
  const _SanctionBlock({required this.sanction});

  final SanctionHistoryEntry sanction;

  static String _date(DateTime d) => formatMonthDayYear(d);

  Color _statusColor() {
    switch (sanction.status) {
      case 'Completed':
        return const Color(0xFF2E9E6A);
      case 'Serving':
        return const Color(0xFFE08A00);
      default:
        return const Color(0xFF64748B);
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = GoogleFonts.poppins(
      fontSize: 12.5,
      height: 1.5,
      color: StudentPortalColors.textPrimary(context),
    );
    final muted = GoogleFonts.poppins(
      fontSize: 11.5,
      color: StudentPortalColors.textSecondary(context),
    );
    final dates = sanction.endsOn == null
        ? 'Starts ${_date(sanction.effectiveOn)}'
        : '${_date(sanction.effectiveOn)} – ${_date(sanction.endsOn!)}';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: StudentPortalColors.surfaceMuted(context),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Sanction: ${sanction.typeLabel}',
                    style: style.copyWith(fontWeight: FontWeight.w600)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _statusColor().withOpacity(0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  sanction.status,
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _statusColor(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(sanction.description, style: style),
          const SizedBox(height: 6),
          Text(
            sanction.isSuspension
                ? 'Suspension: $dates'
                : 'Effective: $dates',
            style: muted,
          ),
          if (sanction.affectsEnrollment)
            Text('Affects re-enrollment', style: muted),
        ],
      ),
    );
  }
}
