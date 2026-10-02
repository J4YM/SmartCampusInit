import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Shared chrome for [NotificationsListView] — title, search
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
  static const primaryButton = Color(0xFF345892);
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
  static const navyHeader = Color(0xFF15253F);
  // Same red used for every other destructive action app-wide (e.g.
  // LogoutConfirmationDialog's "Yes, logout", PillButton's dangerRed).
  static const dangerRed = Color(0xFFCD4855);
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
    return SizedBox(
      width: double.infinity,
      child: BentoCard(
        backgroundColor: MailboxColors.card(isDarkMode),
        borderColor: MailboxColors.border(isDarkMode),
        isDarkMode: isDarkMode,
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
              child: Text(
                title,
                style: GoogleFonts.poppins(
                  fontSize: context.isMobileWidth ? 16 : 18,
                  fontWeight: FontWeight.w600,
                  color: MailboxColors.primaryText(isDarkMode),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: context.isMobileWidth ? double.infinity : 360,
                    height: kDashboardControlHeight,
                    child: TextField(
                      expands: true,
                      maxLines: null,
                      minLines: null,
                      textAlignVertical: TextAlignVertical.center,
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
                          size: 16,
                          color: MailboxColors.secondaryText(isDarkMode),
                        ),
                        isDense: true,
                        prefixIconConstraints: const BoxConstraints(minWidth: 38),
                        filled: true,
                        fillColor: MailboxColors.fieldFill(isDarkMode),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
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
                    backgroundOverride: MailboxColors.dangerRed,
                    onTap: hasSelection ? onDelete : null,
                  ),
                ],
              ),
            ),
            DashboardTableHeader(
              columns: [
                DashboardTableColumn(headerColumns[0], flex: 3),
                DashboardTableColumn(headerColumns[1], flex: 2),
                DashboardTableColumn(headerColumns[2], flex: 1),
              ],
              topBorder: true,
              leading: _MailboxCheckbox(
                value: allSelected,
                onChanged: (v) => onSelectAll(v ?? false),
              ),
            ),
            if (rows.isEmpty)
              DashboardTableEmptyState(
                icon: Icons.inbox_outlined,
                message: emptyLabel,
              )
            else
              // shrinkWrap + NeverScrollableScrollPhysics — this card sits
              // inside the dashboard's own outer SingleChildScrollView, so the
              // row list sizes to its (already-paginated, small) content
              // instead of trying to scroll independently. The divider
              // between rows is the table's own row divider.
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                itemCount: rows.length,
                separatorBuilder: (context, __) => Divider(
                  height: 1,
                  color: DashboardTableColors.border(context),
                ),
                itemBuilder: (_, i) => rows[i],
              ),
            DashboardTableFooter(
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
      ),
    );
  }
}

/// The select checkbox in front of the header and each row — one width in
/// both so the columns after it stay aligned.
class _MailboxCheckbox extends StatelessWidget {
  const _MailboxCheckbox({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: DashboardTableMetrics.columnGap),
      child: SizedBox(
        width: 32,
        child: Checkbox(value: value, onChanged: onChanged),
      ),
    );
  }
}

/// Row column widths — the same flex values as the header's columns.
const _mailboxRowColumns = <DashboardTableColumn>[
  DashboardTableColumn('', flex: 3),
  DashboardTableColumn('', flex: 2),
  DashboardTableColumn('', flex: 1),
];

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
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final hour12 = timestamp.hour % 12 == 0 ? 12 : timestamp.hour % 12;
    final minute = timestamp.minute.toString().padLeft(2, '0');
    final period = timestamp.hour < 12 ? 'AM' : 'PM';
    return '${months[timestamp.month - 1]} ${timestamp.day} | $hour12:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    return DashboardTableRow(
      columns: _mailboxRowColumns,
      // The list draws the divider between rows (see MailboxListScaffold).
      showDivider: false,
      selected: selected,
      onTap: onTap,
      leading: _MailboxCheckbox(
        value: selected,
        onChanged: (v) => onSelectedChanged(v ?? false),
      ),
      cells: [
        primaryCell,
        Text(
          _formattedTimestamp,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: dashboardTableMetaStyle(context),
        ),
        MailboxStatusPill(isRead: isRead),
      ],
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
    final fg = isRead ? const Color(0xFF137333) : kDangerTextColor;
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
    this.backgroundOverride,
  });

  final String label;
  final IconData icon;
  final bool isDarkMode;
  final bool solid;
  final VoidCallback? onTap;

  /// Overrides the solid button's fill (e.g. [MailboxColors.dangerRed] for
  /// a destructive action like "Delete") instead of the default accent.
  /// Ignored when [solid] is false.
  final Color? backgroundOverride;

  @override
  Widget build(BuildContext context) {
    // The non-solid pill is the app-wide secondary button.
    if (!solid) {
      return SecondaryPillButton(
        label: label,
        icon: icon,
        onTap: onTap,
        isDarkMode: isDarkMode,
      );
    }
    final disabled = onTap == null;
    final background = solid
        ? (backgroundOverride ?? MailboxColors.primaryButton)
        : MailboxColors.fieldFill(isDarkMode);
    final foreground = solid ? Colors.white : MailboxColors.primaryButton;
    return Material(
      color: disabled ? background.withOpacity(0.5) : background,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        // Never shorter than the toolbar controls (and the secondary pill)
        // beside it.
        child: ConstrainedBox(
          constraints:
              const BoxConstraints(minHeight: kDashboardControlHeight),
          child: Align(
            widthFactor: 1,
            heightFactor: 1,
            child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 16,
                  color: disabled ? foreground.withOpacity(0.6) : foreground),
              const SizedBox(width: 6),
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
        ),
      ),
    );
  }
}
