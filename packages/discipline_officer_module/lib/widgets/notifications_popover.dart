import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/notification_item_model.dart';

/// Notifications dropdown anchored below a header's bell icon via
/// [showHeaderPopover] (Figma node 488:1106) — builds its own card chrome
/// (400px wide, 10px radius, bordered) rather than [HeaderPopoverCard]'s
/// 360px/16px shell, so every module's bell renders pixel-identical to the
/// design.
class NotificationsPopover extends StatelessWidget {
  const NotificationsPopover({
    super.key,
    required this.notifications,
    required this.onViewAll,
    required this.onMarkAllRead,
    this.accentColor = const Color(0xFF2563EB),
    this.isDarkMode = false,
  });

  final List<NotificationItemModel> notifications;

  /// Navigates to the full Notifications list page — no longer also marks
  /// everything read as a side effect (see [onMarkAllRead]).
  final VoidCallback onViewAll;

  /// Bulk-marks every notification read, independent of [onViewAll].
  final VoidCallback onMarkAllRead;

  /// Tint for each item's unread dot — defaults to the Discipline Officer
  /// module's blue; pass a module's own accent to match its brand instead.
  final Color accentColor;

  /// Rendered through `showMenu`'s own Overlay/route (see
  /// `showHeaderPopover`), which sits outside the dashboard page's local
  /// per-page Theme — so `context.isDarkMode` here would read the app's
  /// ambient theme, not the page's toggle. Threaded in explicitly instead
  /// (same pattern as `AccountProfileMenu`).
  final bool isDarkMode;

  @override
  Widget build(BuildContext context) {
    final cardColor = isDarkMode ? const Color(0xFF191A1F) : Colors.white;
    final borderColor =
        isDarkMode ? const Color(0xFF22242B) : const Color(0x0D000000);
    final primaryText = isDarkMode ? const Color(0xFFF5F5F5) : Colors.black;

    return Material(
      color: Colors.transparent,
      child: Container(
        width: 400,
        height: 270,
        clipBehavior: Clip.antiAlias,
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: borderColor),
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: borderColor)),
              ),
              child: Text(
                'Notifications',
                style: GoogleFonts.poppins(
                  fontSize: context.isMobileWidth ? 14 : 16,
                  fontWeight: FontWeight.w500,
                  color: primaryText,
                ),
              ),
            ),
            Expanded(
              child: notifications.isEmpty
                  ? Center(
                      child: Text(
                        'No Notifications',
                        style: GoogleFonts.poppins(
                          fontSize: context.isMobileWidth ? 14 : 16,
                          fontWeight: FontWeight.w500,
                          color: primaryText,
                        ),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      itemCount: notifications.length,
                      separatorBuilder: (context, index) => Divider(
                          height: 1,
                          color: isDarkMode
                              ? const Color(0xFF2E313A)
                              : const Color(0xFFE2E8F0)),
                      itemBuilder: (context, index) {
                        return _NotificationTile(
                          item: notifications[index],
                          accentColor: accentColor,
                          isDarkMode: isDarkMode,
                        );
                      },
                    ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.only(top: 10),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: borderColor)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: InkWell(
                      onTap: onViewAll,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          'View all notifications',
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                            fontSize: context.isMobileWidth ? 11 : 13,
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFF345892),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: InkWell(
                      onTap: onMarkAllRead,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          'Mark all as read',
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.end,
                          style: GoogleFonts.poppins(
                            fontSize: context.isMobileWidth ? 11 : 13,
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFF345892),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.item,
    required this.accentColor,
    required this.isDarkMode,
  });

  final NotificationItemModel item;
  final Color accentColor;
  final bool isDarkMode;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => showMailboxDetailDialog(
        context,
        kicker: 'Notification',
        subject: item.title,
        body: item.message,
        timestamp: item.timestamp,
        isDarkMode: isDarkMode,
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        color: item.isRead
            ? Colors.transparent
            : (isDarkMode ? const Color(0x295B8DEF) : const Color(0xFFEFF6FF)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: item.isRead ? Colors.transparent : accentColor,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: GoogleFonts.poppins(
                      fontSize: context.isMobileWidth ? 11 : 13,
                      fontWeight: FontWeight.w600,
                      color: isDarkMode
                          ? const Color(0xFFF5F5F5)
                          : const Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.message,
                    style: GoogleFonts.poppins(
                      fontSize: context.isMobileWidth ? 10 : 12,
                      fontWeight: FontWeight.w400,
                      color: isDarkMode
                          ? const Color(0xFFA1A1AA)
                          : const Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _timeAgoLabel(item.timestamp),
                    style: GoogleFonts.poppins(
                      fontSize: context.isMobileWidth ? 9 : 11,
                      fontWeight: FontWeight.w400,
                      color: isDarkMode
                          ? const Color(0xFF71717A)
                          : const Color(0xFFCBD5E1),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _timeAgoLabel(DateTime dateTime) {
  final diff = DateTime.now().difference(dateTime);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) {
    return '${diff.inMinutes} minute${diff.inMinutes == 1 ? '' : 's'} ago';
  }
  if (diff.inHours < 24) {
    return '${diff.inHours} hour${diff.inHours == 1 ? '' : 's'} ago';
  }
  return '${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
}
