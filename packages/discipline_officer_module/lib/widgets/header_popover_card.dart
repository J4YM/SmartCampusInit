import 'dart:math' as math;

import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Light grey divider used to separate a popover's header from its body,
/// distinct from a list's own row dividers.
const popoverDividerColor = Color(0xFFF1F5F9);

/// Shared header-dropdown chrome — every header popover (Notifications,
/// Settings, Account, …) is built from [HeaderPopoverCard] +
/// [PopoverHeaderBar] so they stay visually identical across modules: same
/// surface, radius, shadow, width, and header/divider style.
///
/// Note: this shell is only reached today via `SettingsPopover`, which isn't
/// wired to any header button — it's still made theme-aware for whenever
/// that changes. Unlike the actively-used popovers in this package, callers
/// of this widget don't thread an explicit `isDarkMode` through, so this
/// relies on `context.isDarkMode`.
class HeaderPopoverCard extends StatelessWidget {
  const HeaderPopoverCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 360,
        constraints: const BoxConstraints(maxHeight: 440),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: context.isDarkMode ? const Color(0xFF16191D) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 16,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: child,
      ),
    );
  }
}

class PopoverHeaderBar extends StatelessWidget {
  const PopoverHeaderBar({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 12, 16),
      child: Row(
        children: [
          Text(
            title,
            style: GoogleFonts.poppins(
              fontSize: context.isMobileWidth ? 14 : 16,
              fontWeight: FontWeight.w700,
              color: context.isDarkMode
                  ? const Color(0xFFF1F5F9)
                  : const Color(0xFF1E293B),
            ),
          ),
          const Spacer(),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Opens [contentBuilder] as a fixed-position dropdown just below a header's
/// action icons. Every module's Notifications/Settings/Account button calls
/// this rather than anchoring to its own trigger icon's `RenderBox`, so
/// every popover lands at the same spot and stays pixel-identical across
/// modules. `contentBuilder` gets a [StateSetter] so callers can rebuild
/// their popover in place (e.g. after "mark all as read") without closing
/// the overlay.
///
/// Set [centered] (mobile, once the header's icons have moved into
/// `AppBottomNavBar`) to instead show the popover centered on the screen —
/// the top-right anchor math below assumes the trigger lives in the top
/// header, which reads as oddly disconnected when it's actually triggered
/// from the bottom nav bar.
///
/// Set [anchorAboveBottomNav] instead to anchor bottom-right, just above
/// `AppBottomNavBar`, near its rightmost (Profile) item — used for the
/// profile popover specifically, which benefits from staying visually
/// tethered to the icon that opened it rather than jumping to the center.
/// [centered] and [anchorAboveBottomNav] are mutually exclusive; if both are
/// set, [centered] wins.
Future<void> showHeaderPopover({
  required BuildContext context,
  required Widget Function(BuildContext context, StateSetter setPopoverState)
      contentBuilder,
  double topMargin = 72,
  double? rightMargin,
  double cardWidth = 360,
  bool centered = false,
  bool anchorAboveBottomNav = false,
}) {
  if (centered || anchorAboveBottomNav) {
    // Align/Padding, not a showMenu RelativeRect: RelativeRect anchors to
    // the *top* of whatever rect it's given regardless of how its bottom
    // margin is set, so it can't express "flush to the bottom" for a
    // variable-height popover — Align can, independent of content height.
    return showGeneralDialog<void>(
      context: context,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black54,
      barrierDismissible: true,
      transitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return Align(
          alignment: centered ? Alignment.center : Alignment.bottomRight,
          child: Padding(
            padding: anchorAboveBottomNav
                ? EdgeInsets.only(
                    right: 16,
                    // AppBottomNavBar's own fixed 65px content height, plus
                    // its SafeArea bottom inset, plus a small gap so the
                    // popover sits just above the bar instead of touching
                    // it.
                    bottom: 65 + MediaQuery.of(dialogContext).padding.bottom + 12,
                  )
                : EdgeInsets.zero,
            child: Material(
              color: Colors.transparent,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: cardWidth),
                child: StatefulBuilder(builder: contentBuilder),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (dialogContext, animation, secondaryAnimation, child) {
        return FadeTransition(opacity: animation, child: child);
      },
    );
  }

  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;

  // AppHeaderNavBar itself is full-bleed (no outer margin), but its content
  // is centered and capped at a 1440px width with 24px of inner padding.
  // Past 1440px wide, that content's right edge moves in from the screen
  // edge by half the leftover space, so the popover has to track the same
  // math to stay anchored under the header's action icons instead of
  // drifting into the empty navy margin beside them.
  final resolvedRightMargin =
      rightMargin ?? 24 + math.max(0.0, (overlay.size.width - 1440) / 2);

  final position = RelativeRect.fromLTRB(
    overlay.size.width - resolvedRightMargin - cardWidth,
    topMargin,
    resolvedRightMargin,
    0,
  );

  return showMenu<void>(
    context: context,
    position: position,
    color: Colors.transparent,
    shadowColor: Colors.transparent,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    shape: const RoundedRectangleBorder(),
    menuPadding: EdgeInsets.zero,
    constraints: const BoxConstraints(),
    items: [
      PopupMenuItem<void>(
        enabled: false,
        padding: EdgeInsets.zero,
        child: StatefulBuilder(builder: contentBuilder),
      ),
    ],
  );
}
