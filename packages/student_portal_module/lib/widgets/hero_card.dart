import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/student_portal_colors.dart';
import '../theme/student_portal_spacing.dart';
import '../util/date_format.dart';
import 'attendance_ring.dart';
import 'portal_surface_card.dart';

/// The dashboard's lead card — greeting, program line, this-month attendance
/// ring, and a quick Present/Late/Absent chip row. This replaces the old
/// full-bleed gradient banner: it's just the first (biggest) bento tile now,
/// scaled to the content it holds rather than the full viewport width.
class HeroCard extends StatelessWidget {
  const HeroCard({
    super.key,
    required this.studentName,
    required this.programLine,
    required this.attendanceRate,
    required this.presentCount,
    required this.lateCount,
    required this.absentCount,
  });

  final String studentName;
  final String programLine;
  final double attendanceRate;
  final int presentCount;
  final int lateCount;
  final int absentCount;

  String get _firstName => studentName.trim().split(RegExp(r'\s+')).first;

  @override
  Widget build(BuildContext context) {
    final compact = context.isMobileWidth;

    final textBlock = Column(
      crossAxisAlignment:
          compact ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          formatFullWeekdayDate(DateTime.now()),
          textAlign: compact ? TextAlign.center : TextAlign.start,
          style: GoogleFonts.inter(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
            color: StudentPortalColors.accent(context),
          ),
        ),
        const SizedBox(height: StudentPortalSpacing.xs),
        Text(
          '${greetingForHour(DateTime.now().hour)}, $_firstName',
          textAlign: compact ? TextAlign.center : TextAlign.start,
          style: GoogleFonts.poppins(
            fontSize: 23,
            fontWeight: FontWeight.w700,
            color: StudentPortalColors.textPrimary(context),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          programLine,
          textAlign: compact ? TextAlign.center : TextAlign.start,
          style: GoogleFonts.inter(
            fontSize: 12.5,
            color: StudentPortalColors.textSecondary(context),
          ),
        ),
        const SizedBox(height: StudentPortalSpacing.md + 2),
        Wrap(
          alignment: compact ? WrapAlignment.center : WrapAlignment.start,
          spacing: StudentPortalSpacing.sm,
          runSpacing: StudentPortalSpacing.sm,
          children: [
            _StatChip(
              color: StudentPortalColors.presentFg(context),
              label: '$presentCount Present',
            ),
            _StatChip(
              color: StudentPortalColors.lateFg(context),
              label: '$lateCount Late',
            ),
            _StatChip(
              color: StudentPortalColors.absentFg(context),
              label: '$absentCount Absent',
            ),
          ],
        ),
      ],
    );

    final ring = AttendanceRing(percent: attendanceRate);

    return PortalSurfaceCard(
      padding: const EdgeInsets.symmetric(
        horizontal: StudentPortalSpacing.xxl,
        vertical: StudentPortalSpacing.xl,
      ),
      child: compact
          ? Column(
              children: [
                textBlock,
                const SizedBox(height: StudentPortalSpacing.xl),
                ring,
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: textBlock),
                const SizedBox(width: StudentPortalSpacing.xxl),
                ring,
              ],
            ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: StudentPortalColors.surfaceMuted(context),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: StudentPortalColors.textPrimary(context),
            ),
          ),
        ],
      ),
    );
  }
}
