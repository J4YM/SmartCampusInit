import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'it_technician_dashboard_page.dart' show ItTechnicianColors;
import 'technical_issues_tab.dart' show TechnicalIssueRowModel;

/// Popup opened by the Technical Issues tab's "View Archived" button: every
/// resolved technical issue. Each card offers Restore (back to the active
/// list) and nothing else; nothing here is purged. Laid out like Student
/// Affairs' archive: a title and close button, a short note, then rounded
/// cards (a bottom sheet on phones, a dialog on wide screens) with the shared
/// pagination footer inside.
class ArchivedIssuesSheet extends StatefulWidget {
  const ArchivedIssuesSheet({
    super.key,
    required this.loadArchived,
    this.onRestore,
    this.onDelete,
  });

  final Future<List<TechnicalIssueRowModel>> Function() loadArchived;

  /// Re-opens the issue. No Restore button when omitted.
  final Future<void> Function(String reportId)? onRestore;

  /// Permanently deletes archived issues by id (their comments go with
  /// them). No tick-boxes or delete actions when omitted.
  final Future<void> Function(List<String> reportIds)? onDelete;

  @override
  State<ArchivedIssuesSheet> createState() => _ArchivedIssuesSheetState();
}

class _ArchivedIssuesSheetState extends State<ArchivedIssuesSheet> {
  /// Issues per page. Each card is tall (category, description, resolved
  /// date, Restore), so five is what fits the popup without scrolling.
  static const _pageSize = 5;

  List<TechnicalIssueRowModel>? _items;
  Object? _error;
  final Set<String> _busy = {};
  int _page = 1;

  final _searchController = TextEditingController();
  String _query = '';

  /// Ids ticked for "Delete selected" — always a subset of what is listed.
  final Set<String> _selected = {};
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// The archived issues matching the search bar.
  List<TechnicalIssueRowModel> get _visible {
    final items = _items ?? const <TechnicalIssueRowModel>[];
    if (_query.trim().isEmpty) return items;
    return [
      for (final i in items)
        if (archiveMatchesQuery(_query, [
          i.categoryLabel,
          i.description,
          i.location,
          i.reportedByLabel,
          i.resolvedAtLabel,
        ]))
          i,
    ];
  }

  void _onSearchChanged(String value) => setState(() {
        _query = value;
        _page = 1;
        final visibleIds = _visible.map((i) => i.id).toSet();
        _selected.retainWhere(visibleIds.contains);
      });

  void _toggleSelected(String id, bool on) =>
      setState(() => on ? _selected.add(id) : _selected.remove(id));

  void _toggleAll(bool on) => setState(() {
        _selected.clear();
        if (on) _selected.addAll(_visible.map((i) => i.id));
      });

