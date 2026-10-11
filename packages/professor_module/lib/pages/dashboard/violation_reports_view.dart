import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/professor_colors.dart';
import 'conduct_report_view.dart' show ConductViolationOption;

/// One violation report tied to the professor — one they filed (from the
/// dashboard or by tapping their ID card at the kiosk) or one a student
/// filed at the kiosk naming them as the teacher. Reports filed in one visit
/// share an [admissionSlipId].
class ProfessorReportModel {
  const ProfessorReportModel({
    required this.id,
    required this.studentName,
    required this.studentNumber,
    required this.section,
    required this.violationLabel,
    required this.category,
    required this.status,
    required this.createdAt,
    required this.filedByYou,
    this.admissionSlipId,
    this.notes,
    this.isEscalated = false,
    this.professorDecision,
    this.professorDecisionNote,
  });

  final String id;
  final String studentName;
  final String studentNumber;
  final String section;
  final String violationLabel;
  final String category;

  /// `Pending`, `Under_Investigation` or `Resolved`
  /// (`student_violations.status`).
  final String status;
  final DateTime createdAt;

  /// True when this professor filed it; false for a student's own kiosk
  /// self-report that named them.
  final bool filedByYou;
  final String? admissionSlipId;
  final String? notes;
  final bool isEscalated;

  /// `Confirmed` / `Denied` once the professor named on a student's
  /// self-report has decided; null while undecided.
  final String? professorDecision;
  final String? professorDecisionNote;

  /// Only a report a student filed about this professor, not yet decided.
  bool get canDecide => !filedByYou && professorDecision == null;

  bool get isResolved => status == 'Resolved';

  String get statusLabel => switch (status) {
        'Under_Investigation' => 'Under investigation',
        'Resolved' => 'Resolved',
        _ => 'Pending',
      };

  String get sourceLabel => filedByYou ? 'Filed by you' : 'Student self-report';
}

/// A student found by the "File a report" search.
class ReportStudentOption {
  const ReportStudentOption({
    required this.id,
    required this.name,
    required this.studentNumber,
    required this.section,
  });

  final String id;
  final String name;
  final String studentNumber;
  final String section;
}

/// What the File a Report form hands back.
class ReportSubmission {
  const ReportSubmission({
    required this.studentId,
    required this.offenseIds,
    required this.notes,
    required this.escalateNow,
  });

  final String studentId;
  final List<String> offenseIds;
  final String notes;
  final bool escalateNow;
}

const _columns = <DashboardTableColumn>[
  DashboardTableColumn('Student', flex: 4, minWidth: 220),
  DashboardTableColumn('Violation', flex: 5, minWidth: 240),
  DashboardTableColumn('Source', flex: 3, minWidth: 160),
  DashboardTableColumn('Filed', flex: 3, minWidth: 170),
  DashboardTableColumn('Status', flex: 3, minWidth: 150),
];

/// The Professor's single reporting tab. Top: every violation report tied to
/// them (pending and resolved), searchable and filterable. "File a Report"
/// opens the same kind of form the Security kiosk flow uses: search any
/// student, tick any number of violations, add notes, optionally escalate.
class ViolationReportsView extends StatefulWidget {
  const ViolationReportsView({
    super.key,
    required this.reports,
    required this.offenseOptions,
    this.onSearchStudents,
    this.onSubmit,
    this.onDecide,
    this.isLoading = false,
  });

  final List<ProfessorReportModel> reports;
  final List<ConductViolationOption> offenseOptions;

  /// Null hides the File a Report button (demo / no database).
  final Future<List<ReportStudentOption>> Function(String query)?
      onSearchStudents;
  final Future<void> Function(ReportSubmission submission)? onSubmit;

  /// Saves the professor's confirm / deny on a report that names them.
  /// Null hides the buttons.
  final Future<void> Function(
    ProfessorReportModel report, {
    required bool confirm,
    String? note,
  })? onDecide;
  final bool isLoading;

  @override
  State<ViolationReportsView> createState() => _ViolationReportsViewState();
}

class _ViolationReportsViewState extends State<ViolationReportsView> {
  final _searchController = TextEditingController();
  String _query = '';

