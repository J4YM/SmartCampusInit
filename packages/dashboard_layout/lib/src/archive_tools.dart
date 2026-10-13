import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_popup.dart';
import 'brightness_x.dart';
import 'control_metrics.dart';
import 'danger_color.dart';
import 'nav_hover_underline.dart' show kSubNavActiveDarkColor;
import 'poppins_theme.dart' show kDarkCheckboxCheckColor;
import 'responsive_x.dart';
import 'titled_table_card.dart' show DashboardSearchField;

/// The shared pieces every archive in the system is built from — the
/// Violation Queue's archived reports, the IT Technician's archived issues,
/// the Guidance Student Archive's logs, the Admin's archived terms — so they
/// all search, select and delete the same way: a search bar, a "Select all"
/// tick-box, a "Delete selected" action and a "Delete all" action, each
/// guarded by one confirmation popup.

/// Whether [fields] match [query]: case-insensitive, and every word of the
/// query must appear somewhere in the fields ("juan 2024" finds Juan Dela
/// Cruz, number 2024-0001). An empty query matches everything.
bool archiveMatchesQuery(String query, Iterable<String?> fields) {
  final words = query
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return true;
  final haystack = fields
      .whereType<String>()
      .map((f) => f.toLowerCase())
      .join(' ');
  return words.every(haystack.contains);
}

/// The tick-box used on archive rows and the "Select all" row: brand blue in
/// light mode, `#A9C6FD` in dark mode — like every checkbox in the app.
class ArchiveCheckbox extends StatelessWidget {
  const ArchiveCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    this.tristate = false,
  });

  /// `null` (with [tristate]) shows the "some selected" dash.
  final bool? value;
  final ValueChanged<bool>? onChanged;
  final bool tristate;

  @override
  Widget build(BuildContext context) {
    final dark = context.isDarkMode;
    return SizedBox(
      width: 32,
      height: 32,
      child: Checkbox(
        value: value,
        tristate: tristate,
        activeColor: dark ? kSubNavActiveDarkColor : AppPopupColors.accent,
        checkColor: dark ? kDarkCheckboxCheckColor : null,
        side: BorderSide(
          color: AppPopupColors.of(context).muted,
          width: 1.5,
        ),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.standard,
        onChanged:
            onChanged == null ? null : (v) => onChanged!(v ?? false),
      ),
    );
  }
}

/// The strip above an archive's list: the search bar, then — when the archive
/// can be deleted from — a "Select all" tick-box and "Delete selected".
/// There is no separate "delete everything" button: tick Select all, then
/// Delete selected.
///
/// [visibleCount] is how many rows match the current search; "Select all"
/// ticks those rows (so searching, ticking Select all and deleting removes the
/// results, nothing else — the confirmation says how many).
class ArchiveToolbar extends StatelessWidget {
  const ArchiveToolbar({
    super.key,
    this.searchController,
    this.onSearchChanged,
    this.searchHint = 'Search',
    this.searchField,
    this.searchKey = const Key('archive-search'),
    required this.visibleCount,
    required this.selectedCount,
    this.onToggleAll,
    this.onDeleteSelected,
    this.busy = false,
    this.fillColor,
  });

  /// The built-in search bar's controller, change callback and hint — or
  /// pass [searchField] to supply a module's own search field instead.
  final TextEditingController? searchController;
  final ValueChanged<String>? onSearchChanged;
  final String searchHint;

  /// Replaces the built-in search bar (a module's own styled field).
  final Widget? searchField;

  /// Key of the built-in search bar — override when one screen holds two
  /// toolbars.
  final Key searchKey;

  /// Rows matching the current search.
  final int visibleCount;

  /// Selected rows (only ever rows that match the search).
  final int selectedCount;

  /// Null on either hides the selection row — a search-only archive.
  final ValueChanged<bool>? onToggleAll;
  final VoidCallback? onDeleteSelected;

  /// A delete is running: the actions dim.
  final bool busy;

  /// The search field's fill; defaults to the page background.
  final Color? fillColor;

  @override
  Widget build(BuildContext context) {
    final canDelete = onToggleAll != null &&
        onDeleteSelected != null &&
        visibleCount > 0;
    final muted = AppPopupColors.of(context).muted;
    final text = AppPopupColors.of(context).text;
    final mobile = context.isMobileWidth;
    final allSelected = visibleCount > 0 && selectedCount >= visibleCount;
    final someSelected = selectedCount > 0 && !allSelected;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        searchField ??
            DashboardSearchField(
              key: searchKey,
              controller: searchController!,
              onChanged: onSearchChanged ?? (_) {},
              hint: searchHint,
              fillColor: fillColor,
            ),
        if (canDelete) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              InkWell(
                key: const Key('archive-select-all'),
                borderRadius: BorderRadius.circular(8),
                onTap: busy ? null : () => onToggleAll!(!allSelected),
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ArchiveCheckbox(
                        value: allSelected ? true : (someSelected ? null : false),
                        tristate: true,
                        onChanged:
                            busy ? null : (v) => onToggleAll!(!allSelected),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        selectedCount > 0
                            ? '$selectedCount selected'
                            : 'Select all',
                        style: GoogleFonts.poppins(
                          fontSize: mobile ? 11 : 12.5,
                          fontWeight: FontWeight.w500,
                          color: selectedCount > 0 ? text : muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              _DangerPill(
                key: const Key('archive-delete-selected'),
                label: 'Delete selected',
                icon: Icons.delete_outline_rounded,
                solid: true,
                onTap: busy || selectedCount == 0 ? null : onDeleteSelected,
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// A destructive action pill, [kDashboardControlHeight] tall: solid red for
/// the primary one, a tinted red for the secondary one.
class _DangerPill extends StatelessWidget {
  const _DangerPill({
    super.key,
    required this.label,
    required this.icon,
    required this.solid,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool solid;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final fill = solid
        ? kDangerTextColor.withOpacity(enabled ? 1 : 0.5)
        : kDangerTextColor.withOpacity(enabled ? 0.14 : 0.07);
    final foreground = solid
        ? Colors.white.withOpacity(enabled ? 1 : 0.7)
        : kDangerTextColor.withOpacity(enabled ? 1 : 0.5);
    return Material(
      color: fill,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: kDashboardControlHeight),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: foreground),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: foreground,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The one confirmation every archive delete goes through. Returns true only
/// when the person confirms. [message] should say what will be removed and
/// that it cannot be undone.
Future<bool> confirmArchiveDelete(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) async {
  final confirmed = await showAppPopup<bool>(
    context: context,
    builder: (dialogContext) => AppPopup(
      title: title,
      width: 400,
      body: Text(
        message,
        style: GoogleFonts.poppins(
          fontSize: dialogContext.isMobileWidth ? 11 : 13,
          height: 1.5,
          color: AppPopupColors.of(dialogContext).text,
        ),
      ),
      actions: [
        AppPopupSecondaryButton(
          key: const Key('archive-delete-cancel'),
          label: 'Cancel',
          onPressed: () => Navigator.of(dialogContext).pop(false),
        ),
        AppPopupPrimaryButton(
          key: const Key('archive-delete-confirm'),
          label: confirmLabel,
          destructive: true,
          onPressed: () => Navigator.of(dialogContext).pop(true),
        ),
      ],
    ),
  );
  return confirmed == true;
}

/// "1 report" / "3 reports".
String archiveCountLabel(int count, String singular, [String? plural]) =>
    '$count ${count == 1 ? singular : (plural ?? '${singular}s')}';
