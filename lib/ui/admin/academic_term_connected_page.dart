import 'dart:convert';

import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../auth/app_user.dart';
import '../../data/academic_term_repository.dart';
import '../../data/audit_logger.dart';
import '../../env.dart';

/// Admin control for moving the whole system into a new school year /
/// semester — see supabase/add_academic_term_migration.sql for exactly what
/// the migration archives and deactivates.
class AcademicTermConnectedPage extends StatefulWidget {
  const AcademicTermConnectedPage({super.key, this.currentUser});

  final AppUser? currentUser;

  @override
  State<AcademicTermConnectedPage> createState() =>
      _AcademicTermConnectedPageState();
}

class _AcademicTermConnectedPageState extends State<AcademicTermConnectedPage> {
  static const _terms = ['1st Semester', '2nd Semester', 'Summer'];

  final _yearController = TextEditingController();
  String _term = _terms.first;

  bool _loading = true;
  bool _busy = false;
  String? _error;
  List<AcademicTerm> _history = const [];
  int _confirmed = 0;

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
    super.dispose();
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

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => BentoFormDialog(
        title: 'Start $normalizedYear · $_term?',
        content: Text(
          'This closes the current term, archives its violations, '
          'counseling logs, attendance, grades and subject enrollments, and '
          'DEACTIVATES every student account until the registrar confirms '
          'enrollment (or an enrollment import lists them). '
          'Archived data is kept but disappears from the dashboards.\n\n'
          'This cannot be undone from the app.',
        ),
        cancelLabel: 'Cancel',
        onCancel: () => Navigator.of(dialogContext).pop(false),
        confirmLabel: 'Start New Term',
        onConfirm: () => Navigator.of(dialogContext).pop(true),
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
    showDialog<void>(
      context: context,
      builder: (_) => _ArchiveRowsDialog(
        repo: repo,
        termId: term.id,
        title: '${term.label} — ${_tableLabel(table)}',
        sourceTable: table,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final current = _current;

    Widget card(Widget child) => BentoCard(
          backgroundColor: scheme.surface,
          borderColor: scheme.outlineVariant,
          padding: const EdgeInsets.all(20),
          child: child,
        );

    if (_loading) return const Center(child: CircularProgressIndicator());

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_error != null) ...[
          card(Text(_error!, style: TextStyle(color: scheme.error))),
          const SizedBox(height: 16),
        ],
        card(Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Current term', style: text.titleMedium),
            const SizedBox(height: 8),
            Text(current?.label ?? 'No term started yet',
                style: text.headlineSmall),
            if (current != null) ...[
              const SizedBox(height: 4),
              Text('$_confirmed student(s) confirmed as enrolled this term.',
                  style: text.bodyMedium),
            ],
          ],
        )),
        const SizedBox(height: 16),
        card(Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Migrate to a new term', style: text.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Archives the closing term\'s records and deactivates all '
              'student accounts. Students are re-activated when the '
              'registrar confirms their enrollment or an enrollment import '
              'includes them.',
              style: text.bodyMedium,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 200,
                  child: TextField(
                    controller: _yearController,
                    decoration: const InputDecoration(
                      labelText: 'School year',
                      hintText: '2026-2027',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                SizedBox(
                  width: 200,
                  child: DropdownButtonFormField<String>(
                    initialValue: _term,
                    decoration: const InputDecoration(
                      labelText: 'Term',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final t in _terms)
                        DropdownMenuItem(value: t, child: Text(t)),
                    ],
                    onChanged: (v) => setState(() => _term = v ?? _term),
                  ),
                ),
                FilledButton.icon(
                  onPressed: _busy || _repo == null ? null : _startNewTerm,
                  icon: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.event_repeat_rounded),
                  label: const Text('Start new term'),
                ),
              ],
            ),
          ],
        )),
        if (_history.any((t) => !t.isCurrent)) ...[
          const SizedBox(height: 16),
          card(Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Archived terms', style: text.titleMedium),
              const SizedBox(height: 8),
              for (final t in _history.where((t) => !t.isCurrent))
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text(t.label, style: text.titleSmall),
                  subtitle: Text(
                    '${t.archivedCounts.values.fold(0, (a, b) => a + b)} '
                    'records archived'
                    '${t.closedAt == null ? '' : ' · closed ${_fmt(t.closedAt!)}'}',
                    style: text.bodySmall,
                  ),
                  children: [
                    if (t.archivedCounts.isEmpty)
                      const ListTile(title: Text('Nothing was archived.')),
                    for (final e in t.archivedCounts.entries)
                      ListTile(
                        dense: true,
                        title: Text(_tableLabel(e.key)),
                        trailing: Text('${e.value}'),
                        onTap: e.value == 0
                            ? null
                            : () => _openArchive(t, e.key),
                      ),
                  ],
                ),            ],
          )),
        ],
      ],
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
    required this.sourceTable,
  });

  final AcademicTermRepository repo;
  final String termId;
  final String title;
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
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
    final pages = (_total / _pageSize).ceil().clamp(1, 1 << 30);
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 640,
        height: 460,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Text(_error!)
                : ListView(
                    children: [
                      for (final row in _rows)
                        ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          title: Text(_summary(row),
                              maxLines: 2, overflow: TextOverflow.ellipsis),
                          children: [
                            Align(
                              alignment: Alignment.centerLeft,
                              child: SelectableText(
                                const JsonEncoder.withIndent('  ').convert(row),
                                style: const TextStyle(
                                    fontFamily: 'monospace', fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
      ),
      actions: [
        Text('Page ${_page + 1} of $pages · $_total rows'),
        IconButton(
          tooltip: 'Previous page',
          onPressed: _page == 0 || _loading
              ? null
              : () {
                  _page--;
                  _load();
                },
          icon: const Icon(Icons.chevron_left),
        ),
        IconButton(
          tooltip: 'Next page',
          onPressed: _page + 1 >= pages || _loading
              ? null
              : () {
                  _page++;
                  _load();
                },
          icon: const Icon(Icons.chevron_right),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}