  /// `Pending`, `Under_Investigation` or `Resolved`; null = all.
  String? _statusFilter;
  int _currentPage = 1;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<ProfessorReportModel> get _filtered {
    final q = _query.trim().toLowerCase();
    return widget.reports.where((r) {
      if (_statusFilter != null && r.status != _statusFilter) return false;
      if (q.isEmpty) return true;
      return r.studentName.toLowerCase().contains(q) ||
          r.studentNumber.toLowerCase().contains(q) ||
          r.violationLabel.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _fileReport() async {
    final submission = await showAppPopup<ReportSubmission>(
      context: context,
      builder: (_) => _FileReportDialog(
        offenseOptions: widget.offenseOptions,
        onSearchStudents: widget.onSearchStudents!,
      ),
    );
    if (submission == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.onSubmit!(submission);
      messenger.showSnackBar(const SnackBar(content: Text('Report filed.')));
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('Could not file the report: $e')));
    }
  }

  Future<void> _openReport(ProfessorReportModel r) async {
    final canDecide = r.canDecide && widget.onDecide != null;
    final result = await showAppPopup<({bool confirm, String note})>(
      context: context,
      builder: (_) => _ReportDetailDialog(report: r, canDecide: canDecide),
    );
    if (result == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.onDecide!(r, confirm: result.confirm, note: result.note);
      messenger.showSnackBar(SnackBar(
        content: Text(result.confirm ? 'Report confirmed.' : 'Report denied.'),
      ));
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('Could not save your decision: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final pageSize = context.cardPageSize;
    final totalPages =
        filtered.isEmpty ? 1 : (filtered.length / pageSize).ceil();
    final currentPage = _currentPage.clamp(1, totalPages);
    final pageItems =
        filtered.skip((currentPage - 1) * pageSize).take(pageSize).toList();

    final total = widget.reports.length;
    final pending = widget.reports.where((r) => !r.isResolved).length;
    final canFile = widget.onSearchStudents != null && widget.onSubmit != null;

    final rows = <Widget>[
      for (var i = 0; i < pageItems.length; i++)
        _ReportRow(
          key: ValueKey('report-${pageItems[i].id}'),
          report: pageItems[i],
          showDivider: i < pageItems.length - 1,
          onOpen: () => _openReport(pageItems[i]),
        ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final bounded = constraints.hasBoundedHeight;
        final body = DashboardTableRows(
          scrollable: true,
          shrinkWrap: !bounded,
          physics: bounded ? null : const NeverScrollableScrollPhysics(),
          empty: DashboardTableEmptyState(
            icon: Icons.report_outlined,
            message: widget.isLoading
                ? 'Loading reports…'
                : widget.reports.isEmpty
                    ? 'No reports tied to you yet'
                    : 'No reports match your search',
          ),
          rows: rows,
        );

        return BentoCard(
          backgroundColor: ProfessorColors.card(context),
          borderColor: ProfessorColors.cardBorder(context),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: bounded ? MainAxisSize.max : MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(29, 24, 29, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Violation Reports',
                            style: dashboardCardTitleStyle(context,
                                color: ProfessorColors.rowText(context)),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$total ${total == 1 ? 'report' : 'reports'}'
                            '${pending > 0 ? ' | $pending not yet resolved' : ''}',
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              color: ProfessorColors.mutedText(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (canFile)
                      FilledButton.icon(
                        key: const Key('file-report'),
                        onPressed: _fileReport,
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('File a Report'),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(25, 19, 25, 18),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('reports-search'),
                        controller: _searchController,
                        onChanged: (v) => setState(() {
                          _query = v;
                          _currentPage = 1;
                        }),
                        decoration: const InputDecoration(
                          isDense: true,
                          prefixIcon: Icon(Icons.search_rounded),
                          hintText: 'Search student or violation',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    DropdownButton<String?>(
                      value: _statusFilter,
                      hint: const Text('All statuses'),
                      onChanged: (v) => setState(() {
                        _statusFilter = v;
                        _currentPage = 1;
                      }),
                      items: const [
                        DropdownMenuItem(value: null, child: Text('All statuses')),
                        DropdownMenuItem(
                            value: 'Pending', child: Text('Pending')),
                        DropdownMenuItem(
                            value: 'Under_Investigation',
                            child: Text('Under investigation')),
                        DropdownMenuItem(
                            value: 'Resolved', child: Text('Resolved')),
                      ],
                    ),
                  ],
                ),
              ),
              DashboardTableSection(
                columns: _columns,
                expandBody: bounded,
                body: body,
              ),
              if (filtered.isNotEmpty)
                DashboardTableFooter(
                  child: CardPaginationFooter(
                    currentPage: currentPage,
                    totalPages: totalPages,
                    totalCount: filtered.length,
                    textColor: ProfessorColors.mutedText(context),
                    accentColor: ProfessorColors.azureBlue,
                    mutedBackground: ProfessorColors.cardBorder(context),
                    onPrevious: () =>
                        setState(() => _currentPage = currentPage - 1),
                    onNext: () => setState(() => _currentPage = currentPage + 1),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ReportRow extends StatelessWidget {
  const _ReportRow({
    super.key,
    required this.report,
    required this.showDivider,
    required this.onOpen,
  });

  final ProfessorReportModel report;
  final bool showDivider;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final r = report;
    Widget line(String text, TextStyle style) => Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: style,
        );

    return DashboardTableRow(
      columns: _columns,
      showDivider: showDivider,
      onTap: onOpen,
      cells: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            line(r.studentName, dashboardTablePrimaryStyle(context)),
            line(
              r.section.isEmpty
                  ? r.studentNumber
                  : '${r.studentNumber} · ${r.section}',
              dashboardTableSubStyle(context),
            ),
          ],
        ),
        line(r.violationLabel, dashboardTableBodyStyle(context)),
        line(r.sourceLabel, dashboardTableBodyStyle(context)),
        line(formatDateTime12h(r.createdAt), dashboardTableMetaStyle(context)),
        line(
          [
            r.statusLabel,
            if (r.isEscalated) 'Escalated',
            if (r.professorDecision != null) 'You ${r.professorDecision!.toLowerCase()}'
            else if (r.canDecide) 'Awaiting your decision',
          ].join(' · '),
          dashboardTableBodyStyle(context),
        ),
      ],
    );
  }
}

class _ReportDetailDialog extends StatefulWidget {
  const _ReportDetailDialog({required this.report, required this.canDecide});

  final ProfessorReportModel report;
  final bool canDecide;

  @override
  State<_ReportDetailDialog> createState() => _ReportDetailDialogState();
}

class _ReportDetailDialogState extends State<_ReportDetailDialog> {
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.report;
    final muted = ProfessorColors.mutedText(context);
    final body = ProfessorColors.rowText(context);

    Widget fact(String label, String value) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 11.5, color: muted)),
              const SizedBox(height: 2),
              Text(value, style: TextStyle(fontSize: 13.5, color: body)),
            ],
          ),
        );

    return AppPopup(
      title: 'Violation report',
      subtitle: '${r.studentName} · ${r.studentNumber}',
      width: 480,
      actions: [
        AppPopupSecondaryButton(
          label: widget.canDecide ? 'Cancel' : 'Close',
          onPressed: () => Navigator.of(context).pop(),
        ),
        if (widget.canDecide) ...[
          AppPopupPrimaryButton(
            key: const Key('report-deny'),
            label: 'Deny',
            destructive: true,
            onPressed: () => Navigator.of(context)
                .pop((confirm: false, note: _note.text.trim())),
          ),
          AppPopupPrimaryButton(
            key: const Key('report-confirm'),
            label: 'Confirm',
            onPressed: () => Navigator.of(context)
                .pop((confirm: true, note: _note.text.trim())),
          ),
        ],
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          fact('Violation', r.violationLabel),
          fact('Category', r.category),
          fact('Status', r.isEscalated ? '${r.statusLabel} (escalated)' : r.statusLabel),
          fact('Source', r.sourceLabel),
          fact('Filed', formatDateTime12h(r.createdAt)),
          if (r.admissionSlipId != null)
            fact('Admission slip', r.admissionSlipId!.substring(0, 8).toUpperCase()),
          if ((r.notes ?? '').trim().isNotEmpty) fact('Notes', r.notes!.trim()),
          if (r.professorDecision != null)
            fact(
              'Your decision',
              '${r.professorDecision}'
              '${(r.professorDecisionNote ?? '').isEmpty ? '' : ' - ${r.professorDecisionNote}'}',
            ),
          if (widget.canDecide) ...[
            const SizedBox(height: 8),
            AppPopupTextField(
              label: 'Note (optional, shared with Student Affairs)',
              controller: _note,
              maxLines: 2,
            ),
          ],
        ],
      ),
    );
  }
}

