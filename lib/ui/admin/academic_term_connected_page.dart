import 'dart:convert';

import 'package:admin_dashboard/admin_dashboard.dart' show AdminPageFrame;
import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../auth/app_user.dart';
import '../../data/academic_term_repository.dart';
import '../../data/audit_logger.dart';
import '../../env.dart';

/// Admin control for moving the whole system into a new school year /
/// semester — see supabase/add_academic_term_migration.sql for exactly what
/// the migration archives and deactivates.
///
/// Laid out like every Admin page: the shared page frame, a "Current Term"
/// card beside the "Migrate to a New Term" card, and the closed terms as a
/// table (each row opens into what it archived).
class AcademicTermConnectedPage extends StatefulWidget {
  const AcademicTermConnectedPage({
    super.key,
    this.currentUser,
    @visibleForTesting this.debugTerms,
    @visibleForTesting this.debugDeleteTerms,
  });

  final AppUser? currentUser;

  /// Test seams: a term history to show when there is no database, and the
  /// function that deletes closed terms (returning how many it deleted).
  final List<AcademicTerm>? debugTerms;
  final Future<int> Function(List<String> termIds)? debugDeleteTerms;

  @override
  State<AcademicTermConnectedPage> createState() =>
      _AcademicTermConnectedPageState();
}

/// Width of the "Current Term" side card on a wide window.
const double _kSideCardWidth = 320;

const _archivedColumns = <DashboardTableColumn>[
  DashboardTableColumn('Term', flex: 4, minWidth: 220),
  DashboardTableColumn('Archived Records', flex: 2, minWidth: 150),
  DashboardTableColumn('Closed', flex: 2, minWidth: 130),
];

class _AcademicTermConnectedPageState extends State<AcademicTermConnectedPage> {
  static const _terms = ['1st Semester', '2nd Semester', 'Summer'];

  final _yearController = TextEditingController();
  String _term = _terms.first;

  bool _loading = true;
  bool _busy = false;
  String? _error;
  late List<AcademicTerm> _history = widget.debugTerms ?? const [];
  int _confirmed = 0;

  /// Closed terms whose row is open, and the archived-terms page.
  final Set<String> _open = {};
  int _page = 1;

  /// Archived Terms: the search bar, and the terms ticked for "Delete
  /// selected" (always a subset of the terms matching the search).
  final _archiveSearch = TextEditingController();
  String _archiveQuery = '';
  final Set<String> _selectedTerms = {};
  bool _deleting = false;

  AcademicTermRepository? get _repo {
    if (!AppEnv.supabaseConfigured) return null;
    return AcademicTermRepository(Supabase.instance.client);
  }

