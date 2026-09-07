import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/attendance_models.dart';
import '../theme/student_portal_colors.dart';
import '../theme/student_portal_spacing.dart';
import '../util/date_format.dart';
import 'month_grid.dart';
import 'portal_surface_card.dart';
import 'section_header.dart';
import 'status_legend.dart';
import 'subject_dropdown.dart';

/// Dashboard tile embedding the full calendar-month grid, its subject
/// filter, and the four-state legend. The whole month is visible here, so
/// there is no separate "View all" attendance-history destination.
class MonthPreviewCard extends StatelessWidget {
  const MonthPreviewCard({
    super.key,
    required this.subjects,
    required this.selectedSubjectId,
    required this.onSubjectChanged,
    required this.month,
    required this.entriesByDay,
    required this.selectedDay,
    required this.onDaySelected,
    required this.onPreviousMonth,
    required this.onNextMonth,
  });

  final List<SubjectModel> subjects;
  final String? selectedSubjectId;
  final ValueChanged<String?> onSubjectChanged;
  final DateTime month;
  final Map<DateTime, List<AttendanceEntry>> entriesByDay;
  final DateTime? selectedDay;
  final ValueChanged<DateTime> onDaySelected;

  /// Null disables the corresponding nav arrow — used once navigation
  /// would go past the earliest month with data, or past the current
  /// month.
  final VoidCallback? onPreviousMonth;
  final VoidCallback? onNextMonth;

  @override
  Widget build(BuildContext context) {
    return PortalSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: 'This Month',
            trailing: SubjectDropdown(
              subjects: subjects,
              selectedSubjectId: selectedSubjectId,
              onChanged: onSubjectChanged,
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  formatMonthYear(month),
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: StudentPortalColors.textSecondary(context),
                  ),
                ),
              ),
              _MonthNavArrow(
                  icon: Icons.chevron_left_rounded, onTap: onPreviousMonth),
              const SizedBox(width: StudentPortalSpacing.xs),
              _MonthNavArrow(
                  icon: Icons.chevron_right_rounded, onTap: onNextMonth),
            ],
          ),
          const SizedBox(height: StudentPortalSpacing.md),
          MonthGrid(
            month: month,
            entriesByDay: entriesByDay,
            selectedDay: selectedDay,
            onDaySelected: onDaySelected,
          ),
          const SizedBox(height: StudentPortalSpacing.md),
          const Divider(height: 1),
          const SizedBox(height: StudentPortalSpacing.md),
          const StatusLegend(),
        ],
      ),
    );
  }
}

class _MonthNavArrow extends StatelessWidget {
  const _MonthNavArrow({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Material(
      color: StudentPortalColors.surfaceMuted(context),
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: SizedBox(
          width: 26,
          height: 26,
          child: Icon(
            icon,
            size: 16,
            color: enabled
                ? StudentPortalColors.textSecondary(context)
                : StudentPortalColors.textMuted(context),
          ),
        ),
      ),
    );
  }
}
