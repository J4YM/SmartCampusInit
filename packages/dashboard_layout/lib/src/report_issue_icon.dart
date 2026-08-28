import 'package:flutter/material.dart';

/// "Report a Technical Issue" action icon used across dashboards — a single
/// report/flag-a-problem glyph, universally recognizable on its own without
/// needing a composite badge stacked on top of it.
class ReportIssueIcon extends StatelessWidget {
  const ReportIssueIcon({
    super.key,
    this.size = 22,
    this.color = Colors.white,
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Icon(Icons.report_problem_outlined, size: size, color: color);
  }
}
