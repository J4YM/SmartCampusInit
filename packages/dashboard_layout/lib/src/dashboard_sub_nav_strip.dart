import 'package:flutter/material.dart';

import 'mouse_draggable_scroll_behavior.dart';
import 'responsive_x.dart';

/// Full-bleed tab strip pinned directly under a dashboard's main header, as
/// a part of it: no gap, no rounded corners or shadow, just a flat
/// [backgroundColor] fill with a hairline [borderColor] along the bottom.
///
/// [child] is the row of tabs. It is laid out inside a horizontal scroll
/// view (at mobile widths the tab labels plus spacing don't fit the
/// viewport and must not shrink or wrap) and sits inset by [tabInset] from
/// the page's side padding (24px desktop, 16px mobile) — the same left edge
/// as the header's contents. Like the header, the strip is never capped at
/// 1440px: it always wraps 100% of the screen width. Give the row
/// `CrossAxisAlignment.stretch` so each tab's active indicator lands flush
/// on the strip's bottom edge.
///
/// [ScrollConfiguration]: Flutter's default ScrollBehavior excludes mouse
/// from dragDevices, which would otherwise leave overflowing tabs
/// unreachable for a desktop mouse user.
class DashboardSubNavStrip extends StatelessWidget {
  const DashboardSubNavStrip({
    super.key,
    required this.backgroundColor,
    required this.borderColor,
    required this.child,
    this.tabInset = 40,
  });

  /// Content height of the strip — the 1px bottom border is added below it.
  static const double height = 48;

  final Color backgroundColor;
  final Color borderColor;

  /// Extra inset of the first tab from the page's side padding.
  final double tabInset;

  /// The tab row.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final sideInset = context.isMobileWidth ? 16.0 : 24.0;
    return SizedBox(
      width: double.infinity,
      height: height + 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: backgroundColor,
          border: Border(bottom: BorderSide(color: borderColor)),
        ),
        child: ScrollConfiguration(
          behavior: mouseDraggableScrollBehavior,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: sideInset + tabInset),
            child: child,
          ),
        ),
      ),
    );
  }
}
