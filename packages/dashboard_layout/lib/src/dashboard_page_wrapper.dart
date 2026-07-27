import 'package:flutter/material.dart';

/// Standard max-width framing shared by every dashboard module's root page
/// (Admin, Discipline Officer, Guidance Counselor, …).
///
/// Wraps a module's secondary tab bar + main content area — **not** the
/// full-bleed navy top header, which stays outside this widget and spans
/// 100% of the viewport on its own.
///
/// - Wider than [maxWidth]: the wrapped content is horizontally centered and
///   top-aligned, capped at [maxWidth], so cards/charts/sidebar queues don't
///   stretch into distorted whitespace on ultra-wide monitors.
/// - [maxWidth] or narrower: [ConstrainedBox] imposes no cap at all, so the
///   content just expands to fill the available width as normal.
class DashboardPageWrapper extends StatelessWidget {
  const DashboardPageWrapper({
    super.key,
    required this.child,
    this.maxWidth = 1440,
    this.padding = const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}