/// The File a Report form: student search, multi-select violations grouped by
/// category, notes, "escalate now".
class _FileReportDialog extends StatefulWidget {
  const _FileReportDialog({
    required this.offenseOptions,
    required this.onSearchStudents,
  });

  final List<ConductViolationOption> offenseOptions;
  final Future<List<ReportStudentOption>> Function(String query)
      onSearchStudents;

  @override
  State<_FileReportDialog> createState() => _FileReportDialogState();
}

class _FileReportDialogState extends State<_FileReportDialog> {
  final _studentSearch = TextEditingController();
  final _offenseSearch = TextEditingController();
  final _notes = TextEditingController();

  List<ReportStudentOption> _results = const [];
  ReportStudentOption? _student;
  bool _searching = false;
  String _lastQuery = '';

  final _selected = <String>{};
  bool _escalate = false;

  @override
  void dispose() {
    _studentSearch.dispose();
    _offenseSearch.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    final q = query.trim();
    if (q.isEmpty) {
      setState(() {
        _results = const [];
        _lastQuery = '';
      });
      return;
    }
    setState(() => _searching = true);
    try {
      final found = await widget.onSearchStudents(q);
      if (!mounted) return;
      setState(() {
        _results = found;
        _lastQuery = q;
        _searching = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _results = const [];
        _lastQuery = q;
        _searching = false;
      });
    }
  }