  AcademicTerm? get _current {
    for (final t in _history) {
      if (t.isCurrent) return t;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _yearController.dispose();
    _archiveSearch.dispose();
    super.dispose();
  }

  /// The closed terms matching the Archived Terms search bar.
  List<AcademicTerm> _matchingClosed(List<AcademicTerm> closed) {
    if (_archiveQuery.trim().isEmpty) return closed;
    return [
      for (final t in closed)
        if (archiveMatchesQuery(_archiveQuery, [
          t.label,
          if (t.closedAt != null) _fmt(t.closedAt!),
          for (final table in t.archivedCounts.keys) _tableLabel(table),
        ]))
          t,
    ];
  }

  /// Confirms, then permanently deletes [targets] and everything archived
  /// under them. The current term can never be among them.
  Future<void> _deleteTerms(List<AcademicTerm> targets) async {
    final repo = _repo;
    final deleter =
        widget.debugDeleteTerms ?? (repo == null ? null : repo.deleteClosedTerms);
    if (deleter == null || targets.isEmpty || _deleting) return;
    final records = targets.fold<int>(
        0, (sum, t) => sum + t.archivedCounts.values.fold(0, (a, b) => a + b));
    final what = archiveCountLabel(targets.length, 'archived term');
    final confirmed = await confirmArchiveDelete(
      context,
      title: 'Delete selected terms?',
      message: 'This permanently deletes $what and the '
          '${archiveCountLabel(records, 'record')} archived with '
          '${targets.length == 1 ? 'it' : 'them'}. They cannot be restored '
          'afterwards.',
      confirmLabel: 'Delete',
    );
    if (!confirmed || !mounted) return;

    setState(() => _deleting = true);
    try {
      final ids = [for (final t in targets) t.id];
      final deleted = await deleter(ids);
      final user = widget.currentUser;
      if (user != null && repo != null) {
        await AuditLogger(
          Supabase.instance.client,
          actorId: user.id.startsWith('u_') ? null : user.id,
          actorEmail: user.username,
          actorRole: user.role,
        ).log(
          action: 'Permanently deleted $deleted archived academic term'
              '${deleted == 1 ? '' : 's'} '
              '(${targets.map((t) => t.label).join(', ')})',
          severity: 'WARN',
        );
      }
      _selectedTerms.removeAll(ids);
      if (repo == null) {
        // No database to re-read (a test seam): drop them from what is shown.
        setState(() => _history =
            _history.where((t) => !ids.contains(t.id)).toList());
      }
      await _load();
      _snack(deleted == ids.length
          ? '${archiveCountLabel(deleted, 'term')} deleted.'
          : 'Deleted $deleted of ${ids.length} terms.');
    } catch (e) {
      _snack('Could not delete the archived terms: $e');
      await _load();
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  Future<void> _load() async {
    final repo = _repo;
    if (repo == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final history = await repo.fetchTerms();
      AcademicTerm? current;
      for (final t in history) {
        if (t.isCurrent) current = t;
      }
      final confirmed =
          current == null ? 0 : await repo.countConfirmedStudents(current.id);
      if (!mounted) return;
      setState(() {
        _history = history;
        _confirmed = confirmed;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not load academic terms: $e\n'
          'Run supabase/add_academic_term_migration.sql if you have not yet.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _startNewTerm() async {
    final repo = _repo;
    final year = _yearController.text.trim();
    if (repo == null) return;
    if (!RegExp(r'^\d{4}\s*-\s*\d{4}$').hasMatch(year)) {
      _snack('Enter the school year like 2026-2027.');
      return;
    }
    final normalizedYear = year.replaceAll(RegExp(r'\s'), '');

    final confirmed = await showAppPopup<bool>(
      context: context,
      builder: (_) => _ConfirmNewTermDialog(
        title: 'Start $normalizedYear · $_term?',
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final result = await repo.startNewTerm(
        schoolYear: normalizedYear,
        term: _term,
        startedBy: widget.currentUser?.username,
      );
      final user = widget.currentUser;
      if (user != null) {
        await AuditLogger(
          Supabase.instance.client,
          actorId: user.id.startsWith('u_') ? null : user.id,
          actorEmail: user.username,
          actorRole: user.role,
        ).log(
          action: 'Started academic term $normalizedYear · $_term '
              '(${result.archivedTotal} records archived, '
              '${result.studentsDeactivated} students deactivated)',
          severity: 'WARN',
        );
      }
      _yearController.clear();
      await _load();
      _snack(
        'New term started: ${result.archivedTotal} records archived, '
        '${result.studentsDeactivated} student accounts deactivated.'
        '${result.skipped.isEmpty ? '' : ' Skipped: ${result.skipped.join('; ')}'}',
      );
    } catch (e) {
      _snack('Could not start the new term: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  static String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static String _tableLabel(String table) {
    final words = table.split('_');
    return words
        .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }

  void _openArchive(AcademicTerm term, String table) {
    final repo = _repo;
    if (repo == null) return;
    showAppPopup<void>(
      context: context,
      builder: (_) => _ArchiveRowsDialog(
        repo: repo,
        termId: term.id,
        title: term.label,
        subtitle: _tableLabel(table),
        sourceTable: table,
      ),
    );
  }

  // ---- cards ----------------------------------------------------------

  Widget _currentTermCard(BuildContext context) {
    final current = _current;
    return BentoCard(
      backgroundColor: DashboardTableColors.card(context),
      borderColor: DashboardTableColors.border(context),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Current Term',
            style: dashboardCardTitleStyle(context,
                color: DashboardTableColors.primaryText(context)),
          ),
          const SizedBox(height: 14),
          Text(
            current?.label ?? 'No term started yet',
            style: GoogleFonts.poppins(
              fontSize: context.isMobileWidth ? 20 : 24,
              fontWeight: FontWeight.w700,
              color: DashboardTableColors.primaryText(context),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            current == null
                ? 'Start a term below to begin archiving.'
                : '$_confirmed student${_confirmed == 1 ? '' : 's'} confirmed '
                    'as enrolled this term.',
            style: dashboardTableSubStyle(context),
          ),
        ],
      ),
    );
  }

  Widget _migrateCard(BuildContext context) {
    final fill = DashboardSearchField.defaultFill(context);
    final text = GoogleFonts.poppins(
      fontSize: context.isMobileWidth ? 11 : 13,
      color: DashboardTableColors.primaryText(context),
    );
    final label = GoogleFonts.poppins(
      fontSize: context.isMobileWidth ? 10 : 12,
      fontWeight: FontWeight.w500,
      color: DashboardTableColors.primaryText(context),
    );

    Widget field(String name, Widget child, {double width = 200}) => SizedBox(
          width: width,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(name, style: label),
              ),
              child,
            ],
          ),
        );

    final yearField = SizedBox(
      height: kDashboardControlHeight,
      child: TextField(
        key: const Key('term-school-year'),
        controller: _yearController,
        expands: true,
        maxLines: null,
        minLines: null,
        textAlignVertical: TextAlignVertical.center,
        keyboardType: TextInputType.text,
        style: text,
        decoration: InputDecoration(
          isDense: true,
          hintText: '2026-2027',
          hintStyle: GoogleFonts.poppins(
            fontSize: context.isMobileWidth ? 11 : 13,
            color: DashboardTableColors.secondaryText(context),
          ),
          filled: true,
          fillColor: fill,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );

    final canStart = !_busy && _repo != null;

    return BentoCard(
      backgroundColor: DashboardTableColors.card(context),
      borderColor: DashboardTableColors.border(context),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Migrate to a New Term',
            style: dashboardCardTitleStyle(context,
                color: DashboardTableColors.primaryText(context)),
          ),
          const SizedBox(height: 6),
          Text(
            'Archives the closing term\'s records and deactivates all '
            'student accounts. Students are re-activated when the registrar '
            'confirms their enrollment or an enrollment import includes '
            'them.',
            style: dashboardTableSubStyle(context),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 14,
            runSpacing: 14,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              field('School year', yearField),
              field(
                'Term',
                DashboardDropdown<String>(
                  value: _term,
                  fillColor: fill,
                  textStyle: text,
                  items: [
                    for (final t in _terms)
                      DropdownMenuItem(value: t, child: Text(t)),
                  ],
                  onChanged: (v) => setState(() => _term = v ?? _term),
                ),
              ),
              FilledButton(
                key: const Key('start-new-term'),
                onPressed: canStart ? _startNewTerm : null,
                style: appPrimaryButtonStyle(),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_busy)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    else
                      const Icon(Icons.event_repeat_rounded,
                          size: 16, color: Colors.white),
                    const SizedBox(width: 8),
                    Text(
                      'Start New Term',
                      style: GoogleFonts.poppins(
                          fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _archivedCard(BuildContext context, List<AcademicTerm> allClosed) {
    final closed = _matchingClosed(allClosed);
    final searching = _archiveQuery.trim().isNotEmpty;
    final pageSize = context.cardPageSize;
    final totalPages = closed.isEmpty ? 1 : (closed.length / pageSize).ceil();
    final current = _page.clamp(1, totalPages);
    final pageItems =
        closed.skip((current - 1) * pageSize).take(pageSize).toList();

    return TitledTableCard(
      title: 'Archived Terms',
      subtitle: Text(
        searching
            ? '${closed.length} of ${allClosed.length} closed terms'
            : '${closed.length} closed ${closed.length == 1 ? 'term' : 'terms'}',
        style: TitledTableCard.subtitleStyle(context),
      ),
      toolbar: allClosed.isEmpty
          ? null
          : ArchiveToolbar(
              searchController: _archiveSearch,
              onSearchChanged: (value) => setState(() {
                _archiveQuery = value;
                _page = 1;
                final ids = _matchingClosed(allClosed).map((t) => t.id).toSet();
                _selectedTerms.retainWhere(ids.contains);
              }),
              searchHint: 'Search term, year or archived table',
              visibleCount: closed.length,
              selectedCount: _selectedTerms.length,
              busy: _deleting,
              onToggleAll: (on) => setState(() {
                _selectedTerms.clear();
                if (on) _selectedTerms.addAll(closed.map((t) => t.id));
              }),
              onDeleteSelected: () => _deleteTerms([
                for (final t in allClosed)
                  if (_selectedTerms.contains(t.id)) t,
              ]),
            ),
      columns: _archivedColumns,
      empty: DashboardTableEmptyState(
        icon: searching ? Icons.search_off_rounded : Icons.inventory_2_outlined,
        message:
            searching ? 'No archived terms match your search' : 'No closed terms yet',
      ),
      rows: [
        for (var i = 0; i < pageItems.length; i++)
          _ArchivedTermEntry(
            key: ValueKey('term-${pageItems[i].id}'),
            term: pageItems[i],
            isLast: i == pageItems.length - 1,
            open: _open.contains(pageItems[i].id),
            closedLabel:
                pageItems[i].closedAt == null ? '—' : _fmt(pageItems[i].closedAt!),
            selected: _selectedTerms.contains(pageItems[i].id),
            onSelectedChanged: _deleting
                ? null
                : (on) => setState(() => on
                    ? _selectedTerms.add(pageItems[i].id)
                    : _selectedTerms.remove(pageItems[i].id)),
            tableLabel: _tableLabel,
            onToggle: () => setState(() {
              if (!_open.remove(pageItems[i].id)) _open.add(pageItems[i].id);
            }),
            onOpenTable: (table) => _openArchive(pageItems[i], table),
          ),
      ],
      footer: closed.isEmpty
          ? null
          : CardPaginationFooter(
              currentPage: current,
              totalPages: totalPages,
              totalCount: closed.length,
              textColor: DashboardTableColors.secondaryText(context),
              accentColor: const Color(0xFF345892),
              mutedBackground: DashboardSearchField.defaultFill(context),
              onPrevious: () => setState(() => _page = current - 1),
              onNext: () => setState(() => _page = current + 1),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final closed = _history.where((t) => !t.isCurrent).toList();

    Widget body;
    if (_loading) {
      body = const Padding(
        padding: EdgeInsets.symmetric(vertical: 60),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
      );
    } else {
      final current = _currentTermCard(context);
      final migrate = _migrateCard(context);
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[
            BentoCard(
              backgroundColor: DashboardTableColors.card(context),
              borderColor: DashboardTableColors.border(context),
              padding: const EdgeInsets.all(16),
              child: Text(
                _error!,
                style: dashboardTableBodyStyle(context, color: kDangerTextColor),
              ),
            ),
            const SizedBox(height: 16),
          ],
          LayoutBuilder(
            builder: (context, constraints) {
              if (context.isMobileWidth ||
                  constraints.maxWidth < kMasterDetailStackBreakpoint) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [current, const SizedBox(height: 16), migrate],
                );
              }
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: _kSideCardWidth, child: current),
                    const SizedBox(width: 18),
                    Expanded(child: migrate),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          _archivedCard(context, closed),
        ],
      );
    }

    return AdminPageFrame(
      title: 'Academic Term',
      subtitle: 'Close the term, archive its records and re-open enrollment.',
      child: body,
    );
  }
}

// ---------------------------------------------------------------------------
// Archived term row
// ---------------------------------------------------------------------------

/// Left inset of an archived table under its term: past the side padding and
/// the 28px chevron, so the arrow sits under the term's name.
const double _kInset = DashboardTableMetrics.horizontalPadding + 28;

/// One closed term: a table row and, when open, one line per archived table.
class _ArchivedTermEntry extends StatelessWidget {
  const _ArchivedTermEntry({
    super.key,
    required this.term,
    required this.isLast,
    required this.open,
    required this.closedLabel,
    required this.tableLabel,
    required this.onToggle,
    required this.onOpenTable,
    this.selected = false,
    this.onSelectedChanged,
  });

  final AcademicTerm term;
  final bool isLast;
  final bool open;

  /// Ticked for the card's bulk delete; a null callback hides the tick-box.
  final bool selected;
  final ValueChanged<bool>? onSelectedChanged;
  final String closedLabel;
  final String Function(String table) tableLabel;
  final VoidCallback onToggle;
  final ValueChanged<String> onOpenTable;

  @override
  Widget build(BuildContext context) {
    final total = term.archivedCounts.values.fold(0, (a, b) => a + b);
    final header = DashboardTableRow(
      columns: _archivedColumns,
      showDivider: !(isLast && !open),
      onTap: onToggle,
      cells: [
        Row(
          children: [
            if (onSelectedChanged != null) ...[
              ArchiveCheckbox(
                key: ValueKey('term-select-${term.id}'),
                value: selected,
                onChanged: onSelectedChanged,
              ),
              const SizedBox(width: 4),
            ],
            SizedBox(
              width: 28,
              child: Tooltip(
                message: open ? 'Hide details' : 'Show details',
                child: Icon(
                  open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                  size: 20,
                  color: DashboardTableColors.secondaryText(context),
                ),
              ),
            ),
            Expanded(
              child: Text(
                term.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: dashboardTablePrimaryStyle(context),
              ),
            ),
          ],
        ),
        Text('$total', style: dashboardTableBodyStyle(context)),
        Text(closedLabel, style: dashboardTableBodyStyle(context)),
      ],
    );
    if (!open) return header;

    final fill = DashboardSearchField.defaultFill(context).withOpacity(0.5);
    final entries = term.archivedCounts.entries.toList();
    final Widget detail = entries.isEmpty
        ? Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 52),
            padding: const EdgeInsets.fromLTRB(
                _kInset, 8, DashboardTableMetrics.horizontalPadding, 8),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              color: fill,
              border: isLast
                  ? null
                  : Border(
                      bottom: BorderSide(
                          color: DashboardTableColors.border(context))),
            ),
            child: Text('Nothing was archived.',
                style: dashboardTableBodyStyle(context)),
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < entries.length; i++)
                _ArchivedTableLine(
                  key: ValueKey('${term.id}-${entries[i].key}'),
                  label: tableLabel(entries[i].key),
                  count: entries[i].value,
                  fill: fill,
                  showDivider: !(isLast && i == entries.length - 1),
                  onOpen: entries[i].value == 0
                      ? null
                      : () => onOpenTable(entries[i].key),
                ),
            ],
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [header, detail],
    );
  }
}

/// One archived table of a closed term — its name and row count, and a view
/// button (pinned right) when it has rows.
class _ArchivedTableLine extends StatelessWidget {
  const _ArchivedTableLine({
    super.key,
    required this.label,
    required this.count,
    required this.fill,
    required this.showDivider,
    required this.onOpen,
  });

  final String label;
  final int count;
  final Color fill;
  final bool showDivider;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: fill,
        border: showDivider
            ? Border(
                bottom: BorderSide(color: DashboardTableColors.border(context)))
            : null,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              _kInset, 8, DashboardTableMetrics.horizontalPadding, 8),
          child: Row(
            children: [
              Icon(Icons.subdirectory_arrow_right_rounded,
                  size: 16, color: DashboardTableColors.secondaryText(context)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: dashboardTablePrimaryStyle(context),
                ),
              ),
              Text('$count', style: dashboardTableBodyStyle(context)),
              // Room for the pinned view button drawn over this end.
              const SizedBox(width: 44 + DashboardTableMetrics.horizontalPadding),
            ],
          ),
        ),
      ),
    );
    if (onOpen == null) return content;
    return DashboardTableStickyEnd(
      end: Align(
        alignment: Alignment.centerRight,
        child: DashboardRowIconButton(
          icon: Icons.visibility_outlined,
          tooltip: 'View archived rows',
          onPressed: onOpen,
        ),
      ),
      endWidth: 44,
      background: fill,
      bottomInset: showDivider ? 1 : 0,
      child: content,
    );
  }
}

