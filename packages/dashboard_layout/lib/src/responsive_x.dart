import 'package:flutter/material.dart';

/// Width below which every dashboard module (Discipline Officer, Guidance
/// Counselor, Professor, …) switches from the desktop header — with its
/// inline notification/profile icons — to [AppBottomNavBar] carrying
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

/// Shortest content area (below the fixed header) a viewport-filling page
/// is laid out at — a shorter window scrolls the page instead of squeezing
/// its cards any further.
const double kDashboardMinFillHeight = 640;

/// A dashboard page's vertical scroll view (the area below the fixed
/// header). With [fill] true, [child] is laid out at exactly the viewport's
/// height, floored at [minHeight], so a master-detail row can `Expanded`
/// into whatever space is left — the page fits the window with no scroll
/// and only scrolls once the window gets shorter than [minHeight]. With
/// [fill] false it's a plain scroll view sized by its content.
class DashboardPageScrollView extends StatelessWidget {
  const DashboardPageScrollView({
    super.key,
    required this.child,
    this.fill = false,
    this.minHeight = kDashboardMinFillHeight,
  });

  final Widget child;
  final bool fill;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, viewport) => _DashboardViewportScope(
        height: viewport.maxHeight,
        child: SingleChildScrollView(
          child: fill
              ? SizedBox(
                  height: viewport.maxHeight < minHeight
                      ? minHeight
                      : viewport.maxHeight,
                  child: child,
                )
              : child,
        ),
      ),
    );
  }
}

/// Publishes the visible height of the enclosing [DashboardPageScrollView]
/// — see [ResponsiveX.dashboardViewportHeight].
class _DashboardViewportScope extends InheritedWidget {
  const _DashboardViewportScope({required this.height, required super.child});

  final double height;

  @override
  bool updateShouldNotify(_DashboardViewportScope old) => old.height != height;
}

/// Sizes a desktop master-detail `Row`: when the page gives it a bounded
/// height (a [DashboardPageScrollView] with `fill: true` and an `Expanded`
/// tab body) it takes all of it; otherwise it falls back to
/// [ResponsiveX.masterDetailRowMaxHeight]'s viewport-based cap.
class MasterDetailRowFrame extends StatelessWidget {
  const MasterDetailRowFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => constraints.hasBoundedHeight
          ? child
          : ConstrainedBox(
              constraints:
                  BoxConstraints(maxHeight: context.masterDetailRowMaxHeight()),
              child: child,
            ),
    );
  }
}

/// Content width below which a desktop master-detail tab (a list card
/// beside a detail/side card) stacks the two cards instead.
const double kMasterDetailStackBreakpoint = 900;

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

  /// Visible height of the enclosing [DashboardPageScrollView] (the area
  /// under the fixed header), or the whole screen's height outside one.
  double get dashboardViewportHeight =>
      dependOnInheritedWidgetOfExactType<_DashboardViewportScope>()?.height ??
      MediaQuery.sizeOf(this).height;

  /// Whether a desktop master-detail tab shows its two cards side by side —
  /// the layout that fills the window (see [DashboardPageScrollView.fill]).
  /// The content width is [DashboardPageWrapper]'s default 1440 cap minus
  /// its 24px desktop side padding, compared against [stackBreakpoint] (the
  /// same width the tab's own LayoutBuilder stacks at).
  bool showsMasterDetailRow({
    double stackBreakpoint = kMasterDetailStackBreakpoint,
  }) {
    if (isMobileWidth) return false;
    final width = MediaQuery.sizeOf(this).width;
    return (width > 1440 ? 1440 : width) - 48 >= stackBreakpoint;
  }
}
