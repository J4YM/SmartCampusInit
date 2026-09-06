import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/attendance_models.dart';
import '../theme/student_portal_colors.dart';
import '../theme/student_portal_spacing.dart';
import 'attendance_mark.dart';

const _dow = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];

/// Full calendar-month grid (Monday-start, 7 columns) — used by both the
/// dashboard's "This Month" card and the day-detail sheet's callers. Each
/// cell rolls up every subject's status for that day via the same
/// worst-status-wins rule ([aggregateStatus]), so a problem day is never
/// hidden behind a green mark just because one subject happened to be fine.
class MonthGrid extends StatelessWidget {
  const MonthGrid({
    super.key,
    required this.month,
    required this.entriesByDay,
    required this.selectedDay,
    required this.onDaySelected,
  });

  /// Any date within the month to render — only year/month are read.
  final DateTime month;

  /// Keyed by [dateOnly]'d date, scoped to [month] by the caller.
  final Map<DateTime, List<AttendanceEntry>> entriesByDay;
  final DateTime? selectedDay;
  final ValueChanged<DateTime> onDaySelected;

  @override
  Widget build(BuildContext context) {
    final firstOfMonth = DateTime(month.year, month.month);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leadingBlanks = firstOfMonth.weekday - DateTime.monday;
    final totalCells = leadingBlanks + daysInMonth;
    final rowCount = (totalCells / 7).ceil();
    final today = dateOnly(DateTime.now());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            for (final label in _dow)
              Expanded(
                child: Center(
                  child: Text(
                    label,
                    style: GoogleFonts.inter(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                      color: StudentPortalColors.textMuted(context),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: StudentPortalSpacing.sm),
        for (var row = 0; row < rowCount; row++) ...[
          if (row > 0) const SizedBox(height: StudentPortalSpacing.xs),
          Row(
            children: [
              for (var col = 0; col < 7; col++) ...[
                if (col > 0) const SizedBox(width: StudentPortalSpacing.xs),
                Expanded(
                  child: _cell(
                    context,
                    cellIndex: row * 7 + col,
                    leadingBlanks: leadingBlanks,
                    daysInMonth: daysInMonth,
                    today: today,
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }

  Widget _cell(
    BuildContext context, {
    required int cellIndex,
    required int leadingBlanks,
    required int daysInMonth,
    required DateTime today,
  }) {
    final dayNumber = cellIndex - leadingBlanks + 1;
    if (dayNumber < 1 || dayNumber > daysInMonth) {
      return const SizedBox(height: 52);
    }

    final date = DateTime(month.year, month.month, dayNumber);
    final status = aggregateStatus(entriesByDay[date] ?? const []);
    final isFuture = date.isAfter(today);
    final isToday = date == today;
    final isSelected = selectedDay != null && dateOnly(selectedDay!) == date;

    return _MonthDayCell(
      day: dayNumber,
      status: status,
      isToday: isToday,
      isSelected: isSelected,
      isFuture: isFuture,
      onTap: isFuture ? null : () => onDaySelected(date),
    );
  }
}

class _MonthDayCell extends StatelessWidget {
  const _MonthDayCell({
    required this.day,
    required this.status,
    required this.isToday,
    required this.isSelected,
    required this.isFuture,
    required this.onTap,
  });

  final int day;
  final AttendanceStatus? status;
  final bool isToday;
  final bool isSelected;
  final bool isFuture;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: isSelected
              ? StudentPortalColors.accent(context)
              : isToday
                  ? StudentPortalColors.primarySoft(context)
                  : Colors.transparent,
          border: Border.all(
            color: isToday && !isSelected
                ? StudentPortalColors.accent(context)
                : StudentPortalColors.cardBorder(context),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$day',
              style: GoogleFonts.inter(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: isSelected
                    ? Colors.white
                    : isFuture
                        ? StudentPortalColors.textMuted(context)
                        : StudentPortalColors.textPrimary(context),
              ),
            ),
            const SizedBox(height: 4),
            isSelected && status != null
                ? SelectedAttendanceMark(status: status!, size: 10)
                : AttendanceMark(status: status, size: 10),
          ],
        ),
      ),
    );
  }
}
