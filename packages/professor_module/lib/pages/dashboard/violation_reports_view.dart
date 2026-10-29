import 'dart:typed_data';

import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/professor_colors.dart';

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
        'Under_Investigation' || 'Investigation_Complete' => 'Under investigation',
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

/// A photo the reporter picked, not yet uploaded.
class ReportEvidence {
  const ReportEvidence({
    required this.name,
    required this.bytes,
    required this.contentType,
  });

  final String name;
  final Uint8List bytes;
  final String contentType;
}

/// What the File a Report form hands back: the facts only. The Discipline
/// Officer classifies the violation afterwards.
class ReportSubmission {
  const ReportSubmission({
    required this.studentId,
    required this.incidentAt,
    required this.description,
    this.evidence = const [],
  });

  final String studentId;

  /// When the incident actually happened (not when it was filed).
  final DateTime incidentAt;
  final String description;
  final List<ReportEvidence> evidence;
}

/// Null when [incidentAt] is valid; otherwise the message to show. A report
/// cannot be about something that has not happened yet.
String? validateIncidentAt(DateTime incidentAt, {DateTime? now}) =>
    incidentAt.isAfter(now ?? DateTime.now())
        ? 'Incident time cannot be in the future.'
        : null;

const _evidenceTypes = {
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'webp': 'image/webp',
};

/// Default photo picker: the platform file chooser, images only.
Future<List<ReportEvidence>> pickReportEvidence() async {
  final result = await FilePicker.pickFiles(
    type: FileType.image,
    allowMultiple: true,
    withData: true,
  );
  if (result == null) return const [];
  return [
    for (final f in result.files)
      if (f.bytes != null)
        ReportEvidence(
          name: f.name,
          bytes: f.bytes!,
          contentType: _evidenceTypes[(f.extension ?? '').toLowerCase()] ??
              'application/octet-stream',
        ),
  ];
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
    this.onSearchStudents,
    this.onSubmit,
    this.pickEvidence,
    this.onDecide,
    this.isLoading = false,
  });

  final List<ProfessorReportModel> reports;

  /// Null hides the File a Report button (demo / no database).
  final Future<List<ReportStudentOption>> Function(String query)?
      onSearchStudents;
  final Future<void> Function(ReportSubmission submission)? onSubmit;

  /// Chooses photo evidence; defaults to the platform file chooser.
  final Future<List<ReportEvidence>> Function()? pickEvidence;

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
        pickEvidence: widget.pickEvidence ?? pickReportEvidence,
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

    final search = DashboardSearchField(
      key: const Key('reports-search'),
      controller: _searchController,
      hint: 'Search student or violation',
      fillColor: ProfessorColors.background(context),
      textColor: ProfessorColors.rowText(context),
      hintColor: ProfessorColors.placeholderText(context),
      onChanged: (v) => setState(() {
        _query = v;
        _currentPage = 1;
      }),
    );

    final filter = FilterMenuButton(
      backgroundColor: ProfessorColors.background(context),
      menuColor: ProfessorColors.card(context),
      borderColor: ProfessorColors.cardBorder(context),
      iconColor: ProfessorColors.mutedText(context),
      textColor: ProfessorColors.rowText(context),
      mutedTextColor: ProfessorColors.mutedText(context),
      accentColor: ProfessorColors.azureBlue,
      sections: [
        FilterMenuSection(
          title: 'Status',
          options: const [
            FilterMenuOption(label: 'Pending', value: 'Pending'),
            FilterMenuOption(
                label: 'Under investigation', value: 'Under_Investigation'),
            FilterMenuOption(label: 'Resolved', value: 'Resolved'),
          ],
          selectedValue: _statusFilter,
          onChanged: (value) => setState(() {
            _statusFilter = value;
            _currentPage = 1;
          }),
        ),
      ],
    );

    final fileButton = SecondaryPillButton(
      key: const Key('file-report'),
      label: 'File a Report',
      icon: Icons.add_rounded,
      onTap: _fileReport,
    );

    // Search + Filter on one row, "File a Report" at the card's far right; on
    // a narrow card the action drops under them.
    final toolbar = LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 560;
        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: search),
                  const SizedBox(width: 10),
                  filter,
                ],
              ),
              if (canFile) ...[
                const SizedBox(height: 10),
                Align(alignment: Alignment.centerRight, child: fileButton),
              ],
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: search),
            const SizedBox(width: 10),
            filter,
            if (canFile) ...[
              const SizedBox(width: 10),
              fileButton,
            ],
          ],
        );
      },
    );

    return TitledTableCard(
      title: 'Violation Reports',
      subtitle: Text(
        '$total ${total == 1 ? 'report' : 'reports'}'
        '${pending > 0 ? ' | $pending not yet resolved' : ''}',
        style: TitledTableCard.subtitleStyle(context,
            color: ProfessorColors.mutedText(context)),
      ),
      toolbar: toolbar,
      columns: _columns,
      rows: rows,
      empty: DashboardTableEmptyState(
        icon: Icons.report_outlined,
        message: widget.isLoading
            ? 'Loading reports…'
            : widget.reports.isEmpty
                ? 'No reports tied to you yet'
                : 'No reports match your search',
      ),
      footer: filtered.isEmpty
          ? null
          : CardPaginationFooter(
              currentPage: currentPage,
              totalPages: totalPages,
              totalCount: filtered.length,
              textColor: ProfessorColors.mutedText(context),
              accentColor: ProfessorColors.azureBlue,
              mutedBackground: ProfessorColors.background(context),
              onPrevious: () => setState(() => _currentPage = currentPage - 1),
              onNext: () => setState(() => _currentPage = currentPage + 1),
            ),
      backgroundColor: ProfessorColors.card(context),
      borderColor: ProfessorColors.cardBorder(context),
      titleColor: ProfessorColors.rowText(context),
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

    // What still needs the professor, or what they decided — a muted line
    // under the status pill.
    final note = [
      if (r.isEscalated) 'Escalated',
      if (r.professorDecision != null)
        'You ${r.professorDecision!.toLowerCase()}'
      else if (r.canDecide)
        'Awaiting your decision',
    ].join(' · ');

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
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _ReportStatusBadge(status: r.status, label: r.statusLabel),
            if (note.isNotEmpty) ...[
              const SizedBox(height: 4),
              line(note, dashboardTableSubStyle(context)),
            ],
          ],
        ),
      ],
    );
  }
}

