import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/attendance_models.dart';
import '../theme/student_portal_colors.dart';
import 'attendance_mark.dart';

/// Mark+label key under the week rail — spells out what each shape means
/// (filled = confirmed, ring = flagged) rather than leaving it to guesswork.
class StatusLegend extends StatelessWidget {
  const StatusLegend({super.key});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 14,
      runSpacing: 8,
      children: [
        for (final status in AttendanceStatus.values)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AttendanceMark(status: status, size: 11),
              const SizedBox(width: 6),
              Text(
                status.label,
                style: GoogleFonts.inter(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  color: StudentPortalColors.textSecondary(context),
                ),
              ),
            ],
          ),
      ],
    );
  }
}
