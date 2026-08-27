import 'package:flutter/material.dart';

/// Wrench + alert-circle composite used for the "Report a Technical Issue"
/// action across dashboards. Material's built-in icon set has no single
/// glyph combining the two, so this stacks [Icons.build_outlined] with a
/// small [Icons.error_outline] badge at the bottom-right — matching the
/// wrench-plus-warning-badge design the icon is meant to represent.
/// [backgroundColor] fills a disc behind the badge so it reads as a clean
/// cutout instead of the wrench's strokes showing through underneath it —
/// pass whatever surface color this icon actually sits on at rest.
class ReportIssueIcon extends StatelessWidget {
  const ReportIssueIcon({
    super.key,
    required this.backgroundColor,
    this.size = 22,
    this.color = Colors.white,
  });

  final double size;
  final Color color;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    final badgeSize = size * 0.56;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(Icons.build_outlined, size: size, color: color),
          Positioned(
            right: -badgeSize * 0.18,
            bottom: -badgeSize * 0.18,
            child: Container(
              width: badgeSize,
              height: badgeSize,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: backgroundColor,
              ),
              child: Icon(
                Icons.error_outline,
                size: badgeSize,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
