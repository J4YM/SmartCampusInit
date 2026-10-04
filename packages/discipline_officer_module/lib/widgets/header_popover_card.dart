
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
      child: SizedBox(
        width: 360,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 440),
          child: BentoCard(
            backgroundColor:
                context.isDarkMode ? const Color(0xFF191A1F) : Colors.white,
            borderColor: context.isDarkMode
                ? const Color(0xFF22242B)
                : const Color(0x0D000000),
            clipBehavior: Clip.antiAlias,
            child: child,
          ),
        ),
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
                  ? const Color(0xFFF5F5F5)
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
///
/// By default (none of the flags above) the popover is anchored top-right,
/// [topMargin] below the top of the screen with its right edge [rightMargin]
/// (24px — the header's own side padding — unless overridden) in from the
/// screen's right edge, so it tracks the header's action icons at any window
/// width. Every main header's contents span 100% of the screen width (staff
/// dashboards and the Student/Parent portals alike), so no width-dependent
/// offset is needed.
///
/// Every anchor uses an Align+Padding dialog rather than `showMenu`: the
/// popup route behind `showMenu`/`RelativeRect` renders its menu roughly 48px
/// further left than the rect it is given, so the popover visibly missed
/// landing under its trigger icons. Align+Padding is exact at every width,
/// and (unlike a `RelativeRect`) can express "flush to the bottom" for a
/// variable-height popover.
///
/// The page behind a popover is never dimmed or darkened, whichever anchor is
/// used — the transparent barrier only exists to catch the tap that dismisses it.
/// [centered], [anchorAboveBottomNav], and [anchorTopRight] are mutually
/// exclusive; if more than one is set, [centered] wins, then
/// [anchorAboveBottomNav].
Future<void> showHeaderPopover({
  required BuildContext context,
  required Widget Function(BuildContext context, StateSetter setPopoverState)
      contentBuilder,
  double topMargin = 72,
  double? rightMargin,
  double cardWidth = 360,
  bool centered = false,
  bool anchorAboveBottomNav = false,
  bool anchorTopRight = false,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierLabel: 'Dismiss',
    barrierColor: Colors.transparent,
    barrierDismissible: true,
    transitionDuration: const Duration(milliseconds: 150),
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      final Alignment alignment;
      final EdgeInsets padding;
      if (centered) {
        alignment = Alignment.center;
        padding = EdgeInsets.zero;
      } else if (anchorAboveBottomNav) {
        alignment = Alignment.bottomRight;
        padding = EdgeInsets.only(
          right: 16,
          // AppBottomNavBar's own fixed 65px content height, plus its
          // SafeArea bottom inset, plus a small gap so the popover sits
          // just above the bar instead of touching it.
          bottom: 65 + MediaQuery.of(dialogContext).padding.bottom + 12,
        );
      } else {
        alignment = Alignment.topRight;
        padding = EdgeInsets.only(top: topMargin, right: rightMargin ?? 24);
      }
      return Align(
        alignment: alignment,
        child: Padding(
          padding: padding,
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
