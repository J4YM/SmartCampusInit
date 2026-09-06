import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/violation_models.dart';
import '../theme/student_portal_colors.dart';
import '../theme/student_portal_spacing.dart';
import '../util/date_format.dart';
import 'status_badge.dart';

/// Below this available width, badges + title + date + chevron can't share
/// one line without squeezing the title to nothing — collapse to the
/// two-line layout instead. A width the row's own [LayoutBuilder] measures
/// rather than the whole screen's, since this row renders inside cards of
/// very different widths (a wide bento tile vs. the narrower column it
/// sits in beside the month card).
const _twoLineBreakpoint = 380.0;

/// A single infraction as a compact, left-striped alert row rather than a
/// bulky card — a Major + Pending case gets a tinted background wash so it
/// draws the eye without breaking the row rhythm around it. Collapses to a
/// two-line layout when its own available width is narrow, instead of
/// squeezing everything (badges, title, date) onto one line.
class ViolationRow extends StatelessWidget {
  const ViolationRow({super.key, required this.violation, this.onTap});

  final StudentViolationModel violation;
  final VoidCallback? onTap;

  bool get _needsAttention =>
      violation.category == ViolationCategory.major &&
      violation.status == ViolationStatus.pending;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < _twoLineBreakpoint;
        return _buildRow(context, compact);
      },
    );
  }

  Widget _buildRow(BuildContext context, bool compact) {
    final stripe = violation.category.foreground(context);

    final badges = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        StatusBadge(
          label: violation.category.label,
          foreground: violation.category.foreground(context),
          background: violation.category.background(context),
          dense: true,
        ),
        const SizedBox(width: StudentPortalSpacing.xs),
        StatusBadge(
          label: violation.status.label,
          foreground: violation.status.foreground(context),
          background: violation.status.background(context),
          icon: violation.status.icon,
          dense: true,
        ),
      ],
    );

    final title = Text(
      violation.title,
      maxLines: compact ? 2 : 1,
      overflow: TextOverflow.ellipsis,
      style: GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: StudentPortalColors.textPrimary(context),
      ),
    );

    final date = Text(
      formatMonthDayYear(violation.dateFiled),
      style: GoogleFonts.inter(
        fontSize: 11.5,
        color: StudentPortalColors.textMuted(context),
      ),
    );

    final chevron = Icon(
      Icons.chevron_right_rounded,
      size: 18,
      color: StudentPortalColors.textMuted(context),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: StudentPortalSpacing.sm),
      child: Material(
        color: _needsAttention
            ? violation.category.background(context)
            : StudentPortalColors.surfaceMuted(context),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: StudentPortalSpacing.md,
              vertical: StudentPortalSpacing.md,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border(left: BorderSide(color: stripe, width: 3)),
            ),
            child: compact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: StudentPortalSpacing.xs,
                        runSpacing: StudentPortalSpacing.xs,
                        children: [
                          StatusBadge(
                            label: violation.category.label,
                            foreground: violation.category.foreground(context),
                            background: violation.category.background(context),
                            dense: true,
                          ),
                          StatusBadge(
                            label: violation.status.label,
                            foreground: violation.status.foreground(context),
                            background: violation.status.background(context),
                            icon: violation.status.icon,
                            dense: true,
                          ),
                        ],
                      ),
                      const SizedBox(height: StudentPortalSpacing.sm),
                      title,
                      const SizedBox(height: StudentPortalSpacing.xs),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [date, chevron],
                      ),
                    ],
                  )
                : Row(
                    children: [
                      badges,
                      const SizedBox(width: StudentPortalSpacing.md),
                      Expanded(child: title),
                      const SizedBox(width: StudentPortalSpacing.sm),
                      date,
                      chevron,
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
