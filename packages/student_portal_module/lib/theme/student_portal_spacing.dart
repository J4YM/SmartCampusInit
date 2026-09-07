import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/widgets.dart';

/// Shared spacing/layout tokens so every tab uses the same scale and the
/// same 1440px content cap every other dashboard module uses
/// (`DashboardPageWrapper`'s default `maxWidth`).
abstract final class StudentPortalSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;

  /// Same cap as every other dashboard's `DashboardPageWrapper`.
  static const double maxContentWidth = 1440;

  /// Page-edge horizontal gutter — tightens on mobile-width viewports,
  /// matches the 24px every other dashboard uses once there's room.
  static double pageHorizontal(BuildContext context) =>
      context.isMobileWidth ? lg : xxl;

  /// Two-column layouts (Overview's violations/messages split, Attendance's
  /// calendar/detail split, the Violations/Messages masonry) collapse to a
  /// single stacked column below this width — same breakpoint
  /// `dashboard_layout` uses everywhere else.
  static bool isCompact(BuildContext context) => context.isMobileWidth;
}