// ---------------------------------------------------------------------------
// Popups
// ---------------------------------------------------------------------------

class _ConfirmNewTermDialog extends StatelessWidget {
  const _ConfirmNewTermDialog({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final c = AppPopupColors.of(context);
    return AppPopup(
      title: title,
      width: 500,
      actions: [
        AppPopupSecondaryButton(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(false),
        ),
        AppPopupPrimaryButton(
          key: const Key('confirm-new-term'),
          label: 'Start New Term',
          destructive: true,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
      body: Text(
        'This closes the current term, archives its violations, counseling '
        'logs, attendance, grades and subject enrollments, and DEACTIVATES '
        'every student account until the registrar confirms enrollment (or an '
        'enrollment import lists them). Archived data is kept but disappears '
        'from the dashboards.\n\n'
        'This cannot be undone from the app.',
        style: GoogleFonts.poppins(
          fontSize: context.isMobileWidth ? 11 : 13,
          height: 1.5,
          color: c.text,
        ),
      ),
    );
  }
}

/// Read-only, paged view of the rows archived from one table when a term
/// closed. Rows are shown as stored (ids included), expandable per row.
class _ArchiveRowsDialog extends StatefulWidget {
  const _ArchiveRowsDialog({
    required this.repo,
    required this.termId,
    required this.title,
    required this.subtitle,
    required this.sourceTable,
  });

  final AcademicTermRepository repo;
  final String termId;
  final String title;
  final String subtitle;
  final String sourceTable;

  @override
  State<_ArchiveRowsDialog> createState() => _ArchiveRowsDialogState();
}

class _ArchiveRowsDialogState extends State<_ArchiveRowsDialog> {
  static const _pageSize = 25;

  int _page = 0;
  int _total = 0;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = const [];
  final Set<int> _expanded = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _expanded.clear();
    });
    try {
      final result = await widget.repo.fetchArchiveRows(
        termId: widget.termId,
        sourceTable: widget.sourceTable,
        page: _page,
        pageSize: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _rows = result.rows;
        _total = result.total;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// A short, readable one-liner: the first few non-id scalar fields.
  static String _summary(Map<String, dynamic> row) {
    final parts = <String>[];
    for (final e in row.entries) {
      final v = e.value;
      if (v == null || v is Map || v is List) continue;
      if (e.key == 'id' || e.key.endsWith('_id')) continue;
      final s = '$v';
      if (s.isEmpty) continue;
      parts.add('${e.key}: ${s.length > 40 ? '${s.substring(0, 40)}…' : s}');
      if (parts.length == 4) break;
    }
    return parts.isEmpty ? (row['id']?.toString() ?? '(row)') : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final c = AppPopupColors.of(context);
    final mobile = context.isMobileWidth;
    final pages = (_total / _pageSize).ceil().clamp(1, 1 << 30);

    final Widget list;
    if (_loading) {
      list = const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    } else if (_error != null) {
      list = AppPopupError(_error!);
    } else if (_rows.isEmpty) {
      list = Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: Text('No rows were archived.',
              style: GoogleFonts.poppins(
                  fontSize: mobile ? 11 : 13, color: c.muted)),
        ),
      );
    } else {
      list = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < _rows.length; i++)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: c.fieldFill,
                borderRadius: BorderRadius.circular(10),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => setState(() {
                  if (!_expanded.remove(i)) _expanded.add(i);
                }),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _summary(_rows[i]),
                              maxLines: _expanded.contains(i) ? null : 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.poppins(
                                fontSize: mobile ? 11 : 12.5,
                                color: c.text,
                              ),
                            ),
                          ),
                          Icon(
                            _expanded.contains(i)
                                ? Icons.expand_less_rounded
                                : Icons.expand_more_rounded,
                            size: 18,
                            color: c.muted,
                          ),
                        ],
                      ),
                      if (_expanded.contains(i)) ...[
                        const SizedBox(height: 8),
                        SelectableText(
                          const JsonEncoder.withIndent('  ').convert(_rows[i]),
                          style: const TextStyle(
                              fontFamily: 'monospace', fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ],
      );
    }

    return AppPopup(
      title: widget.title,
      subtitle: widget.subtitle,
      width: 680,
      actions: [
        AppPopupSecondaryButton(
          label: 'Close',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          list,
          if (!_loading && _error == null && _total > 0) ...[
            const SizedBox(height: 6),
            CardPaginationFooter(
              currentPage: _page + 1,
              totalPages: pages,
              totalCount: _total,
              textColor: c.muted,
              accentColor: AppPopupColors.accent,
              mutedBackground: c.fieldFill,
              onPrevious: () {
                _page--;
                _load();
              },
              onNext: () {
                _page++;
                _load();
              },
            ),
          ],
        ],
      ),
    );
  }
}