  /// Confirms, then permanently deletes [targets] from the archive.
  Future<void> _deleteIssues(List<TechnicalIssueRowModel> targets) async {
    final onDelete = widget.onDelete;
    if (onDelete == null || targets.isEmpty || _deleting) return;
    final what = archiveCountLabel(targets.length, 'archived issue');
    final confirmed = await confirmArchiveDelete(
      context,
      title: 'Delete selected issues?',
      message: 'This permanently deletes $what and their comments. They '
          'cannot be restored afterwards.',
      confirmLabel: 'Delete',
    );
    if (!confirmed || !mounted) return;
    final ids = [for (final i in targets) i.id];
    setState(() => _deleting = true);
    try {
      await onDelete(ids);
      if (!mounted) return;
      setState(() {
        _items?.removeWhere((i) => ids.contains(i.id));
        _selected.removeAll(ids);
      });
      _toast('${archiveCountLabel(ids.length, 'issue')} deleted.');
    } catch (e) {
      _toast('Could not delete: $e');
      // Show what is really left (some may have gone through).
      _selected.clear();
      await _reload();
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  Future<void> _reload() async {
    try {
      final items = await widget.loadArchived();
      if (mounted) setState(() => _items = items);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _restore(TechnicalIssueRowModel item) async {
    final restore = widget.onRestore;
    if (restore == null) return;
    setState(() => _busy.add(item.id));
    try {
      await restore(item.id);
      if (!mounted) return;
      setState(() => _items?.removeWhere((i) => i.id == item.id));
      _toast('Issue restored to the active list.');
    } catch (e) {
      _toast('Could not restore the issue: $e');
    } finally {
      if (mounted) setState(() => _busy.remove(item.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.78;
    final all = _items;
    final items = all == null ? null : _visible;

    // Paged client-side over the searched list. The page is clamped, not
    // stored as-is: restoring the last issue of the last page must land on
    // the new last page, not on one that no longer exists.
    final totalPages =
        items == null || items.isEmpty ? 1 : (items.length / _pageSize).ceil();
    final page = _page.clamp(1, totalPages);
    Widget? footer;

    final Widget body;
    if (_error != null) {
      body = _ArchivedMessage(
        icon: Icons.error_outline_rounded,
        title: 'Could not load archived issues',
        detail: '$_error',
      );
    } else if (items == null) {
      body = const Padding(
        padding: EdgeInsets.symmetric(vertical: 56),
        child: Center(
          child: SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      );
    } else if (all!.isEmpty) {
      body = const _ArchivedMessage(
        icon: Icons.archive_outlined,
        title: 'No archived issues',
        detail: 'Technical issues you resolve appear here.',
      );
    } else if (items.isEmpty) {
      body = const _ArchivedMessage(
        icon: Icons.search_off_rounded,
        title: 'No matching issues',
        detail: 'Try a different category, description or reporter.',
      );
    } else {
      final pageItems =
          items.skip((page - 1) * _pageSize).take(_pageSize).toList();
      footer = Padding(
        padding: const EdgeInsets.fromLTRB(22, 12, 22, 16),
        child: CardPaginationFooter(
          currentPage: page,
          totalPages: totalPages,
          totalCount: items.length,
          textColor: ItTechnicianColors.mutedText(context),
          accentColor: ItTechnicianColors.azureBlue,
          mutedBackground: ItTechnicianColors.background(context),
          onPrevious: () => setState(() => _page = page - 1),
          onNext: () => setState(() => _page = page + 1),
        ),
      );
      body = ListView.separated(
        // A new key per page so the next page opens at its top.
        key: ValueKey('archived-page-$page'),
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 20),
        itemCount: pageItems.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final item = pageItems[index];
          return _ArchivedIssueCard(
            key: ValueKey('archived-${item.id}'),
            item: item,
            busy: _busy.contains(item.id) || _deleting,
            selected: _selected.contains(item.id),
            onSelectedChanged: widget.onDelete == null
                ? null
                : (on) => _toggleSelected(item.id, on),
            onRestore: widget.onRestore == null ? null : () => _restore(item),
          );
        },
      );
    }

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 14),
              child: AppPopupHeader(
                title: 'Archived Technical Issues',
                subtitle: 'Resolved issues are kept here. Restore one to '
                    'reopen it.',
                onClose: () => Navigator.of(context).pop(),
              ),
            ),
            if (all != null && all.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 0, 22, 14),
                child: ArchiveToolbar(
                  searchController: _searchController,
                  onSearchChanged: _onSearchChanged,
                  searchHint: 'Search category, description or reporter',
                  visibleCount: items?.length ?? 0,
                  selectedCount: _selected.length,
                  busy: _deleting,
                  fillColor: ItTechnicianColors.background(context),
                  onToggleAll: widget.onDelete == null ? null : _toggleAll,
                  onDeleteSelected: widget.onDelete == null
                      ? null
                      : () => _deleteIssues([
                            for (final i in all)
                              if (_selected.contains(i.id)) i,
                          ]),
                ),
              ),
            Divider(height: 1, color: ItTechnicianColors.cardBorder(context)),
            Flexible(child: body),
            if (footer != null) ...[
              Divider(
                  height: 1, color: ItTechnicianColors.cardBorder(context)),
              footer,
            ],
          ],
        ),
      ),
    );
  }
}

/// One archived issue: what it was, who reported it, when it was resolved, and
/// its one action, Restore.
class _ArchivedIssueCard extends StatelessWidget {
  const _ArchivedIssueCard({
    super.key,
    required this.item,
    required this.busy,
    this.selected = false,
    this.onSelectedChanged,
    this.onRestore,
  });

  final TechnicalIssueRowModel item;
  final bool busy;
  final bool selected;

  /// Null hides the tick-box (nothing can be deleted from this archive).
  final ValueChanged<bool>? onSelectedChanged;
  final VoidCallback? onRestore;

  @override
  Widget build(BuildContext context) {
    final text = ItTechnicianColors.rowText(context);
    final muted = ItTechnicianColors.mutedText(context);
    final tone = ItTechnicianColors.successGreen;
    final resolvedAt = item.resolvedAtLabel;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ItTechnicianColors.background(context),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (onSelectedChanged != null) ...[
                ArchiveCheckbox(
                  key: Key('archived-select-${item.id}'),
                  value: selected,
                  onChanged: busy ? null : onSelectedChanged,
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.categoryLabel,
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: text,
                      ),
                    ),
                    Text(
                      'Reported by ${item.reportedByLabel}'
                      '${item.location == null ? '' : ' · ${item.location}'}',
                      style: GoogleFonts.poppins(fontSize: 12, color: muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: tone.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Resolved',
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: tone,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            item.description,
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: text,
            ),
          ),
          if (resolvedAt != null) ...[
            const SizedBox(height: 4),
            Text(
              'Resolved $resolvedAt',
              style: GoogleFonts.poppins(fontSize: 12, color: muted),
            ),
          ],
          if (onRestore != null) ...[
            const SizedBox(height: 6),
            TextButton.icon(
              key: const Key('archived-restore'),
              onPressed: busy ? null : onRestore,
              icon: const Icon(Icons.restore_rounded, size: 16),
              label: Text(
                'Restore',
                style: GoogleFonts.poppins(
                    fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The archive popup's empty / error state: a muted icon, a title and a line
/// of detail, centered.
class _ArchivedMessage extends StatelessWidget {
  const _ArchivedMessage({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final muted = ItTechnicianColors.mutedText(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 44),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 36, color: muted),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: ItTechnicianColors.rowText(context),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              detail,
              textAlign: TextAlign.center,
              style:
                  GoogleFonts.poppins(fontSize: 12, height: 1.45, color: muted),
            ),
          ],
        ),
      ),
    );
  }
}