/// The report's status as the same tinted pill every dashboard's status
/// column uses: amber while pending, blue under investigation, green once
/// resolved.
class _ReportStatusBadge extends StatelessWidget {
  const _ReportStatusBadge({required this.status, required this.label});

  final String status;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'Resolved' => ProfessorColors.successGreen,
      'Under_Investigation' => ProfessorColors.azureBlue,
      _ => ProfessorColors.warningYellow,
    };
    // Blue reads poorly on the dark card; use the shared light blue there.
    final text = status == 'Under_Investigation'
        ? subNavActiveColor(context, ProfessorColors.azureBlue)
        : color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: GoogleFonts.poppins(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: text,
        ),
      ),
    );
  }
}

/// A small tinted pill (14% of [color]) — the same soft look as the status
/// badge — for "Escalated" and the professor's own decision.
class _ReportPill extends StatelessWidget {
  const _ReportPill(this.label, this.color);

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: GoogleFonts.poppins(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
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
    // The popup palette (it renders in the root overlay), laid out like the
    // Endorsement detail: a label column, values beside it, and sunken wells
    // under their own headings for the longer text.
    final c = AppPopupColors.of(context);
    final mobile = context.isMobileWidth;

    Widget fact(String label, Widget value) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 104,
                child: Text(label,
                    style: GoogleFonts.poppins(
                        fontSize: mobile ? 10 : 12, color: c.muted)),
              ),
              Expanded(child: value),
            ],
          ),
        );

    Widget text(String value, {bool strong = false}) => Text(
          value,
          style: GoogleFonts.poppins(
            fontSize: mobile ? 11 : 12.5,
            fontWeight: strong ? FontWeight.w600 : FontWeight.w400,
            color: c.text,
          ),
        );

    Widget well(String value) => Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: c.fieldFill,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            value,
            style: GoogleFonts.poppins(
                fontSize: mobile ? 11 : 13, height: 1.5, color: c.text),
          ),
        );

    final decision = r.professorDecision;
    final decisionNote = (r.professorDecisionNote ?? '').trim();

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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          fact('Violation', text(r.violationLabel, strong: true)),
          fact('Category', text(r.category)),
          fact(
            'Status',
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _ReportStatusBadge(status: r.status, label: r.statusLabel),
                  if (r.isEscalated)
                    const _ReportPill('Escalated', ProfessorColors.dangerRed),
                ],
              ),
            ),
          ),
          fact('Source', text(r.sourceLabel)),
          fact('Filed', text(formatDateTime12h(r.createdAt))),
          if (r.admissionSlipId != null)
            fact('Admission slip',
                text(r.admissionSlipId!.substring(0, 8).toUpperCase())),
          if ((r.notes ?? '').trim().isNotEmpty) ...[
            const AppPopupSection('Notes', icon: Icons.notes_rounded),
            well(r.notes!.trim()),
          ],
          if (decision != null) ...[
            const AppPopupSection('Your decision',
                icon: Icons.fact_check_outlined),
            Align(
              alignment: Alignment.centerLeft,
              child: _ReportPill(
                decision,
                decision == 'Confirmed'
                    ? ProfessorColors.successGreen
                    : ProfessorColors.dangerRed,
              ),
            ),
            if (decisionNote.isNotEmpty) ...[
              const SizedBox(height: 10),
              well(decisionNote),
            ],
          ],
          if (widget.canDecide) ...[
            const AppPopupSection('Your decision',
                icon: Icons.fact_check_outlined),
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

/// The File a Report form: student, when the incident happened, what happened
/// and optional photo evidence. The professor does not choose a violation;
/// the Discipline Officer classifies the report.
class _FileReportDialog extends StatefulWidget {
  const _FileReportDialog({
    required this.onSearchStudents,
    required this.pickEvidence,
  });

  final Future<List<ReportStudentOption>> Function(String query)
      onSearchStudents;
  final Future<List<ReportEvidence>> Function() pickEvidence;

  @override
  State<_FileReportDialog> createState() => _FileReportDialogState();
}

class _FileReportDialogState extends State<_FileReportDialog> {
  final _studentSearch = TextEditingController();
  final _description = TextEditingController();

  List<ReportStudentOption> _results = const [];
  ReportStudentOption? _student;
  bool _searching = false;
  String _lastQuery = '';

  late DateTime _incidentAt = _roundedNow();
  final _evidence = <ReportEvidence>[];
  String? _photoError;

  static DateTime _roundedNow() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day, n.hour, n.minute);
  }

  @override
  void dispose() {
    _studentSearch.dispose();
    _description.dispose();
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

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _incidentAt,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now,
    );
    if (picked == null || !mounted) return;
    setState(() => _incidentAt = DateTime(picked.year, picked.month,
        picked.day, _incidentAt.hour, _incidentAt.minute));
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_incidentAt),
    );
    if (picked == null || !mounted) return;
    setState(() => _incidentAt = DateTime(_incidentAt.year, _incidentAt.month,
        _incidentAt.day, picked.hour, picked.minute));
  }

  Future<void> _addPhotos() async {
    try {
      final picked = await widget.pickEvidence();
      if (!mounted) return;
      setState(() {
        _photoError = null;
        for (final p in picked) {
          if (!_evidence.any((e) => e.name == p.name)) _evidence.add(p);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _photoError = '$e');
    }
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _formatDate(DateTime d) =>
      '${_months[d.month - 1]} ${d.day}, ${d.year}';

  String _formatTime(DateTime d) {
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final m = d.minute.toString().padLeft(2, '0');
    return '$h:$m ${d.hour < 12 ? 'AM' : 'PM'}';
  }

  @override
  Widget build(BuildContext context) {
    final c = AppPopupColors.of(context);
    final timeError = validateIncidentAt(_incidentAt);
    final canSubmit = _student != null &&
        _description.text.trim().isNotEmpty &&
        timeError == null;
    final fieldStyle = appPopupFieldStyle(context);

    Widget note(String text) => Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(
            text,
            style: GoogleFonts.poppins(fontSize: 12, color: c.muted),
          ),
        );

    String studentLine(ReportStudentOption s) =>
        '${s.studentNumber}${s.section.isEmpty ? '' : ' · ${s.section}'}';

    Widget pickerField(
            Key key, IconData icon, String text, VoidCallback onTap) =>
        Material(
          color: c.fieldFill,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            key: key,
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: Row(
                children: [
                  Icon(icon, size: 18, color: c.muted),
                  const SizedBox(width: 10),
                  Expanded(child: Text(text, style: fieldStyle)),
                ],
              ),
            ),
          ),
        );

    return AppPopup(
      title: 'File an Incident Report',
      subtitle: 'Describe what happened. Student Affairs classifies it.',
      width: 560,
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
                    incidentAt: _incidentAt,
                    description: _description.text.trim(),
                    evidence: List.of(_evidence),
                  ))
              : null,
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const AppPopupSection('Student Information',
              icon: Icons.person_outline_rounded),
          if (_student != null)
            Container(
              padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
              decoration: BoxDecoration(
                color: c.fieldFill,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _student!.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: c.text,
                          ),
                        ),
                        Text(
                          studentLine(_student!),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                              fontSize: 11.5, color: c.muted),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Change student',
                    onPressed: () => setState(() => _student = null),
                    icon: Icon(Icons.close_rounded, size: 18, color: c.muted),
                  ),
                ],
              ),
            )
          else ...[
            TextField(
              key: const Key('report-student-search'),
              controller: _studentSearch,
              onChanged: _search,
              keyboardType: TextInputType.text,
              style: fieldStyle,
              cursorColor: AppPopupColors.accent,
              decoration: appPopupInputDecoration(
                context,
                hint: 'Search by student number or name',
                prefixIcon:
                    Icon(Icons.search_rounded, size: 20, color: c.muted),
              ),
            ),
            if (_searching)
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: LinearProgressIndicator(
                  minHeight: 3,
                  color: AppPopupColors.accent,
                ),
              )
            else if (_lastQuery.isNotEmpty && _results.isEmpty)
              note('No student matches "$_lastQuery".')
            else
              for (final s in _results)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Material(
                    color: c.fieldFill,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => setState(() {
                        _student = s;
                        _results = const [];
                        _lastQuery = '';
                        _studentSearch.clear();
                      }),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s.name,
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: c.text,
                              ),
                            ),
                            Text(
                              studentLine(s),
                              style: GoogleFonts.poppins(
                                  fontSize: 11.5, color: c.muted),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
          ],
          const SizedBox(height: 14),
          const AppPopupSection('When did it happen?',
              icon: Icons.event_outlined),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: pickerField(
                    const Key('report-incident-date'),
                    Icons.calendar_today_outlined,
                    _formatDate(_incidentAt),
                    _pickDate),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: pickerField(
                    const Key('report-incident-time'),
                    Icons.schedule_rounded,
                    _formatTime(_incidentAt),
                    _pickTime),
              ),
            ],
          ),
          if (timeError != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                timeError,
                key: const Key('report-incident-error'),
                style: GoogleFonts.poppins(
                    fontSize: 11.5, color: AppPopupColors.danger),
              ),
            ),
          const SizedBox(height: 14),
          const AppPopupSection('What happened?',
              icon: Icons.description_outlined),
          AppPopupTextField(
            key: const Key('report-description'),
            label: 'Description',
            controller: _description,
            minLines: 3,
            maxLines: 5,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 14),
          const AppPopupSection('Photo evidence (optional)',
              icon: Icons.photo_camera_outlined),
          for (final e in _evidence)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 2, 4, 2),
                decoration: BoxDecoration(
                  color: c.fieldFill,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(Icons.image_outlined, size: 18, color: c.muted),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(e.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: fieldStyle),
                    ),
                    IconButton(
                      key: Key('report-remove-photo-${e.name}'),
                      tooltip: 'Remove photo',
                      onPressed: () => setState(() => _evidence.remove(e)),
                      icon: Icon(Icons.close_rounded, size: 18, color: c.muted),
                    ),
                  ],
                ),
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: SecondaryPillButton(
              key: const Key('report-add-photos'),
              label: 'Add photos',
              icon: Icons.add_a_photo_outlined,
              onTap: _addPhotos,
            ),
          ),
          if (_photoError != null)
            Text(
              _photoError!,
              style: GoogleFonts.poppins(
                  fontSize: 11.5, color: AppPopupColors.danger),
            ),
        ],
      ),
    );
  }
}
