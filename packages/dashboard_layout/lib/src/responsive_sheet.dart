import 'package:flutter/material.dart';

import 'app_popup.dart';
import 'bento_card.dart';
import 'responsive_x.dart';

/// Shows [builder]'s content as a bottom sheet pinned to the bottom of the
/// viewport on mobile-width screens (below [kDashboardMobileBreakpoint]),
/// or as a centered, max-width-capped dialog on wider screens — one call
/// site, one responsive convention, instead of every dashboard/module
/// picking its own bottom-sheet-vs-dialog treatment.
///
/// A drag handle renders above the content only on the mobile bottom-sheet
/// path; corners are rounded on top only there, and on all four corners
/// for the desktop dialog. Both paths keep Flutter's own built-in
/// transitions and dismiss behavior — `showModalBottomSheet`'s slide-up +
/// swipe-to-dismiss + scrim, `showDialog`'s fade/scale + tap-outside-to-
/// dismiss + full-screen scrim — this only changes positioning and
/// framing, not how the route opens, closes, or returns its result.
Future<T?> showResponsiveSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  required Color backgroundColor,
  Color? handleColor,
  double desktopMaxWidth = 480,
  bool isScrollControlled = true,
}) {
  if (context.isMobileWidth) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      backgroundColor: backgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => _SheetHandle(
        color: handleColor,
        child: builder(sheetContext),
      ),
    );
  }

  // The desktop dialog is the same shell every other popup has (AppPopup's):
  // a transparent Dialog around a rounded, bordered, softly-shadowed card.
  final dark = backgroundColor.computeLuminance() < 0.5;
  return showDialog<T>(
    context: context,
    builder: (dialogContext) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: desktopMaxWidth),
        child: BentoCard(
          backgroundColor: backgroundColor,
          borderColor: AppPopupColors(dark).border,
          isDarkMode: dark,
          clipBehavior: Clip.antiAlias,
          child: builder(dialogContext),
        ),
      ),
    ),
  );

}

/// The mobile-only drag handle bar, drawn above the sheet's content —
/// never shown on the desktop dialog path, since [showResponsiveSheet]
/// only wraps content in this on the `showModalBottomSheet` branch.
class _SheetHandle extends StatelessWidget {
  const _SheetHandle({required this.child, this.color});

  final Widget child;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 4),
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: color ?? Colors.black26,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ),
        Flexible(child: child),
      ],
    );
  }
}
