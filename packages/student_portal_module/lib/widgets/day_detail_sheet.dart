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
Future<void> showDayDetailSheet(
  BuildContext context,
  DateTime day,
  List<AttendanceEntry> entries,
) {
  return showResponsiveSheet(
    context: context,
    backgroundColor: StudentPortalColors.surface(context),
    handleColor: StudentPortalColors.surfaceMuted(context),
    builder: (sheetContext) => _DayDetailSheet(day: day, entries: entries),
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
              InkWell(
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
                            entry.subjectName,
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
