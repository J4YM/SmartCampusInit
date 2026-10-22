import 'dart:async';

import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/discipline_case_model.dart';
import '../../models/discipline_ticket_model.dart';
import '../../models/escalation_report_model.dart';
import '../../models/good_moral_models.dart';
import '../../theme/discipline_officer_colors.dart';

/// Colors shared by the endorsement status badges (also used by the Guidance
/// Associate's approvals view).
Color escalationStatusColor(EscalationReportModel r) => switch (r.status) {
      'Approved' => DisciplineOfficerColors.validateGreen,
      'Rejected' => DisciplineOfficerColors.denyRed,
      _ => const Color(0xFFD97706),
    };

class EscalationStatusBadge extends StatelessWidget {
  const EscalationStatusBadge({super.key, required this.report});

  final EscalationReportModel report;

  @override
  Widget build(BuildContext context) {
    final color = escalationStatusColor(report);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        report.statusLabel,
        style: GoogleFonts.poppins(
            fontSize: 11, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}

/// The icon for "Endorse", wherever it appears.
const IconData kIssueEscalationIcon = Icons.assignment_late_outlined;

/// Width of the endorsement side card on a wide screen — the same side-card
/// width the other dashboards use.
const double _kSideCardWidth = 320;

/// Width of the table's far-right action column.
const double _kActionColumnWidth = 44;

const _studentColumns = <DashboardTableColumn>[
  DashboardTableColumn('Student', flex: 4, minWidth: 220),
  DashboardTableColumn('Section', flex: 3, minWidth: 120),
  DashboardTableColumn('Violations', flex: 2, minWidth: 100),
  DashboardTableColumn('Endorsement', flex: 3, minWidth: 150),
  DashboardTableColumn('', width: _kActionColumnWidth, sticky: true),
];

/// One page of the student list the Endorsements tab shows.
typedef EndorsementStudentPage = ({
  List<StudentDirectoryEntryModel> items,
  int totalCount,
});

/// Loads page [page] (1-indexed) of every student, narrowed by [query].
typedef LoadEndorsementStudents = Future<EndorsementStudentPage> Function({
  required int page,
  String query,
});

/// How many students one page of the list holds.
const int kEndorsementPageSize = 25;

/// The Endorsements tab: every student (not only those with violations) beside
/// the endorsements already sent to the Guidance Associate and where each
/// stands. The Discipline Officer endorses a student for counseling and/or a
/// parent intervention; nothing reaches a parent until Guidance approves.
class EndorsementsView extends StatelessWidget {
  const EndorsementsView({
    super.key,
    required this.reports,
    required this.cases,
    required this.loadStudents,
    this.onIssue,
  });

  final List<EscalationReportModel> reports;

  /// Every violation on record: used to show how many each student has and to
  /// offer them as the endorsement's background.
  final List<DisciplineCaseModel> cases;

  /// Source of the paged, searchable student list.
  final LoadEndorsementStudents loadStudents;

  /// Persists a new endorsement. When null the Endorse actions are hidden
  /// (demo).
  final Future<void> Function(EscalationDraft draft)? onIssue;

  Future<void> _endorse(BuildContext context, StudentDirectoryEntryModel s) async {
    final draft = await showEndorseDialog(
      context,
      cases: cases,
      studentNumber: s.studentNumber,
      studentName: s.studentName,
    );
    if (draft == null || onIssue == null) return;
    try {
      await onIssue!(draft);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Endorsement sent to the Guidance Associate.'),
      ));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not send the endorsement: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final studentsCard = _StudentsCard(
      cases: cases,
      reports: reports,
      loadStudents: loadStudents,
      onEndorse: onIssue == null ? null : (s) => _endorse(context, s),
    );
    final reportsCard = _EndorsementsCard(reports: reports);

    if (context.isMobileWidth) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [studentsCard, const SizedBox(height: 16), reportsCard],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < kMasterDetailStackBreakpoint) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [studentsCard, const SizedBox(height: 16), reportsCard],
          );
        }
        return MasterDetailRowFrame(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: studentsCard),
              const SizedBox(width: 18),
              SizedBox(width: _kSideCardWidth, child: reportsCard),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Students (left card)
