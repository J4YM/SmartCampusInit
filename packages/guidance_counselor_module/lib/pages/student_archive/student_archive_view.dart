import 'dart:async';

import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../shared/guidance_tab_chrome.dart';
import 'student_archive_models.dart';

String _fmtDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Width of the table's far-right action column (add an archival log).
const double _kActionColumnWidth = 44;

/// How long typing must pause before the roster is searched again.
const Duration _kSearchDebounce = Duration(milliseconds: 300);

const _columns = <DashboardTableColumn>[
  DashboardTableColumn('Student', flex: 5, minWidth: 240),
  DashboardTableColumn('Section', flex: 3, minWidth: 160),
  DashboardTableColumn('', width: _kActionColumnWidth, sticky: true),
];

/// Guidance Counselor's "Student Archive" tab: search for a student, open
/// their row to see their confidential archival logs (past counseling
/// sessions, parent conferences, interventions, referrals), and add or delete
/// entries. Everything is loaded on demand per student; the host persists and
/// audits each action. A callback left null hides its control (read-only /
/// demo).
///
/// One table card in the app-wide layout: a student per row, the logs
/// listed beneath the open student, an icon button ending the row to add one.
class StudentArchiveView extends StatefulWidget {
  const StudentArchiveView({
    super.key,
    this.onSearchStudents,
    this.onLoadLogs,
    this.onAddLog,
    this.onDeleteLog,
  });

  /// Students matching [query] (empty = first page of everyone).
  final Future<List<ArchiveStudentModel>> Function(String query)? onSearchStudents;
  final Future<List<ArchiveLogModel>> Function(ArchiveStudentModel student)? onLoadLogs;
  final Future<void> Function(ArchiveStudentModel student, ArchiveLogDraft draft)? onAddLog;
  final Future<void> Function(ArchiveStudentModel student, ArchiveLogModel log)? onDeleteLog;

  @override
  State<StudentArchiveView> createState() => _StudentArchiveViewState();
}

