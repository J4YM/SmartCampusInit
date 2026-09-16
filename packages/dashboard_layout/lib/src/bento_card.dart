import 'package:flutter/material.dart';

import 'brightness_x.dart';

/// Rounded, softly-shadowed card shell — the shared "Bento UI" surface used
/// to visually group content across every dashboard module. Generalizes
/// `student_portal_module`'s `PortalSurfaceCard` (same 20px radius / border
/// / shadow recipe) with explicit `backgroundColor`/`borderColor` params
/// instead of a hardcoded color class, since each module still owns its own
/// per-page dark-mode color tokens rather than sharing one.
///
/// Reads `context.isDarkMode` by default for the shadow's opacity — safe
/// whenever the caller sits inside that module's own per-page `Theme`
/// wrapper, same as `PortalSurfaceCard`. Pass [isDarkMode] explicitly
/// instead when that doesn't hold — e.g. content rendered through
/// `showDialog`/`showMenu`'s own root-navigator Overlay (popovers, header
/// dialogs), which sits *outside* the per-page Theme, so `context.isDarkMode`
/// there would silently read the app's ambient (always-light) theme instead
/// of the page's actual toggle. Every dialog/popover in this app already
/// threads its own `isDarkMode` bool for exactly this reason — pass that
/// same value through here too.
class BentoCard extends StatelessWidget {
  const BentoCard({
    super.key,
    required this.child,
    required this.backgroundColor,
    required this.borderColor,
    this.padding,
    this.margin,
    this.borderRadius = 20,
    this.clipBehavior = Clip.none,
    this.elevated = true,
    this.isDarkMode,
  });

  final Widget child;
  final Color backgroundColor;
  final Color borderColor;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  /// Nested sub-cards (a card inside another `BentoCard`) should pass a
  /// smaller radius — e.g. 14 — and set [elevated] to `false` so shadows
  /// don't stack on top of the outer card's own shadow.
  final double borderRadius;

  /// Set to `Clip.antiAlias` when `child` contains its own scrolling
  /// content (e.g. a horizontally-scrollable tab strip) that would
  /// otherwise draw past the card's rounded corners.
  final Clip clipBehavior;

  /// `false` for a nested sub-card sitting inside another `BentoCard` —
  /// keeps the rounded/bordered surface but drops the drop-shadow, since a
  /// shadow-on-shadow stack reads as visual clutter rather than hierarchy.
  final bool elevated;

  /// Overrides `context.isDarkMode` for the shadow's opacity — see the class
  /// doc comment. Leave `null` for the normal in-page-Theme case.
  final bool? isDarkMode;

  @override
  Widget build(BuildContext context) {
    final dark = isDarkMode ?? context.isDarkMode;
    return Container(
      margin: margin,
      padding: padding,
      clipBehavior: clipBehavior,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: borderColor),
        boxShadow: elevated
            ? [
                BoxShadow(
                  color: Colors.black.withOpacity(dark ? 0.25 : 0.04),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: child,
    );
  }
}
