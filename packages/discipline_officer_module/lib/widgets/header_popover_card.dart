import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Light grey divider used to separate a popover's header from its body,
/// distinct from a list's own row dividers.
const popoverDividerColor = Color(0xFFF1F5F9);

/// Shared header-dropdown chrome — every header popover (Notifications,
/// Settings, Account, …) is built from [HeaderPopoverCard] +
/// [PopoverHeaderBar] so they stay visually identical across modules: same
/// surface, radius, shadow, width, and header/divider style.
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
          color: Colors.white,
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
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF1E293B),
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
Future<void> showHeaderPopover({
  required BuildContext context,
  required Widget Function(BuildContext context, StateSetter setPopoverState)
      contentBuilder,
  double topMargin = 72,
  double? rightMargin,
  double cardWidth = 360,
}) {
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
