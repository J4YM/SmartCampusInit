import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/notification_item_model.dart';
import 'header_popover_card.dart';

/// Notifications dropdown anchored below a header's bell icon via
/// [showHeaderPopover]. Shared by every module so the empty/list/footer
/// states stay visually identical.
class NotificationsPopover extends StatelessWidget {
  const NotificationsPopover({
    super.key,
    required this.notifications,
    required this.onMarkAllRead,
    required this.onViewAll,
    this.accentColor = const Color(0xFF2563EB),
  });

  final List<NotificationItemModel> notifications;
  final VoidCallback onMarkAllRead;
  final VoidCallback onViewAll;

  /// Tint for unread dots and the active "Mark all as read" label —
  /// defaults to the Discipline Officer module's blue; pass a module's own
  /// accent to match its brand instead.
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final unreadCount = notifications.where((n) => !n.isRead).length;

    return HeaderPopoverCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PopoverHeaderBar(
            title: 'Notifications',
            trailing: TextButton(
              onPressed: unreadCount == 0 ? null : onMarkAllRead,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                'Mark all as read',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: unreadCount == 0 ? const Color(0xFFCBD5E1) : accentColor,
                ),
              ),
            ),
          ),
          const Divider(height: 1, color: popoverDividerColor),
          Flexible(
            child: notifications.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 36),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.notifications_none_rounded,
                          size: 36,
                          color: Color(0xFFCBD5E1),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'No new notifications',
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: notifications.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1, color: Color(0xFFE2E8F0)),
                    itemBuilder: (context, index) {
                      return _NotificationTile(
                        item: notifications[index],
                        accentColor: accentColor,
                      );
                    },
                  ),
          ),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: onViewAll,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
                ),
              ),
              child: Text(
                'View All Notifications',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: accentColor,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.item, required this.accentColor});

  final NotificationItemModel item;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      color: item.isRead ? Colors.transparent : const Color(0xFFEFF6FF),
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
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.message,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: const Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _timeAgoLabel(item.timestamp),
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                    color: const Color(0xFFCBD5E1),
                  ),
                ),
              ],
            ),
          ),
        ],
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