  List<ConductViolationOption> get _visibleOffenses {
    final q = _offenseSearch.text.trim().toLowerCase();
    if (q.isEmpty) return widget.offenseOptions;
    return widget.offenseOptions
        .where((o) =>
            o.label.toLowerCase().contains(q) ||
            o.category.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final muted = ProfessorColors.mutedText(context);
    final canSubmit = _student != null && _selected.isNotEmpty;

    // Group the visible options under one header per category.
    final grouped = <String, List<ConductViolationOption>>{};
    for (final o in _visibleOffenses) {
      grouped.putIfAbsent(o.category, () => []).add(o);
    }

    return AppPopup(
      title: 'File a Report',
      subtitle: 'Report any student for any violation',
      width: 620,
      actions: [
        AppPopupSecondaryButton(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppPopupPrimaryButton(
          key: const Key('file-report-submit'),
          label: 'Submit report',
          onPressed: canSubmit
              ? () => Navigator.of(context).pop(ReportSubmission(
                    studentId: _student!.id,
                    offenseIds: _selected.toList(),
                    notes: _notes.text.trim(),
                    escalateNow: _escalate,
                  ))
              : null,
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Student', style: TextStyle(fontSize: 12, color: muted)),
          const SizedBox(height: 6),
          if (_student != null)
            InputChip(
              label: Text(
                  '${_student!.name} · ${_student!.studentNumber}'
                  '${_student!.section.isEmpty ? '' : ' · ${_student!.section}'}'),
              onDeleted: () => setState(() => _student = null),
            )
          else ...[
            TextField(
              key: const Key('report-student-search'),
              controller: _studentSearch,
              onChanged: _search,
              decoration: const InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.search_rounded),
                hintText: 'Search by student number or name',
                border: OutlineInputBorder(),
              ),
            ),
            if (_searching)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: LinearProgressIndicator(),
              )
            else if (_lastQuery.isNotEmpty && _results.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('No student matches "$_lastQuery".',
                    style: TextStyle(fontSize: 12.5, color: muted)),
              )
            else
              for (final s in _results)
                ListTile(
                  dense: true,
                  title: Text(s.name),
                  subtitle: Text(
                      '${s.studentNumber}${s.section.isEmpty ? '' : ' · ${s.section}'}'),
                  onTap: () => setState(() {
                    _student = s;
                    _results = const [];
                    _lastQuery = '';
                    _studentSearch.clear();
                  }),
                ),
          ],
          const SizedBox(height: 16),
          Text(
            'Violations (${_selected.length} selected)',
            style: TextStyle(fontSize: 12, color: muted),
          ),
          const SizedBox(height: 6),
          TextField(
            key: const Key('report-offense-search'),
            controller: _offenseSearch,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.search_rounded),
              hintText: 'Filter violations',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 200,
            child: ListView(
              children: [
                for (final entry in grouped.entries) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 8, 4, 2),
                    child: Text(
                      entry.key,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: muted,
                      ),
                    ),
                  ),
                  for (final o in entry.value)
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _selected.contains(o.id),
                      title: Text(o.label),
                      onChanged: (v) => setState(() {
                        if (v == true) {
                          _selected.add(o.id);
                        } else {
                          _selected.remove(o.id);
                        }
                      }),
                    ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          AppPopupTextField(
            label: 'Notes / description (optional)',
            controller: _notes,
            maxLines: 3,
          ),
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _escalate,
            title: const Text('Escalate immediately'),
            onChanged: (v) => setState(() => _escalate = v ?? false),
          ),
        ],
      ),
    );
  }
}
