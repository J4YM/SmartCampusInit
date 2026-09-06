import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Shared chrome for [NotificationsListView]/[EmailListView] — title, search
/// + bulk-action toolbar, navy table header row, and pagination footer.
/// Extracted here (rather than duplicated per view) because the two "View
/// all" list views are otherwise near-identical, same reasoning as
/// [CardPaginationFooter]'s own extraction. Each view still owns its own
/// data/selection/search state and row content — this widget only renders
/// the card shell around pre-built [rows].
///
/// Renders as a plain content card (no `Scaffold`, no back button) — it's
/// embedded directly below the dashboard's own header + sub-nav bar in
/// place of whatever tab was showing, exactly like switching a normal
/// sub-nav tab, rather than opening as a separate full-screen route.
// Dark-mode values below use the app-wide neutral near-black palette
// (0E0E0E background, 191A1F cards, 22242B/2E313A borders, F5F5F5/
// A1A1AA/71717A text) — light mode is untouched.
abstract final class MailboxColors {
  static Color background(bool isDarkMode) =>
      isDarkMode ? const Color(0xFF0E0E0E) : const Color(0xFFF0F5F8);
  static Color card(bool isDarkMode) =>
      isDarkMode ? const Color(0xFF191A1F) : Colors.white;
  static Color border(bool isDarkMode) =>
      isDarkMode ? const Color(0xFF22242B) : const Color(0x0D000000);
  static Color primaryText(bool isDarkMode) =>
      isDarkMode ? const Color(0xFFF5F5F5) : const Color(0xFF1E293B);
  static Color secondaryText(bool isDarkMode) =>
      isDarkMode ? const Color(0xFFA1A1AA) : const Color(0xFF64748B);
  static Color fieldFill(bool isDarkMode) =>
      isDarkMode ? const Color(0xFF0E0E0E) : const Color(0xFFF0F5F8);
  static const primaryButton = Color(0xFF345892);
  static const navyHeader = Color(0xFF15253F);
}

class MailboxListCard extends StatelessWidget {
  const MailboxListCard({
    super.key,
    required this.title,
    required this.isDarkMode,
    required this.searchController,
    required this.onSearchChanged,
    required this.hasSelection,
    required this.onMarkRead,
    required this.onMarkUnread,
    required this.onDelete,
    required this.headerColumns,
    required this.allSelected,
    required this.onSelectAll,
    required this.currentPage,
    required this.totalPages,
    required this.totalCount,
    required this.onPreviousPage,
    required this.onNextPage,
    required this.emptyLabel,
    required this.rows,
  });

  final String title;
  final bool isDarkMode;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final bool hasSelection;
  final VoidCallback onMarkRead;
  final VoidCallback onMarkUnread;
  final VoidCallback onDelete;

