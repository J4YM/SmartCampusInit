import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Full-width header bar above [MainContentArea], to the right of the
/// [Sidebar]. Unlike the other dashboard modules' navy [AppHeaderNavBar],
/// this stays a plain light bar with no title — it exists only to host the
/// sidebar's collapse toggle on the left plus the admin's notification,
/// email, and report-issue actions on the right.
class AdminTopNavBar extends StatelessWidget {
  const AdminTopNavBar({
    super.key,
    required this.onMenuTap,
    this.unreadNotificationCount = 0,
    this.onNotificationsTap,
    this.onEmailTap,
    this.onReportIssueTap,
  });

  /// Toggles the sidebar between its full width and icon-only rail.
  final VoidCallback onMenuTap;

  final int unreadNotificationCount;
  final VoidCallback? onNotificationsTap;
  final VoidCallback? onEmailTap;

  /// Opens the shared technical-issue report dialog when supplied. Falls
  /// back to no icon at all when omitted. Rendered as the rightmost action,
  /// just past the email icon.
  final VoidCallback? onReportIssueTap;

  static const double _horizontalPadding = 16;
  static const double _iconButtonSize = 38; // 22px icon + 8px padding * 2
  static const double _iconGap = 4;

  /// Distance from this bar's true right edge to the right edge of the
  /// action icon that is [positionFromRight] slots in from whichever icon
  /// currently renders rightmost (0 = that icon itself, 1 = the one before
  /// it, …). Callers anchoring a `showHeaderPopover` (e.g. the notification
  /// bell, which isn't always the rightmost icon once report-issue is
  /// shown) pass this as `rightMargin` so the popover lands under the
  /// correct icon regardless of which optional actions are present.
  static double rightMarginForIcon(int positionFromRight) =>
      _horizontalPadding + positionFromRight * (_iconButtonSize + _iconGap);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.topNavBackground(context),
        border: Border(
          bottom: BorderSide(color: AppColors.topNavBorder(context)),
        ),
      ),
      child: Row(
        children: [
          _TopNavIconButton(
            icon: Icons.menu_rounded,
            tooltip: 'Toggle sidebar',
            onTap: onMenuTap,
          ),
          const Spacer(),
          if (onNotificationsTap != null)
            _TopNavIconButton(
              icon: Icons.notifications_none_rounded,
              tooltip: 'Notifications',
              badgeCount: unreadNotificationCount,
              onTap: onNotificationsTap!,
            ),
          if (onEmailTap != null) ...[
            const SizedBox(width: 4),
            _TopNavIconButton(
              icon: Icons.mail_outline_rounded,
              tooltip: 'Email',
              onTap: onEmailTap!,
            ),
          ],
          if (onReportIssueTap != null) ...[
            const SizedBox(width: 4),
            _TopNavIconButton(
              icon: Icons.build_outlined,
              tooltip: 'Report Technical Issue',
              onTap: onReportIssueTap!,
            ),
          ],
        ],
      ),
    );
  }
}

class _TopNavIconButton extends StatelessWidget {
  const _TopNavIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.badgeCount = 0,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(10),
              hoverColor: AppColors.topNavIconHover(context),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(
                  icon,
                  size: 22,
                  color: AppColors.topNavIcon(context),
                ),
              ),
            ),
          ),
          if (badgeCount > 0)
            Positioned(
              right: 2,
              top: 2,
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFCD4855),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  constraints: const BoxConstraints(minWidth: 15, minHeight: 15),
                  child: Text(
                    badgeCount > 99 ? '99+' : '$badgeCount',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
