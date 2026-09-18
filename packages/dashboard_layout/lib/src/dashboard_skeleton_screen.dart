import 'package:flutter/material.dart';

import 'bento_card.dart';
import 'dashboard_page_wrapper.dart';
import 'skeleton_loader.dart';

/// Generic full-page skeleton loading screen for a staff dashboard's
/// initial data fetch — a pulsing placeholder shaped like this app's common
/// dashboard layout (a row of stat tiles above a card full of list rows).
///
/// Drops in wherever a `*_connected_page.dart` host previously blocked on a
/// bare `CircularProgressIndicator` while its first Supabase fetch ran.
/// Not pixel-perfect for any one dashboard's real content — every dashboard
/// already follows this same stat-row + card-list shape closely enough
/// (see [BentoCard]) that one shared approximation reads correctly
/// everywhere instead of needing a bespoke skeleton per module.
///
/// Wrapped in the same [DashboardPageWrapper] every dashboard's real content
/// uses — capped at 1440px and centered on ultra-wide screens — so the
/// skeleton's width matches the content it's standing in for exactly, and
/// swapping from skeleton to real content on load doesn't shift layout.
class DashboardSkeletonScreen extends StatelessWidget {
  const DashboardSkeletonScreen({
    super.key,
    required this.backgroundColor,
    required this.cardColor,
    required this.cardBorderColor,
    required this.placeholderColor,
    this.statTileCount = 4,
    this.listRowCount = 6,
    this.useScaffold = true,
    this.wrapInPageFrame = true,
  });

  final Color backgroundColor;
  final Color cardColor;
  final Color cardBorderColor;

  /// Fill for every pulsing bar/circle — pass that dashboard's own muted
  /// "field fill"-style token (e.g. `DisciplineOfficerColors.gray`).
  final Color placeholderColor;

  final int statTileCount;
  final int listRowCount;

  /// `false` when the call site already sits inside an ambient `Scaffold`
  /// (e.g. a connected-page `build()` that returns a bare widget for its
  /// parent's `Scaffold.body`) — wrapping in a second `Scaffold` there would
  /// be redundant. Defaults to `true` since most loading-state call sites
  /// replace a page's entire `build()` and need to supply their own.
  final bool useScaffold;

  /// `false` when the call site is reused as a tab *inside* another
  /// dashboard's already-[DashboardPageWrapper]-framed page (e.g. a page
  /// embedded elsewhere, the same way [wrapInPageFrame]-style params work
  /// on the real content it stands in for) — skips this widget's own
  /// [DashboardPageWrapper] so the loading skeleton isn't capped/padded
  /// twice (which made it visibly narrower than the host's own sub-nav
  /// bar). Defaults to `true`, unchanged for every standalone usage.
  final bool wrapInPageFrame;

  @override
  Widget build(BuildContext context) {
    final body = SafeArea(
      child: SkeletonPulse(
        builder: (context, opacity) {
          final content = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth < 700
                      ? 2
                      : statTileCount.clamp(1, 4);
                  const gap = 16.0;
                  final tileWidth =
                      (constraints.maxWidth - gap * (columns - 1)) / columns;
                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (var i = 0; i < statTileCount; i++)
                        SizedBox(
                          width: tileWidth,
                          child: BentoCard(
                            backgroundColor: cardColor,
                            borderColor: cardBorderColor,
                            padding: const EdgeInsets.all(18),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SkeletonBox(
                                  color: placeholderColor,
                                  opacity: opacity,
                                  width: 64,
                                  height: 10,
                                ),
                                const SizedBox(height: 12),
                                SkeletonBox(
                                  color: placeholderColor,
                                  opacity: opacity,
                                  width: 40,
                                  height: 22,
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 20),
              BentoCard(
                backgroundColor: cardColor,
                borderColor: cardBorderColor,
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < listRowCount; i++) ...[
                      Row(
                        children: [
                          SkeletonCircle(
                            color: placeholderColor,
                            opacity: opacity,
                            diameter: 36,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SkeletonBox(
                                  color: placeholderColor,
                                  opacity: opacity,
                                  width: 180,
                                  height: 12,
                                ),
                                const SizedBox(height: 8),
                                SkeletonBox(
                                  color: placeholderColor,
                                  opacity: opacity,
                                  width: 110,
                                  height: 10,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (i != listRowCount - 1) const SizedBox(height: 18),
                    ],
                  ],
                ),
              ),
            ],
          );

          if (!wrapInPageFrame) return content;
          return SingleChildScrollView(
            child: DashboardPageWrapper(child: content),
          );
        },
      ),
    );

    if (!useScaffold) return body;
    return Scaffold(backgroundColor: backgroundColor, body: body);
  }
}