  /// Exactly 3 column labels for the navy header row (leading checkbox
  /// column is implicit).
  final List<String> headerColumns;
  final bool allSelected;
  final ValueChanged<bool> onSelectAll;
  final int currentPage;
  final int totalPages;
  final int totalCount;
  final VoidCallback? onPreviousPage;
  final VoidCallback? onNextPage;
  final String emptyLabel;
  final List<MailboxListRow> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: MailboxColors.card(isDarkMode),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: MailboxColors.border(isDarkMode)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              title,
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: MailboxColors.primaryText(isDarkMode),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 260,
                  child: TextField(
                    controller: searchController,
                    onChanged: onSearchChanged,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      color: MailboxColors.primaryText(isDarkMode),
                    ),
                    decoration: InputDecoration(
                      hintText: 'Search',
                      hintStyle: GoogleFonts.poppins(
                        fontSize: 13,
                        color: MailboxColors.secondaryText(isDarkMode),
                      ),
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        size: 20,
                        color: MailboxColors.secondaryText(isDarkMode),
                      ),
                      isDense: true,
                      filled: true,
                      fillColor: MailboxColors.fieldFill(isDarkMode),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                MailboxActionPillButton(
                  label: 'Mark as read',
                  icon: Icons.done_all_rounded,
                  isDarkMode: isDarkMode,
                  solid: false,
                  onTap: hasSelection ? onMarkRead : null,
                ),
                MailboxActionPillButton(
                  label: 'Mark as unread',
                  icon: Icons.remove_done_rounded,
                  isDarkMode: isDarkMode,
                  solid: false,
                  onTap: hasSelection ? onMarkUnread : null,
                ),
                MailboxActionPillButton(
                  label: 'Delete',
                  icon: Icons.delete_outline_rounded,
                  isDarkMode: isDarkMode,
                  solid: true,
                  onTap: hasSelection ? onDelete : null,
                ),
              ],
            ),
          ),
          Container(
            color: MailboxColors.navyHeader,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                SizedBox(
                  width: 32,
                  child: Checkbox(
                    value: allSelected,
                    onChanged: (v) => onSelectAll(v ?? false),
                    fillColor: WidgetStateProperty.all(Colors.white),
                    checkColor: MailboxColors.navyHeader,
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(headerColumns[0], style: _headerStyle),
                ),
                Expanded(
                  flex: 2,
                  child: Text(headerColumns[1], style: _headerStyle),
                ),
                Expanded(child: Text(headerColumns[2], style: _headerStyle)),
              ],
            ),
          ),
          if (rows.isEmpty)
            SizedBox(
              height: 160,
              child: Center(
                child: Text(
                  emptyLabel,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: MailboxColors.secondaryText(isDarkMode),
                  ),
                ),
              ),
            )
          else
            // shrinkWrap + NeverScrollableScrollPhysics — this card sits
            // inside the dashboard's own outer SingleChildScrollView, so the
            // row list sizes to its (already-paginated, small) content
            // instead of trying to scroll independently.
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: rows.length,
              separatorBuilder: (_, __) => Divider(
                height: 1,
                color: MailboxColors.border(isDarkMode),
              ),
              itemBuilder: (_, i) => rows[i],
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: CardPaginationFooter(
              currentPage: currentPage,
              totalPages: totalPages,
              totalCount: totalCount,
              textColor: MailboxColors.secondaryText(isDarkMode),
              accentColor: MailboxColors.primaryButton,
              mutedBackground: MailboxColors.fieldFill(isDarkMode),
              onPrevious: onPreviousPage,
              onNext: onNextPage,
            ),
          ),
        ],
      ),
    );
  }

  TextStyle get _headerStyle => GoogleFonts.poppins(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      );
}

class MailboxListRow extends StatelessWidget {
  const MailboxListRow({
    super.key,
    required this.selected,
    required this.isRead,
    required this.timestamp,
    required this.isDarkMode,
    required this.onSelectedChanged,
    required this.onTap,
    required this.primaryCell,
  });

  final bool selected;
  final bool isRead;
  final DateTime timestamp;
  final bool isDarkMode;
  final ValueChanged<bool> onSelectedChanged;
  final VoidCallback onTap;
  final Widget primaryCell;

  String get _formattedTimestamp {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final hour12 = timestamp.hour % 12 == 0 ? 12 : timestamp.hour % 12;
    final minute = timestamp.minute.toString().padLeft(2, '0');
    final period = timestamp.hour < 12 ? 'AM' : 'PM';
    return '${months[timestamp.month - 1]} ${timestamp.day} | $hour12:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 32,
              child: Checkbox(
                value: selected,
                onChanged: (v) => onSelectedChanged(v ?? false),
              ),
            ),
            Expanded(flex: 3, child: primaryCell),
            Expanded(
              flex: 2,
              child: Text(
                _formattedTimestamp,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: MailboxColors.primaryText(isDarkMode),
                ),
              ),
            ),
            Expanded(child: MailboxStatusPill(isRead: isRead)),
          ],
        ),
      ),
    );
  }
}

class MailboxStatusPill extends StatelessWidget {
  const MailboxStatusPill({super.key, required this.isRead});

  final bool isRead;

  @override
  Widget build(BuildContext context) {
    // rgba(52,199,89,0.2)/#137333 (read) and rgba(205,72,85,0.2)/#FF0004
    // (unread), per Figma node 565:1582.
    final bg = isRead ? const Color(0x3334C759) : const Color(0x33CD4855);
    final fg = isRead ? const Color(0xFF137333) : const Color(0xFFFF0004);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
        child: Text(
          isRead ? 'Read' : 'Unread',
          style: GoogleFonts.poppins(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: fg,
          ),
        ),
      ),
    );
  }
}

class MailboxActionPillButton extends StatelessWidget {
  const MailboxActionPillButton({
    super.key,
    required this.label,
    required this.icon,
    required this.isDarkMode,
    required this.solid,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool isDarkMode;
  final bool solid;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    final background =
        solid ? MailboxColors.primaryButton : MailboxColors.fieldFill(isDarkMode);
    final foreground = solid ? Colors.white : MailboxColors.primaryButton;
    return Material(
      color: disabled ? background.withOpacity(0.5) : background,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 15,
                  color: disabled ? foreground.withOpacity(0.6) : foreground),
              const SizedBox(width: 5),
              Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: disabled ? foreground.withOpacity(0.6) : foreground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
