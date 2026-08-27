import 'package:flutter/material.dart';

/// Lays out stat/metric cards two per row for narrow (mobile) viewports.
/// When the card count is odd, the last row's single card spans the full
/// row width instead of sitting at half width with an empty gap beside it.
/// Used by every dashboard module's stat-card row (Violations, Attendance,
/// Conduct Report, Overview) in place of a plain `Wrap`, which — at real
/// mobile widths — only fit one fixed-width card per row instead of two.
class MobileMetricGrid extends StatelessWidget {
  const MobileMetricGrid({
    super.key,
    required this.cards,
    this.spacing = 18,
  });

  final List<Widget> cards;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columnWidth = (constraints.maxWidth - spacing) / 2;
        final rows = <Widget>[];

        for (var i = 0; i < cards.length; i += 2) {
          if (rows.isNotEmpty) rows.add(SizedBox(height: spacing));

          final isTrailingSingle = i + 1 >= cards.length;
          rows.add(
            isTrailingSingle
                ? cards[i]
                : IntrinsicHeight(
                    child: Row(
                      children: [
                        SizedBox(width: columnWidth, child: cards[i]),
                        SizedBox(width: spacing),
                        SizedBox(width: columnWidth, child: cards[i + 1]),
                      ],
                    ),
                  ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rows,
        );
      },
    );
  }
}
