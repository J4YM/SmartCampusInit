import 'package:flutter/material.dart';

import '../models/attendance_models.dart';
import '../theme/student_portal_colors.dart';

/// The small per-day indicator used on every day cell — the same bare
/// status-icon glyphs Professor Dashboard's Attendance table uses
/// (check/cancel/watch_later/info), so a status reads identically across
/// the whole app rather than the portal inventing its own shape language.
/// `null` status (a weekend or a day with no class) renders the same muted
/// "unmarked" glyph Professor Dashboard uses for a blank cell.
class AttendanceMark extends StatelessWidget {
  const AttendanceMark({super.key, required this.status, this.size = 14});

  final AttendanceStatus? status;
  final double size;

  @override
  Widget build(BuildContext context) {
    final status = this.status;
    if (status == null) {
      return Icon(
        Icons.remove_circle_outline_rounded,
        size: size,
        color: StudentPortalColors.textMuted(context),
      );
    }
    return Icon(status.icon, size: size, color: status.foreground(context));
  }
}

/// The mark rendered inside a selected (filled-blue) day cell — always
/// white so it stays legible against the brand-blue fill. Used by the
/// month grid's day cells.
class SelectedAttendanceMark extends StatelessWidget {
  const SelectedAttendanceMark({
    super.key,
    required this.status,
    this.size = 13,
  });

  final AttendanceStatus status;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Icon(status.icon, size: size, color: Colors.white);
  }
}