// ---------------------------------------------------------------------------

class _StudentsCard extends StatefulWidget {
  const _StudentsCard({
    required this.cases,
    required this.reports,
    required this.loadStudents,
    required this.onEndorse,
  });

  final List<DisciplineCaseModel> cases;
  final List<EscalationReportModel> reports;
  final LoadEndorsementStudents loadStudents;
  final void Function(StudentDirectoryEntryModel student)? onEndorse;

  @override
  State<_StudentsCard> createState() => _StudentsCardState();
}

class _StudentsCardState extends State<_StudentsCard> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  String _query = '';
  int _page = 1;
  int _totalCount = 0;
  List<StudentDirectoryEntryModel> _items = const [];
  bool _loading = true;
  String? _error;

  /// Bumped per request so a slow answer to an old query never overwrites the
  /// answer to the newest one.
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final id = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.loadStudents(page: _page, query: _query);
      if (!mounted || id != _request) return;
      setState(() {
        _items = result.items;
        _totalCount = result.totalCount;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || id != _request) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _query = value.trim();
      _page = 1;
      _load();
    });
  }

  int _violationCount(String studentNumber) =>
      widget.cases.where((c) => c.studentNumber == studentNumber).length;

  /// The student's latest endorsement, newest first as the host ordered them.
  EscalationReportModel? _latestReport(String studentNumber) {
    for (final r in widget.reports) {
      if (r.studentNumber == studentNumber) return r;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final totalPages =
        _totalCount == 0 ? 1 : (_totalCount / kEndorsementPageSize).ceil();
    final mutedStyle = GoogleFonts.poppins(
      fontSize: context.isMobileWidth ? 11 : 13,
      color: DisciplineOfficerColors.placeholderText(context),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final bounded = constraints.hasBoundedHeight;

        final rows = <Widget>[
          for (var i = 0; i < _items.length; i++)
            _StudentRow(
              key: ValueKey('endorsement-student-${_items[i].studentNumber}'),
              student: _items[i],
              violations: _violationCount(_items[i].studentNumber),
              latest: _latestReport(_items[i].studentNumber),
              showDivider: i < _items.length - 1,
              onEndorse: widget.onEndorse == null
                  ? null
                  : () => widget.onEndorse!(_items[i]),
            ),
        ];

        final Widget body = _error != null
            ? Padding(
                padding: const EdgeInsets.all(29),
                child: Text('Could not load students: $_error',
                    style: dashboardTableBodyStyle(context)),
              )
            : DashboardTableRows(
                scrollable: true,
                shrinkWrap: !bounded,
                physics: bounded ? null : const NeverScrollableScrollPhysics(),
                empty: DashboardTableEmptyState(
                  icon: Icons.groups_outlined,
                  message: _loading
                      ? 'Loading students…'
                      : (_query.isEmpty
                          ? 'No students on record'
                          : 'No students match your search'),
                ),
                rows: rows,
              );

        return BentoCard(
          backgroundColor: DisciplineOfficerColors.card(context),
          borderColor: DisciplineOfficerColors.cardBorder(context),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: bounded ? MainAxisSize.max : MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(29, 24, 29, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Students',
                      style: GoogleFonts.poppins(
                        fontSize: context.isMobileWidth ? 16 : 18,
                        fontWeight: FontWeight.w600,
                        color: DisciplineOfficerColors.rowText(context),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$_totalCount ${_totalCount == 1 ? 'student' : 'students'}'
                      ' | endorse any student for counseling or a parent '
                      'intervention',
                      style: mutedStyle,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(25, 19, 25, 18),
                child: SizedBox(
                  height: kDashboardControlHeight,
                  child: TextField(
                    key: const Key('endorsement-student-search'),
                    expands: true,
                    maxLines: null,
                    minLines: null,
                    textAlignVertical: TextAlignVertical.center,
                    keyboardType: TextInputType.text,
                    controller: _searchController,
                    onChanged: _onSearch,
                    style: GoogleFonts.poppins(
                      fontSize: context.isMobileWidth ? 11 : 13,
                      color: DisciplineOfficerColors.rowText(context),
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Search student name or number',
                      hintStyle: mutedStyle,
                      prefixIcon: Icon(Icons.search_rounded,
                          size: 20,
                          color:
                              DisciplineOfficerColors.placeholderText(context)),
                      filled: true,
                      fillColor: DisciplineOfficerColors.background(context),
                      contentPadding: EdgeInsets.zero,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              ),
              DashboardTableSection(
                columns: _studentColumns,
                expandBody: bounded,
                body: body,
              ),
              if (_totalCount > 0)
                DashboardTableFooter(
                  child: CardPaginationFooter(
                    currentPage: _page,
                    totalPages: totalPages,
                    totalCount: _totalCount,
                    textColor: DisciplineOfficerColors.placeholderText(context),
                    accentColor: DisciplineOfficerColors.azureBlue,
                    mutedBackground: DisciplineOfficerColors.background(context),
                    onPrevious: () {
                      _page -= 1;
                      _load();
                    },
                    onNext: () {
                      _page += 1;
                      _load();
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _StudentRow extends StatelessWidget {
  const _StudentRow({
    super.key,
    required this.student,
    required this.violations,
    required this.latest,
    required this.showDivider,
    required this.onEndorse,
  });

  final StudentDirectoryEntryModel student;
  final int violations;
  final EscalationReportModel? latest;
  final bool showDivider;

  /// Null hides the button (demo mode: nothing to send to).
  final VoidCallback? onEndorse;

  @override
  Widget build(BuildContext context) {
    return DashboardTableRow(
      columns: _studentColumns,
      showDivider: showDivider,
      cells: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(student.studentName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: dashboardTablePrimaryStyle(context)),
            Text(student.studentNumber,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: dashboardTableSubStyle(context)),
          ],
        ),
        Text(student.programGradeSection,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: dashboardTableBodyStyle(context)),
        Text(violations == 0 ? 'None' : '$violations',
            style: dashboardTableBodyStyle(context)),
        Align(
          alignment: Alignment.centerLeft,
          child: latest == null
              ? Text('Not endorsed', style: dashboardTableSubStyle(context))
              : EscalationStatusBadge(report: latest!),
        ),
        _EndorseIconButton(
          key: ValueKey('endorse-${student.studentNumber}'),
          onPressed: onEndorse,
        ),
      ],
    );
  }
}

/// The icon-only "Endorse" button that ends every student row.
class _EndorseIconButton extends StatelessWidget {
  const _EndorseIconButton({super.key, required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    if (onPressed == null) return const SizedBox(width: 36, height: 36);
    return Align(
      alignment: Alignment.centerRight,
      child: Tooltip(
        message: 'Endorse to Guidance',
        child: IconButton(
          onPressed: onPressed,
          padding: const EdgeInsets.all(8),
          constraints: const BoxConstraints.tightFor(width: 36, height: 36),
          style: IconButton.styleFrom(
            minimumSize: const Size(36, 36),
            fixedSize: const Size(36, 36),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          icon: Icon(
            kIssueEscalationIcon,
            size: 20,
            // Light blue (#A9C6FD) in dark mode, the brand blue in light.
            color: subNavActiveColor(context, DisciplineOfficerColors.azureBlue),
            semanticLabel: 'Endorse to Guidance',
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Endorsements (side card)
// ---------------------------------------------------------------------------

class _EndorsementsCard extends StatefulWidget {
  const _EndorsementsCard({required this.reports});

  final List<EscalationReportModel> reports;

  @override
  State<_EndorsementsCard> createState() => _EndorsementsCardState();
}

class _EndorsementsCardState extends State<_EndorsementsCard> {
  int _currentPage = 1;

  @override
  Widget build(BuildContext context) {
    final pageSize = context.cardPageSize;
    final total = widget.reports.length;
    final totalPages = total == 0 ? 1 : (total / pageSize).ceil();
    final currentPage = _currentPage.clamp(1, totalPages);
    final pageReports =
        widget.reports.skip((currentPage - 1) * pageSize).take(pageSize).toList();
    final awaiting = widget.reports.where((r) => r.isPending).length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final bounded = constraints.hasBoundedHeight;

        final Widget list = DashboardTableRows(
          scrollable: true,
          shrinkWrap: !bounded,
          physics: bounded ? null : const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
          empty: Padding(
            padding: const EdgeInsets.fromLTRB(29, 8, 29, 24),
            child: Text(
              'No endorsements yet.',
              style: dashboardTableBodyStyle(context),
            ),
          ),
          rows: [
            for (final report in pageReports)
              _ReportTile(key: ValueKey('report-${report.id}'), report: report),
          ],
        );

        return BentoCard(
          backgroundColor: DisciplineOfficerColors.card(context),
          borderColor: DisciplineOfficerColors.cardBorder(context),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: bounded ? MainAxisSize.max : MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(29, 24, 29, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Endorsements',
                      style: GoogleFonts.poppins(
                        fontSize: context.isMobileWidth ? 16 : 18,
                        fontWeight: FontWeight.w600,
                        color: DisciplineOfficerColors.rowText(context),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$total ${total == 1 ? 'endorsement' : 'endorsements'}'
                      '${awaiting > 0 ? ' | $awaiting awaiting Guidance' : ''}',
                      style: GoogleFonts.poppins(
                        fontSize: context.isMobileWidth ? 11 : 13,
                        color: DisciplineOfficerColors.placeholderText(context),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(29, 16, 29, 14),
                child: Text(
                  'Endorsements go to the Guidance Associate first. A parent is '
                  'only notified (SMS / email) once Guidance approves.',
                  style: dashboardTableSubStyle(context),
                ),
              ),
              bounded ? Expanded(child: list) : Flexible(child: list),
              if (widget.reports.isNotEmpty)
                DashboardTableFooter(
                  child: CardPaginationFooter(
                    currentPage: currentPage,
                    totalPages: totalPages,
                    totalCount: total,
                    textColor: DisciplineOfficerColors.placeholderText(context),
                    accentColor: DisciplineOfficerColors.azureBlue,
                    mutedBackground: DisciplineOfficerColors.background(context),
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

class _ReportTile extends StatelessWidget {
  const _ReportTile({super.key, required this.report});

  final EscalationReportModel report;

  @override
  Widget build(BuildContext context) {
    final text = DisciplineOfficerColors.rowText(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: DisciplineOfficerColors.background(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(report.studentName,
                        style: dashboardTablePrimaryStyle(context)),
                    Text(report.studentNumber,
                        style: dashboardTableSubStyle(context)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              EscalationStatusBadge(report: report),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${report.kind.label}'
            ' · ${report.isAuto ? 'Automatic flag' : 'By ${report.createdByName ?? 'Student Affairs'}'}'
            ' · ${formatDateTime12h(report.createdAt)}',
            key: ValueKey('report-kind-${report.id}'),
            style: dashboardTableMetaStyle(context),
          ),
          if (report.summary.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(report.summary,
                style: dashboardTableBodyStyle(context, color: text)),
          ],
          if (report.decisionNote != null &&
              report.decisionNote!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Guidance note: ${report.decisionNote}',
                style: dashboardTableSubStyle(context)),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Endorse popup
// ---------------------------------------------------------------------------

/// Opens the Endorse popup for one student and returns the draft the officer
/// confirms (null when cancelled). [cases] supplies the student's violations
/// as optional background; [referralId] ties the endorsement to the student
/// referral it answers, and [initialKind] / [initialSummary] prefill it.
Future<EscalationDraft?> showEndorseDialog(
  BuildContext context, {
  required List<DisciplineCaseModel> cases,
  required String studentNumber,
  required String studentName,
  String? referralId,
  EndorsementKind initialKind = EndorsementKind.counseling,
  String initialSummary = '',
}) {
  return showAppPopup<EscalationDraft>(
    context: context,
    builder: (_) => _EndorseDialog(
      violations: [
        for (final c in cases)
          if (c.studentNumber == studentNumber) c,
      ],
      studentNumber: studentNumber,
      studentName: studentName,
      referralId: referralId,
      initialKind: initialKind,
      initialSummary: initialSummary,
    ),
  );
}

class _EndorseDialog extends StatefulWidget {
  const _EndorseDialog({
    required this.violations,
    required this.studentNumber,
    required this.studentName,
    required this.initialKind,
    required this.initialSummary,
    this.referralId,
  });

  final List<DisciplineCaseModel> violations;
  final String studentNumber;
  final String studentName;
  final String? referralId;
  final EndorsementKind initialKind;
  final String initialSummary;

  @override
  State<_EndorseDialog> createState() => _EndorseDialogState();
}

class _EndorseDialogState extends State<_EndorseDialog> {
  late EndorsementKind _kind = widget.initialKind;
  late final _summary = TextEditingController(text: widget.initialSummary);
  late final _message = TextEditingController(
    text: '${widget.studentName} has concerns on record. Please visit the '
        'Guidance Office to discuss. Thank you.',
  );
  final Set<String> _selected = {};
  bool _sms = true;
  bool _email = false;

  @override
  void dispose() {
    _summary.dispose();
    _message.dispose();
    super.dispose();
  }

  bool get _valid {
    if (_summary.text.trim().isEmpty) return false;
    if (!_kind.notifiesParent) return true;
    return _message.text.trim().isNotEmpty && (_sms || _email);
  }

  EscalationDraft _draft() => EscalationDraft(
        studentNumber: widget.studentNumber,
        violationIds: _selected.toList(),
        summary: _summary.text.trim(),
        message: _kind.notifiesParent ? _message.text.trim() : '',
        channels: _kind.notifiesParent
            ? [if (_sms) 'sms', if (_email) 'email']
            : const [],
        kind: _kind,
        referralId: widget.referralId,
      );

  @override
  Widget build(BuildContext context) {
    return AppPopup(
      title: 'Endorse to Guidance',
      subtitle: '${widget.studentName} · ${widget.studentNumber}',
      width: 520,
      actions: [
        AppPopupSecondaryButton(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppPopupPrimaryButton(
          key: const Key('endorse-confirm'),
          label: 'Send to Guidance',
          onPressed: _valid ? () => Navigator.of(context).pop(_draft()) : null,
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AppPopupSection('Guidance is asked for',
              icon: Icons.volunteer_activism_outlined),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final k in EndorsementKind.values)
                ChoiceChip(
                  key: Key('endorsement-kind-${k.dbValue}'),
                  label: Text(k.label),
                  selected: _kind == k,
                  onSelected: (_) => setState(() => _kind = k),
                ),
            ],
          ),
          const SizedBox(height: 14),
          AppPopupTextField(
            label: 'Reason for the Guidance Associate',
            fieldKey: const Key('endorsement-reason'),
            controller: _summary,
            hint: 'What you have seen and why Guidance should step in',
            minLines: 3,
            maxLines: 3,
            onChanged: (_) => setState(() {}),
          ),
          if (widget.violations.isNotEmpty) ...[
            const SizedBox(height: 14),
            const AppPopupSection('Violations on record (optional)',
                icon: Icons.history_rounded),
            for (final c in widget.violations) ...[
              AppPopupCheckboxTile(
                key: ValueKey('endorsement-violation-${c.id}'),
                title: c.violationType,
                subtitle: formatDateTime12h(c.incidentDateTime),
                value: _selected.contains(c.id),
                onChanged: (v) => setState(() {
                  v ? _selected.add(c.id) : _selected.remove(c.id);
                }),
              ),
              const SizedBox(height: 8),
            ],
          ],
          if (_kind.notifiesParent) ...[
            const SizedBox(height: 8),
            const AppPopupSection('Message to the parent',
                icon: Icons.description_outlined),
            AppPopupTextField(
              label: 'Message (Guidance may edit it)',
              fieldKey: const Key('endorsement-message'),
              controller: _message,
              minLines: 3,
              maxLines: 3,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 14),
            const AppPopupSection('Send Via', icon: Icons.send_outlined),
            Row(
              children: [
                Expanded(
                  child: AppPopupCheckboxTile(
                    key: const Key('endorsement-sms'),
                    title: 'SMS',
                    value: _sms,
                    onChanged: (v) => setState(() => _sms = v),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AppPopupCheckboxTile(
                    key: const Key('endorsement-email'),
                    title: 'Email',
                    value: _email,
                    onChanged: (v) => setState(() => _email = v),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