class _StudentArchiveViewState extends State<StudentArchiveView> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<ArchiveStudentModel> _students = const [];
  bool _loading = false;
  Object? _error;
  int _searchNonce = 0;
  int _currentPage = 1;

  /// Students whose row is open (kept across paging and searching).
  final Set<String> _open = {};

  /// Logs by student id — fetched only when a row is first opened, so merely
  /// listing students never reads confidential notes.
  final Map<String, List<ArchiveLogModel>> _logs = {};
  final Map<String, Object> _logErrors = {};

  @override
  void initState() {
    super.initState();
    _runSearch();
  }

  @override
  void didUpdateWidget(covariant StudentArchiveView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The backend can become available after the first build.
    if (oldWidget.onSearchStudents == null && widget.onSearchStudents != null) {
      _runSearch();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(_kSearchDebounce, _runSearch);
  }

  Future<void> _runSearch() async {
    final search = widget.onSearchStudents;
    if (search == null) return;
    final nonce = ++_searchNonce;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await search(_search.text.trim());
      if (mounted && nonce == _searchNonce) {
        setState(() {
          _students = result;
          _currentPage = 1;
        });
      }
    } catch (e) {
      if (mounted && nonce == _searchNonce) setState(() => _error = e);
    } finally {
      if (mounted && nonce == _searchNonce) setState(() => _loading = false);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _loadLogs(ArchiveStudentModel student) async {
    final load = widget.onLoadLogs;
    if (load == null) return;
    try {
      final logs = await load(student);
      if (!mounted) return;
      setState(() {
        _logs[student.id] = logs;
        _logErrors.remove(student.id);
      });
    } catch (e) {
      if (mounted) setState(() => _logErrors[student.id] = e);
    }
  }

  void _toggle(ArchiveStudentModel student) {
    final opening = !_open.contains(student.id);
    setState(() => opening ? _open.add(student.id) : _open.remove(student.id));
    if (opening && !_logs.containsKey(student.id)) _loadLogs(student);
  }

  Future<void> _add(ArchiveStudentModel student) async {
    final add = widget.onAddLog;
    if (add == null) return;
    final draft = await showAppPopup<ArchiveLogDraft>(
      context: context,
      builder: (_) => _AddLogDialog(student: student),
    );
    if (draft == null || !mounted) return;
    try {
      await add(student, draft);
      _toast('Log added.');
      // Show the new entry: open the row and re-read its logs.
      setState(() {
        _open.add(student.id);
        _logs.remove(student.id);
      });
      await _loadLogs(student);
    } catch (e) {
      _toast('Could not add the log: $e');
    }
  }

  Future<void> _delete(ArchiveStudentModel student, ArchiveLogModel log) async {
    final del = widget.onDeleteLog;
    if (del == null) return;
    final ok = await showAppPopup<bool>(
      context: context,
      builder: (_) => _DeleteLogDialog(log: log),
    );
    if (ok != true || !mounted) return;
    try {
      await del(student, log);
      _toast('Log deleted.');
      await _loadLogs(student);
    } catch (e) {
      _toast('Could not delete the log: $e');
    }
  }

  Widget _emptyState(BuildContext context) {
    if (widget.onSearchStudents == null) {
      return const DashboardTableEmptyState(
        icon: Icons.cloud_off_rounded,
        message: 'Student archive needs a Supabase connection.',
      );
    }
    if (_error != null) {
      return DashboardTableEmptyState(
        icon: Icons.error_outline_rounded,
        message: 'Could not load students: $_error',
      );
    }
    if (_loading) return const _Spinner(padding: 40);
    return DashboardTableEmptyState(
      icon: Icons.folder_off_outlined,
      message: _search.text.trim().isEmpty
          ? 'No students found'
          : 'No students match your search',
    );
  }

  @override
  Widget build(BuildContext context) {
    final muted = GuidanceTabColors.secondaryText(context);
    final pageSize = context.cardPageSize;
    final totalPages =
        _students.isEmpty ? 1 : (_students.length / pageSize).ceil();
    final currentPage = _currentPage.clamp(1, totalPages);
    final pageStudents =
        _students.skip((currentPage - 1) * pageSize).take(pageSize).toList();

    final rows = <Widget>[
      for (var i = 0; i < pageStudents.length; i++)
        _StudentEntry(
          key: ValueKey('archive-student-${pageStudents[i].id}'),
          student: pageStudents[i],
          isLast: i == pageStudents.length - 1,
          open: _open.contains(pageStudents[i].id),
          logs: _logs[pageStudents[i].id],
          logError: _logErrors[pageStudents[i].id],
          onToggle: () => _toggle(pageStudents[i]),
          onAdd: widget.onAddLog == null ? null : () => _add(pageStudents[i]),
          onDelete: widget.onDeleteLog == null
              ? null
              : (log) => _delete(pageStudents[i], log),
        ),
    ];

    return GuidanceTableCard(
      title: 'Student Archive',
      subtitle: Row(
        children: [
          Icon(Icons.lock_outline, size: 14, color: muted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Confidential. Visible to the Guidance Office only; every view, '
              'addition and deletion is recorded in the audit log.',
              style: GuidanceTableCard.subtitleStyle(context),
            ),
          ),
        ],
      ),
      toolbar: GuidanceSearchField(
        key: const Key('archive-search'),
        controller: _search,
        hint: 'Search by name or student number',
        onChanged: _onSearchChanged,
      ),
      columns: _columns,
      rows: rows,
      empty: _emptyState(context),
      footer: _students.isEmpty || _error != null
          ? null
          : CardPaginationFooter(
              currentPage: currentPage,
              totalPages: totalPages,
              totalCount: _students.length,
              textColor: muted,
              accentColor: GuidanceTabColors.primaryAction,
              mutedBackground: GuidanceTabColors.surfaceBackground(context),
              onPrevious: () => setState(() => _currentPage = currentPage - 1),
              onNext: () => setState(() => _currentPage = currentPage + 1),
            ),
    );
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner({required this.padding});

  final double padding;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.all(padding),
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
      );
}

// ---------------------------------------------------------------------------
// Student row + its logs
// ---------------------------------------------------------------------------

/// One student: a table row and, when open, the archival logs beneath it.
class _StudentEntry extends StatelessWidget {
  const _StudentEntry({
    super.key,
    required this.student,
    required this.isLast,
    required this.open,
    required this.logs,
    required this.logError,
    required this.onToggle,
    required this.onAdd,
    required this.onDelete,
  });

