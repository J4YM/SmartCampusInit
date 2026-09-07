import 'package:flutter/material.dart';

/// Width below which every dashboard module (Discipline Officer, Guidance
/// Counselor, Professor, …) switches from the desktop header — with its
/// inline email/notification/profile icons — to [AppBottomNavBar] carrying
/// those same actions. Matches `AppDimensions.responsiveBreakpoint` in
/// login_module so the app switches layouts at a consistent width.
const double kDashboardMobileBreakpoint = 800;

/// Width below which a paginated card/table drops to a denser row count
/// (see [ResponsiveX.cardPageSize]) — deliberately narrower than
/// [kDashboardMobileBreakpoint] (which governs layout stacking): a device
/// between 600 and 800px already gets the stacked mobile layout but still
/// has room to show the full row count, so it isn't worth thinning out
/// until the viewport gets narrower still.
const double kPaginationMobileBreakpoint = 600;

extension ResponsiveX on BuildContext {
  bool get isMobileWidth =>
      MediaQuery.of(this).size.width < kDashboardMobileBreakpoint;

  /// Rows per page for a card's own client-side (or server-paged) list —
  /// 5 below [kPaginationMobileBreakpoint] so a paginated table never forces
  /// heavy scrolling just to reach its own footer or the next card on a
  /// phone, 10 at or above it. Every dashboard's paginated card/table should
  /// size its page through this getter instead of a bespoke ternary, so the
  /// density rule only ever needs tuning in one place.
  int get cardPageSize =>
      MediaQuery.sizeOf(this).width < kPaginationMobileBreakpoint ? 5 : 10;

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
