import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/notification_item_model.dart';
import '../../widgets/mailbox_list_scaffold.dart';

/// "View all notifications" content, shown in place of whatever sub-nav tab
/// was active when the header bell popover's "View all notifications" link
/// is tapped (Figma node 565:1582's table/toolbar layout) — the dashboard's
/// own header and sub-nav bar stay visible throughout, exactly like
/// switching a normal tab; this widget renders only the content card.
class NotificationsListView extends StatefulWidget {
  const NotificationsListView({
    super.key,
    required this.notifications,
    this.isDarkMode = false,
  });

  final List<NotificationItemModel> notifications;

  /// Rendered inside the dashboard's own body, which sits under that page's
  /// local per-page `Theme` — but popovers/dialogs opened from a row here
  /// (`showMailboxDetailDialog`) go through their own root-navigator route,
  /// which does NOT inherit that Theme. Threaded in explicitly instead
  /// (same pattern as every popover/dialog in this app).
  final bool isDarkMode;

  @override
  State<NotificationsListView> createState() => _NotificationsListViewState();
}

class _NotificationsListViewState extends State<NotificationsListView> {
  // Mark-as-read/unread and Delete below are LOCAL, in-memory only — no
  // NotificationsRepository method exists for per-item mutation (only
  // markAllReadForRole exists), and none is added here. Switching away and
  // back to this view shows the original, unmutated list again.
  late List<NotificationItemModel> _items = List.of(widget.notifications);

  final _searchController = TextEditingController();
  final Set<String> _selectedIds = {};
  int _page = 1;
  static const _pageSize = 10;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<NotificationItemModel> get _filtered {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _items;
    return _items
        .where((n) =>
            n.title.toLowerCase().contains(query) ||
            n.message.toLowerCase().contains(query))
        .toList();
  }

  List<NotificationItemModel> get _paged {
    final filtered = _filtered;
    final start = (_page - 1) * _pageSize;
    if (start >= filtered.length) return const [];
    return filtered.skip(start).take(_pageSize).toList();
  }

  int get _totalPages =>
      _filtered.isEmpty ? 1 : (_filtered.length / _pageSize).ceil();

  void _toggleSelectAll(bool selectAll) {
    setState(() {
      if (selectAll) {
        _selectedIds.addAll(_paged.map((n) => n.id));
      } else {
        _selectedIds.removeAll(_paged.map((n) => n.id));
      }
    });
  }

  void _markSelected(bool read) {
    setState(() {
      _items = _items
          .map((n) =>
              _selectedIds.contains(n.id) ? n.copyWith(isRead: read) : n)
          .toList();
      _selectedIds.clear();
    });
  }

  void _deleteSelected() {
    setState(() {
      _items.removeWhere((n) => _selectedIds.contains(n.id));
      _selectedIds.clear();
      if (_page > _totalPages) _page = _totalPages;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MailboxListCard(
      title: 'Notifications',
      isDarkMode: widget.isDarkMode,
      searchController: _searchController,
      onSearchChanged: (_) => setState(() => _page = 1),
      hasSelection: _selectedIds.isNotEmpty,
      onMarkRead: () => _markSelected(true),
      onMarkUnread: () => _markSelected(false),
      onDelete: _deleteSelected,
      headerColumns: const ['Notification', 'Date & Time', 'Status'],
      allSelected: _paged.isNotEmpty &&
          _paged.every((n) => _selectedIds.contains(n.id)),
      onSelectAll: _toggleSelectAll,
      currentPage: _page,
      totalPages: _totalPages,
      totalCount: _filtered.length,
      onPreviousPage: _page > 1 ? () => setState(() => _page--) : null,
      onNextPage: _page < _totalPages ? () => setState(() => _page++) : null,
      emptyLabel: 'No Notifications',
      rows: [
        for (final item in _paged)
          MailboxListRow(
            key: ValueKey(item.id),
            selected: _selectedIds.contains(item.id),
            isRead: item.isRead,
            timestamp: item.timestamp,
            isDarkMode: widget.isDarkMode,
            onSelectedChanged: (v) => setState(() {
              if (v) {
                _selectedIds.add(item.id);
              } else {
                _selectedIds.remove(item.id);
              }
            }),
            onTap: () => showMailboxDetailDialog(
              context,
              kicker: 'Notification',
              subject: item.title,
              body: item.message,
              timestamp: item.timestamp,
              isDarkMode: widget.isDarkMode,
            ),
            primaryCell: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: MailboxColors.primaryText(widget.isDarkMode),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.message,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: MailboxColors.secondaryText(widget.isDarkMode),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
