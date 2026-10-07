import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'student_archive_models.dart';

String _fmtDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Guidance Counselor's "Student Archive" tab: search for a student, expand
/// them to see their confidential archival logs (past counseling sessions,
/// parent conferences, interventions, referrals), and add or delete entries.
/// Everything is loaded on demand per student; the host persists and audits
/// each action. A callback left null hides its control (read-only / demo).
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
  List<ArchiveStudentModel> _students = const [];
  bool _loading = false;
  Object? _error;
  int _searchNonce = 0;

  @override
  void initState() {
    super.initState();
    _runSearch();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
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
      if (mounted && nonce == _searchNonce) setState(() => _students = result);
    } catch (e) {
      if (mounted && nonce == _searchNonce) setState(() => _error = e);
    } finally {
      if (mounted && nonce == _searchNonce) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).hintColor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Student Archive',
            style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Row(
          children: [
            const Icon(Icons.lock_outline, size: 14),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Confidential. Visible to the Guidance Office only; every view, '
                'addition and deletion is recorded in the audit log.',
                style: GoogleFonts.poppins(fontSize: 12, color: muted),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _search,
          onChanged: (_) => _runSearch(),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Search by name or student number',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),
        if (widget.onSearchStudents == null)
          Text('Student archive needs a Supabase connection.',
              style: GoogleFonts.poppins(fontSize: 12.5, color: muted))
        else if (_error != null)
          Text('Could not load students: $_error',
              style: GoogleFonts.poppins(fontSize: 12.5, color: Colors.red))
        else if (_loading && _students.isEmpty)
          const Center(child: Padding(
            padding: EdgeInsets.all(24),
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ))
        else if (_students.isEmpty)
          Text('No students found.',
              style: GoogleFonts.poppins(fontSize: 12.5, color: muted))
        else
          for (final s in _students)
            _StudentTile(
              key: ValueKey(s.id),
              student: s,
              onLoadLogs: widget.onLoadLogs,
              onAddLog: widget.onAddLog,
              onDeleteLog: widget.onDeleteLog,
            ),
      ],
    );
  }
}

class _StudentTile extends StatefulWidget {
  const _StudentTile({
    super.key,
    required this.student,
    this.onLoadLogs,
    this.onAddLog,
    this.onDeleteLog,
  });

  final ArchiveStudentModel student;
  final Future<List<ArchiveLogModel>> Function(ArchiveStudentModel)? onLoadLogs;
  final Future<void> Function(ArchiveStudentModel, ArchiveLogDraft)? onAddLog;
  final Future<void> Function(ArchiveStudentModel, ArchiveLogModel)? onDeleteLog;

  @override
  State<_StudentTile> createState() => _StudentTileState();
}

class _StudentTileState extends State<_StudentTile> {
  List<ArchiveLogModel>? _logs;
  Object? _error;
  bool _loaded = false;

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _load() async {
    final load = widget.onLoadLogs;
    if (load == null) return;
    try {
      final logs = await load(widget.student);
      if (mounted) setState(() => _logs = logs);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _add() async {
    final add = widget.onAddLog;
    if (add == null) return;
    final theme = Theme.of(context);
    final draft = await showDialog<ArchiveLogDraft>(
      context: context,
      builder: (_) => Theme(data: theme, child: const _AddLogDialog()),
    );
    if (draft == null) return;
    try {
      await add(widget.student, draft);
      _toast('Log added.');
      await _load();
    } catch (e) {
      _toast('Could not add the log: $e');
    }
  }

  Future<void> _delete(ArchiveLogModel log) async {
    final del = widget.onDeleteLog;
    if (del == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this log?'),
        content: Text('"${log.title}" will be permanently deleted. '
            'The deletion is recorded in the audit log.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await del(widget.student, log);
      _toast('Log deleted.');
      await _load();
    } catch (e) {
      _toast('Could not delete the log: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).hintColor;
    final s = widget.student;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        // Logs are fetched only when first expanded, so merely listing
        // students never reads confidential notes.
        onExpansionChanged: (open) {
          if (open && !_loaded) {
            _loaded = true;
            _load();
          }
        },
        title: Text(s.name,
            style: GoogleFonts.poppins(fontSize: 13.5, fontWeight: FontWeight.w600)),
        subtitle: Text(
          s.section.isEmpty ? s.studentNumber : '${s.studentNumber} · ${s.section}',
          style: GoogleFonts.poppins(fontSize: 12, color: muted),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.onAddLog != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _add,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add archival log'),
              ),
            ),
          if (_error != null)
            Text('Could not load logs: $_error',
                style: GoogleFonts.poppins(fontSize: 12, color: Colors.red))
          else if (_logs == null)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
            )
          else if (_logs!.isEmpty)
            Text('No archival logs for this student.',
                style: GoogleFonts.poppins(fontSize: 12.5, color: muted))
          else
            for (final log in _logs!)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(log.title,
                              style: GoogleFonts.poppins(
                                  fontSize: 13, fontWeight: FontWeight.w600)),
                        ),
                        if (widget.onDeleteLog != null)
                          IconButton(
                            tooltip: 'Delete',
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.delete_outline, size: 18),
                            onPressed: () => _delete(log),
                          ),
                      ],
                    ),
                    Text(
                      '${log.type.label} · ${_fmtDate(log.occurredOn)}'
                      '${log.createdByName == null ? '' : ' · ${log.createdByName}'}',
                      style: GoogleFonts.poppins(fontSize: 11.5, color: muted),
                    ),
                    if (log.notes.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(log.notes, style: GoogleFonts.poppins(fontSize: 12.5)),
                    ],
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

class _AddLogDialog extends StatefulWidget {
  const _AddLogDialog();

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

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add archival log'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<ArchiveLogType>(
                value: _type,
                decoration: const InputDecoration(labelText: 'Type'),
                items: [
                  for (final t in ArchiveLogType.values)
                    DropdownMenuItem(value: t, child: Text(t.label)),
                ],
                onChanged: (v) => setState(() => _type = v ?? _type),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _title,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'Title'),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: Text('Date: ${_fmtDate(_date)}')),
                  TextButton(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _date,
                        firstDate: DateTime(2015),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) setState(() => _date = picked);
                    },
                    child: const Text('Change'),
                  ),
                ],
              ),
              TextField(
                controller: _notes,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Notes',
                  alignLabelWithHint: true,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _title.text.trim().isEmpty
              ? null
              : () => Navigator.pop(
                    context,
                    ArchiveLogDraft(
                      type: _type,
                      occurredOn: _date,
                      title: _title.text.trim(),
                      notes: _notes.text.trim(),
                    ),
                  ),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