  final ArchiveStudentModel student;
  final bool isLast;
  final bool open;

  /// Null until loaded.
  final List<ArchiveLogModel>? logs;
  final Object? logError;
  final VoidCallback onToggle;

  /// Null hides the add button (read-only / demo).
  final VoidCallback? onAdd;
  final void Function(ArchiveLogModel log)? onDelete;

  @override
  Widget build(BuildContext context) {
    final s = student;
    final header = DashboardTableRow(
      key: ValueKey('archive-header-${s.id}'),
      columns: _columns,
      showDivider: !(isLast && !open),
      onTap: onToggle,
      cells: [
        Row(
          children: [
            SizedBox(
              width: 28,
              child: Tooltip(
                message: open ? 'Hide logs' : 'Show logs',
                child: Icon(
                  open
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  size: 20,
                  color: GuidanceTabColors.mutedIcon(context),
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    s.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: dashboardTablePrimaryStyle(context),
                  ),
                  Text(
                    s.studentNumber,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: dashboardTableSubStyle(context),
                  ),
                ],
              ),
            ),
          ],
        ),
        Text(
          s.section.isEmpty ? '—' : s.section,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: dashboardTableBodyStyle(context),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: onAdd == null
              ? const SizedBox(width: 36, height: 36)
              : GuidanceRowIconButton(
                  key: ValueKey('archive-add-${s.id}'),
                  icon: Icons.note_add_outlined,
                  tooltip: 'Add archival log',
                  onPressed: onAdd,
                ),
        ),
      ],
    );

    if (!open) return header;

    final fill = GuidanceTabColors.searchFill(context).withOpacity(0.5);
    final Widget detail;
    if (logError != null) {
      detail = _NoteRow(
        text: 'Could not load logs: $logError',
        color: kDangerTextColor,
        showDivider: !isLast,
        fill: fill,
      );
    } else if (logs == null) {
      detail = _NoteRow(spinner: true, showDivider: !isLast, fill: fill);
    } else if (logs!.isEmpty) {
      detail = _NoteRow(
        text: 'No archival logs for this student.',
        showDivider: !isLast,
        fill: fill,
      );
    } else {
      detail = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < logs!.length; i++)
            _LogRow(
              key: ValueKey('archive-log-${logs![i].id}'),
              log: logs![i],
              fill: fill,
              showDivider: !(isLast && i == logs!.length - 1),
              onDelete: onDelete == null ? null : () => onDelete!(logs![i]),
            ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [header, detail],
    );
  }
}

/// Left inset of a log under its student: past the row's side padding and the
/// 28px chevron, so the arrow sits under the student's name.
const double _kLogInset = DashboardTableMetrics.horizontalPadding + 28;

/// A one-line status under an open student (loading, empty, error).
class _NoteRow extends StatelessWidget {
  const _NoteRow({
    this.text,
    this.color,
    this.spinner = false,
    required this.showDivider,
    required this.fill,
  });

  final String? text;
  final Color? color;
  final bool spinner;
  final bool showDivider;
  final Color fill;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.fromLTRB(
          _kLogInset, 8, DashboardTableMetrics.horizontalPadding, 8),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: fill,
        border: showDivider
            ? Border(
                bottom: BorderSide(color: DashboardTableColors.border(context)))
            : null,
      ),
      child: spinner
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(
              text ?? '',
              style: dashboardTableBodyStyle(context, color: color),
            ),
    );
  }
}

/// One archival log: what it was, when, who wrote it and the notes — with a
/// delete button pinned to the right end so it stays on screen while the
/// table scrolls sideways.
class _LogRow extends StatelessWidget {
  const _LogRow({
    super.key,
    required this.log,
    required this.fill,
    required this.showDivider,
    required this.onDelete,
  });

  final ArchiveLogModel log;
  final Color fill;
  final bool showDivider;

