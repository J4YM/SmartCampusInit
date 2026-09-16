import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/attendance_models.dart';
import '../theme/student_portal_colors.dart';
import '../theme/student_portal_spacing.dart';
import 'status_badge.dart';

const _weekdayFull = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];
const _monthFull = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// Per-subject breakdown for one day — opened from tapping a day mark on
/// the month grid, since the grid itself only has room for one rolled-up
/// mark per day. A bottom sheet on mobile, a centered dialog on desktop —
/// see [showResponsiveSheet].
///
/// Takes [isDarkMode] explicitly rather than reading `context.isDarkMode`
/// itself: the caller is `_StudentPortalHomePageState`, whose own
/// `State.context` sits ABOVE the local `Theme` it builds around its own
/// `build()` output (that Theme is a descendant of the State's element, not
/// an ancestor of it) — so `Theme.of(context)`/`context.isDarkMode` from
/// that State's methods always resolves to the app's ambient (light) theme,
/// never the portal's actual dark-mode toggle. Every other popover/push in
/// that same file already sidesteps this by reading `_themeMode.value`
/// directly instead of trusting `context` — this does the same.
Future<void> showDayDetailSheet(
  BuildContext context,
  DateTime day,
  List<AttendanceEntry> entries, {
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
      child: _DayDetailSheet(day: day, entries: entries),
    ),
  );
}

class _DayDetailSheet extends StatelessWidget {
  const _DayDetailSheet({required this.day, required this.entries});

  final DateTime day;
  final List<AttendanceEntry> entries;

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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  '${_weekdayFull[day.weekday - 1]}, ${_monthFull[day.month - 1]} ${day.day}',
                  style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: StudentPortalColors.textPrimary(context),
                  ),
                ),
              ),
              const SizedBox(width: StudentPortalSpacing.sm),
              Tooltip(
                message: 'Close',
                child: InkWell(
                  onTap: () => Navigator.of(context).pop(),
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.close_rounded,
                      size: 22,
                      color: StudentPortalColors.absentFg(context),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: StudentPortalSpacing.md),
          Divider(height: 1, color: StudentPortalColors.cardBorder(context)),
          const SizedBox(height: StudentPortalSpacing.lg),
          if (entries.isEmpty)
            Text(
              'No class sessions recorded for this day.',
              style: GoogleFonts.inter(
                fontSize: 12.5,
                color: StudentPortalColors.textSecondary(context),
              ),
            )
          else
            for (final entry in entries)
              Padding(
                padding: const EdgeInsets.only(bottom: StudentPortalSpacing.lg),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.subjectName ?? 'Daily Attendance',
                            style: GoogleFonts.inter(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: StudentPortalColors.textPrimary(context),
                            ),
                          ),
                          if (entry.timeIn != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                'Tapped in ${entry.timeIn}',
                                style: GoogleFonts.inter(
                                  fontSize: 12.5,
                                  color: StudentPortalColors.textMuted(context),
                                ),
                              ),
                            ),
                          if (entry.remarks != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                entry.remarks!,
                                style: GoogleFonts.inter(
                                  fontSize: 12.5,
                                  color: StudentPortalColors.textMuted(context),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: StudentPortalSpacing.sm),
                    StatusBadge(
                      label: entry.status.label,
                      foreground: entry.status.foreground(context),
                      background: entry.status.background(context),
                      icon: entry.status.icon,
                      dense: true,
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}
