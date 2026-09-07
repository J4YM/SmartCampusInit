import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/student_portal_colors.dart';

/// The hero card's donut — this month's attendance rate at a glance.
class AttendanceRing extends StatelessWidget {
  const AttendanceRing({
    super.key,
    required this.percent,
    this.diameter = 108,
    this.label = 'this month',
  });

  /// 0.0–1.0.
  final double percent;
  final double diameter;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: diameter,
      height: diameter,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size.square(diameter),
            painter: _RingPainter(
              percent: percent.clamp(0, 1),
              trackColor: StudentPortalColors.borderStrong(context),
              valueColor: StudentPortalColors.accent(context),
              strokeWidth: diameter * 0.085,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${(percent * 100).round()}%',
                style: GoogleFonts.poppins(
                  fontSize: diameter * 0.2,
                  fontWeight: FontWeight.w700,
                  color: StudentPortalColors.textPrimary(context),
                  height: 1,
                ),
              ),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: diameter * 0.09,
                  fontWeight: FontWeight.w500,
                  color: StudentPortalColors.textSecondary(context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.percent,
    required this.trackColor,
    required this.valueColor,
    required this.strokeWidth,
  });

  final double percent;
  final Color trackColor;
  final Color valueColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = (size.shortestSide - strokeWidth) / 2;
    final rect =
        Rect.fromCircle(center: size.center(Offset.zero), radius: radius);

    canvas.drawArc(
      rect,
      0,
      2 * math.pi,
      false,
      Paint()
        ..color = trackColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth,
    );

    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * percent,
      false,
      Paint()
        ..color = valueColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.percent != percent ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.valueColor != valueColor;
}