  /// Null hides the delete button (read-only / demo).
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final muted = GuidanceTabColors.mutedIcon(context);
    final meta = '${log.type.label} · ${_fmtDate(log.occurredOn)}'
        '${log.createdByName == null ? '' : ' · ${log.createdByName}'}';

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
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              _kLogInset, 10, DashboardTableMetrics.horizontalPadding, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(Icons.subdirectory_arrow_right_rounded,
                    size: 16, color: muted),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(log.title, style: dashboardTablePrimaryStyle(context)),
                    const SizedBox(height: 2),
                    Text(meta, style: dashboardTableSubStyle(context)),
                    if (log.notes.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        log.notes,
                        style: dashboardTableBodyStyle(
                          context,
                          color: DashboardTableColors.primaryText(context),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // Room for the pinned action drawn over this end.
              const SizedBox(
                width: _kActionColumnWidth +
                    DashboardTableMetrics.horizontalPadding,
              ),
            ],
          ),
        ),
      ),
    );

    if (onDelete == null) return content;
    return DashboardTableStickyEnd(
      end: Align(
        alignment: Alignment.centerRight,
        child: GuidanceRowIconButton(
          key: ValueKey('archive-delete-${log.id}'),
          icon: Icons.delete_outline_rounded,
          tooltip: 'Delete',
          color: kDangerTextColor,
          onPressed: onDelete,
        ),
      ),
      endWidth: _kActionColumnWidth,
      background: fill,
      bottomInset: showDivider ? 1 : 0,
      child: content,
    );
  }
}

// ---------------------------------------------------------------------------
// Popups
// ---------------------------------------------------------------------------

class _DeleteLogDialog extends StatelessWidget {
  const _DeleteLogDialog({required this.log});

  final ArchiveLogModel log;

  @override
  Widget build(BuildContext context) {
    final c = AppPopupColors.of(context);
    return AppPopup(
      title: 'Delete this log?',
      width: 440,
      actions: [
        AppPopupSecondaryButton(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(false),
        ),
        AppPopupPrimaryButton(
          key: const Key('archive-delete-confirm'),
          label: 'Delete',
          destructive: true,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
      body: Text(
        '"${log.title}" will be permanently deleted. '
        'The deletion is recorded in the audit log.',
        style: GoogleFonts.poppins(
          fontSize: context.isMobileWidth ? 11 : 13,
          height: 1.5,
          color: c.text,
        ),
      ),
    );
  }
}

class _AddLogDialog extends StatefulWidget {
  const _AddLogDialog({required this.student});

  final ArchiveStudentModel student;

  @override
  State<_AddLogDialog> createState() => _AddLogDialogState();
}

class _AddLogDialogState extends State<_AddLogDialog> {
  final _title = TextEditingController();
  final _notes = TextEditingController();
  ArchiveLogType _type = ArchiveLogType.counseling;
  DateTime _date = DateTime.now();

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2015),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _date = picked);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppPopupColors.of(context);
    final valid = _title.text.trim().isNotEmpty;
    return AppPopup(
      title: 'Add archival log',
      subtitle: '${widget.student.name} · ${widget.student.studentNumber}',
      width: 480,
      actions: [
        AppPopupSecondaryButton(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppPopupPrimaryButton(
          key: const Key('archive-save'),
          label: 'Save',
          onPressed: valid
              ? () => Navigator.of(context).pop(ArchiveLogDraft(
                    type: _type,
                    occurredOn: _date,
                    title: _title.text.trim(),
                    notes: _notes.text.trim(),
                  ))
              : null,
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppPopupDropdown<ArchiveLogType>(
            label: 'Type',
            value: _type,
            items: [
              for (final t in ArchiveLogType.values)
                DropdownMenuItem(value: t, child: Text(t.label)),
            ],
            onChanged: (v) => setState(() => _type = v ?? _type),
          ),
          kAppPopupFieldGap,
          AppPopupTextField(
            label: 'Title',
            controller: _title,
            onChanged: (_) => setState(() {}),
          ),
          kAppPopupFieldGap,
          const AppPopupFieldLabel('Date'),
          Material(
            color: c.fieldFill,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              key: const Key('archive-date'),
              borderRadius: BorderRadius.circular(10),
              onTap: _pickDate,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(_fmtDate(_date),
                          style: appPopupFieldStyle(context)),
                    ),
                    Icon(Icons.calendar_today_outlined,
                        size: 18, color: c.muted),
                  ],
                ),
              ),
            ),
          ),
          kAppPopupFieldGap,
          AppPopupTextField(
            label: 'Notes',
            controller: _notes,
            maxLines: 5,
          ),
        ],
      ),
    );
  }
}
