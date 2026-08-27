import 'package:flutter/material.dart';

/// Width below which every dashboard module (Discipline Officer, Guidance
/// Counselor, Professor, …) switches from the desktop header — with its
/// inline email/notification/profile icons — to [AppBottomNavBar] carrying
/// those same actions. Matches `AppDimensions.responsiveBreakpoint` in
/// login_module so the app switches layouts at a consistent width.
const double kDashboardMobileBreakpoint = 800;

extension ResponsiveX on BuildContext {
  bool get isMobileWidth =>
      MediaQuery.of(this).size.width < kDashboardMobileBreakpoint;

  /// Height cap for a master-detail row (a queue/list "sidebar" beside a
  /// detail/preview panel, e.g. the Violation Queue) so the pair never
  /// grows past roughly one viewport — [chromeOffset] should approximate
  /// whatever's already stacked above the row (page header, stat cards,
  /// etc.) so the row plus that chrome doesn't overflow past the fold.
  /// Floored at 400 so a very short viewport still gets a usable height
  /// rather than a near-zero or negative constraint.
  double masterDetailRowMaxHeight({double chromeOffset = 140}) {
    return (MediaQuery.sizeOf(this).height - chromeOffset)
        .clamp(400.0, double.infinity);
  }
}
