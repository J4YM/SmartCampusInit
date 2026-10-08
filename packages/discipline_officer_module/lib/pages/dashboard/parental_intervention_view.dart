import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/discipline_case_model.dart';
import '../../models/discipline_ticket_model.dart';
import '../../models/escalation_report_model.dart';
import '../../theme/discipline_officer_colors.dart';

/// Colors shared by the escalation status badges (also used by the Guidance
/// Counselor's approvals view).
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

/// The icon for "Issue Escalation Report", wherever it appears.
const IconData kIssueEscalationIcon = Icons.assignment_late_outlined;

/// Width of the escalation-report side card on a wide screen — the same
/// side-card width the other dashboards use.
const double _kSideCardWidth = 320;

/// Width of the table's far-right action column.
const double _kActionColumnWidth = 44;

const _historyColumns = <DashboardTableColumn>[
  DashboardTableColumn('Student', flex: 4, minWidth: 220),
  DashboardTableColumn('Section', flex: 3, minWidth: 120),
  DashboardTableColumn('Violation', flex: 4, minWidth: 240),
  DashboardTableColumn('Escalated', flex: 3, minWidth: 170),
  DashboardTableColumn('', width: _kActionColumnWidth),
];

/// The Parental Intervention tab: the history of escalated violations (one
/// expandable row per student) beside the escalation reports with where each
/// stands in the Guidance Counselor's approval, plus the "Issue Escalation
/// Report" action. A report only reaches the parent (SMS / email) after the
/// Guidance Counselor approves it.
class ParentalInterventionView extends StatelessWidget {
  const ParentalInterventionView({
    super.key,
    required this.reports,
    required this.cases,
    this.onIssue,
  });

  final List<EscalationReportModel> reports;

  /// Every violation on record (the Violation History's source) — escalated
  /// ones form the history list, and any student with a violation can be
  /// escalated.
  final List<DisciplineCaseModel> cases;

  /// Persists a new report. When null the Issue actions are hidden (demo).
  final Future<void> Function(EscalationDraft draft)? onIssue;

  /// Opens the Issue popup — optionally for one student with some of their
  /// violations already ticked — and sends the result.
  Future<void> _issue(
    BuildContext context, {
    String? studentNumber,
    Set<String>? violationIds,
  }) async {
    final draft = await showAppPopup<EscalationDraft>(
      context: context,
      builder: (_) => _IssueEscalationDialog(
        cases: cases,
        studentNumber: studentNumber,
        violationIds: violationIds,
      ),
    );
    if (draft == null || onIssue == null) return;
    try {
      await onIssue!(draft);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Escalation report sent to the Guidance Counselor.'),
      ));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not send the report: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final escalated = cases.where((c) => c.isEscalated).toList();

    final historyCard = _EscalatedHistoryCard(
      cases: escalated,
      onIssue: onIssue == null
          ? null
          : (studentNumber, ids) =>
              _issue(context, studentNumber: studentNumber, violationIds: ids),
    );
    final reportsCard = _EscalationReportsCard(reports: reports);

    if (context.isMobileWidth) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          historyCard,
          const SizedBox(height: 16),
          reportsCard,
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < kMasterDetailStackBreakpoint) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              historyCard,
              const SizedBox(height: 16),
              reportsCard,
            ],
          );
        }
        // History table on the left, the reports as a side card on the right,
        // both one height (the window's, like the other master-detail tabs).
        return MasterDetailRowFrame(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: historyCard),
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
// Escalated Violation History
// ---------------------------------------------------------------------------

/// "Escalated Violation History": one row per student. A student with several
/// escalated violations is a dropdown — only its header carries the student's
/// name, the rows inside list just the violations. Every row ends with an icon
/// button that starts an escalation report for it.
class _EscalatedHistoryCard extends StatefulWidget {
  const _EscalatedHistoryCard({required this.cases, required this.onIssue});

  /// Escalated violations only, any student.
  final List<DisciplineCaseModel> cases;

  /// (student number, violation ids to pre-tick). Null hides the buttons.
  final void Function(String studentNumber, Set<String> violationIds)? onIssue;

  @override
  State<_EscalatedHistoryCard> createState() => _EscalatedHistoryCardState();
}

class _EscalatedHistoryCardState extends State<_EscalatedHistoryCard> {
  final _searchController = TextEditingController();
  String _query = '';
  int _currentPage = 1;

  /// Students whose dropdown is open (kept across paging and searching).
  final Set<String> _expanded = {};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Students ordered by their latest escalated violation, newest first.
  List<DisciplineStudentGroup> get _students =>
      groupCasesByStudent(widget.cases)
        ..sort((a, b) => b.primaryCase.incidentDateTime
            .compareTo(a.primaryCase.incidentDateTime));

  List<DisciplineStudentGroup> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _students;
    return _students
        .where((g) => g.cases.any((c) =>
            c.studentName.toLowerCase().contains(q) ||
            c.studentNumber.toLowerCase().contains(q) ||
            c.programGradeSection.toLowerCase().contains(q) ||
            c.violationType.toLowerCase().contains(q)))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final students = _filtered;
    final pageSize = context.cardPageSize;
    final totalPages = students.isEmpty ? 1 : (students.length / pageSize).ceil();
    final currentPage = _currentPage.clamp(1, totalPages);
    final pageStudents =
        students.skip((currentPage - 1) * pageSize).take(pageSize).toList();

    final studentCount = groupCasesByStudent(widget.cases).length;
    final mutedStyle = GoogleFonts.poppins(
      fontSize: context.isMobileWidth ? 11 : 13,
      color: DisciplineOfficerColors.placeholderText(context),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final bounded = constraints.hasBoundedHeight;

        final rows = <Widget>[];
        for (var i = 0; i < pageStudents.length; i++) {
          final group = pageStudents[i];
          final isLastGroup = i == pageStudents.length - 1;
          final open = group.cases.length > 1 &&
              _expanded.contains(group.studentKey);
          rows.add(_StudentHistoryEntry(
            key: ValueKey('escalated-student-${group.studentKey}'),
            group: group,
            expanded: open,
            isLast: isLastGroup,
            onToggle: group.cases.length > 1
                ? () => setState(() {
                      if (!_expanded.remove(group.studentKey)) {
                        _expanded.add(group.studentKey);
                      }
                    })
                : null,
            onIssue: widget.onIssue,
          ));
        }

        final Widget body = students.isEmpty
            ? DashboardTableEmptyState(
                icon: Icons.history_rounded,
                message: widget.cases.isEmpty
                    ? 'No escalated violations on record'
                    : 'No students match your search',
              )
            : ListView(
                shrinkWrap: !bounded,
                physics: bounded ? null : const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                children: rows,
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
                      'Escalated Violation History',
                      style: GoogleFonts.poppins(
                        fontSize: context.isMobileWidth ? 16 : 18,
                        fontWeight: FontWeight.w600,
                        color: DisciplineOfficerColors.rowText(context),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$studentCount ${studentCount == 1 ? 'student' : 'students'}'
                      ' | ${widget.cases.length} escalated '
                      '${widget.cases.length == 1 ? 'violation' : 'violations'}',
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
                    key: const Key('escalated-history-search'),
                    expands: true,
                    maxLines: null,
                    minLines: null,
                    textAlignVertical: TextAlignVertical.center,
                    controller: _searchController,
                    onChanged: (value) => setState(() {
                      _query = value;
                      _currentPage = 1;
                    }),
                    style: GoogleFonts.poppins(
                      fontSize: context.isMobileWidth ? 11 : 13,
                      color: DisciplineOfficerColors.rowText(context),
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Search student or violation',
                      hintStyle: mutedStyle,
                      prefixIcon: Icon(Icons.search_rounded,
                          size: 20,
                          color: DisciplineOfficerColors.placeholderText(
                              context)),
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
                columns: _historyColumns,
                expandBody: bounded,
                body: body,
              ),
              if (students.isNotEmpty)
                DashboardTableFooter(
                  child: CardPaginationFooter(
                    currentPage: currentPage,
                    totalPages: totalPages,
                    totalCount: students.length,
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

/// One student: a table row (the dropdown header when they have several
/// escalated violations) and, when open, one violation row each.
class _StudentHistoryEntry extends StatelessWidget {
  const _StudentHistoryEntry({
    super.key,
    required this.group,
    required this.expanded,
    required this.isLast,
    required this.onToggle,
    required this.onIssue,
  });

  final DisciplineStudentGroup group;
  final bool expanded;
  final bool isLast;

  /// Null for a student with a single violation (nothing to open).
  final VoidCallback? onToggle;
  final void Function(String studentNumber, Set<String> violationIds)? onIssue;

  @override
  Widget build(BuildContext context) {
    final student = group.primaryCase;
    final multiple = group.cases.length > 1;
    final only = group.cases.first;

    // A dropdown header (several violations) opens or closes on a click, as
    // does its chevron; the icon button issues a report for all their
    // violations. A single-violation row (nothing to open) is not clickable.
    final VoidCallback? issue = onIssue == null
        ? null
        : () => onIssue!(
            student.studentNumber, {for (final c in group.cases) c.id});

    final header = DashboardTableRow(
      key: ValueKey('escalated-header-${group.studentKey}'),
      columns: _historyColumns,
      showDivider: !(isLast && !expanded),
      onTap: onToggle,
      cells: [
        Row(
          children: [
            SizedBox(
              width: 28,
              child: multiple
                  ? _ExpandToggle(
                      key: ValueKey('escalated-toggle-${group.studentKey}'),
                      expanded: expanded,
                      onTap: onToggle,
                    )
                  : null,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    student.studentName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: dashboardTablePrimaryStyle(context),
                  ),
                  Text(
                    student.studentNumber,
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
          student.programGradeSection,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: dashboardTableBodyStyle(context),
        ),
        if (multiple)
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: DisciplineOfficerColors.background(context),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '${group.cases.length} violations',
                style: dashboardTableMetaStyle(context),
              ),
            ),
          )
        else
          Text(
            only.violationType,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: dashboardTableBodyStyle(context),
          ),
        Text(
          formatDateTime12h(student.incidentDateTime),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: dashboardTableMetaStyle(context),
        ),
        _IssueIconButton(
          key: ValueKey('issue-escalation-${group.studentKey}'),
          onPressed: issue,
        ),
      ],
    );

    if (!multiple || !expanded) return header;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        for (var i = 0; i < group.cases.length; i++)
          _EscalatedViolationRow(
            key: ValueKey('escalated-violation-${group.cases[i].id}'),
            caseItem: group.cases[i],
            showDivider: !(isLast && i == group.cases.length - 1),
            onIssue: onIssue == null
                ? null
                : () => onIssue!(
                    student.studentNumber, {group.cases[i].id}),
          ),
      ],
    );
  }
}

/// A violation inside a student's dropdown: what it was and when — never the
/// student's own details, which the dropdown header above already shows.
class _EscalatedViolationRow extends StatelessWidget {
  const _EscalatedViolationRow({
    super.key,
    required this.caseItem,
    required this.showDivider,
    required this.onIssue,
  });

  final DisciplineCaseModel caseItem;
  final bool showDivider;
  final VoidCallback? onIssue;

  @override
  Widget build(BuildContext context) {
    final muted = DisciplineOfficerColors.mutedText(context);
    const edge = DashboardTableMetrics.horizontalPadding;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: DisciplineOfficerColors.background(context).withOpacity(0.5),
        border: showDivider
            ? Border(
                bottom: BorderSide(color: DashboardTableColors.border(context)))
            : null,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          // Indented inside the student's dropdown: the arrow sits under the
          // student's name (past the header's 28px chevron) and the violation
          // text starts 24px further in.
          padding: const EdgeInsets.fromLTRB(edge + 28, 8, edge, 8),
          child: Row(
            children: [
              Icon(Icons.subdirectory_arrow_right_rounded,
                  size: 16, color: muted),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      caseItem.violationType,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: dashboardTablePrimaryStyle(context),
                    ),
                    Text(
                      formatDateTime12h(caseItem.incidentDateTime),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: dashboardTableSubStyle(context),
                    ),
                  ],
                ),
              ),
              _IssueIconButton(onPressed: onIssue),
            ],
          ),
        ),
      ),
    );
  }
}

/// The icon-only "Issue Escalation Report" button that ends every row.
class _IssueIconButton extends StatelessWidget {
  const _IssueIconButton({super.key, required this.onPressed});

  /// Null hides the button (demo mode: nothing to send to).
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    if (onPressed == null) return const SizedBox(width: 36, height: 36);
    return Align(
      alignment: Alignment.centerRight,
      child: Tooltip(
        message: 'Issue Escalation Report',
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
            semanticLabel: 'Issue Escalation Report',
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Escalation Reports (side card)
// ---------------------------------------------------------------------------

class _EscalationReportsCard extends StatefulWidget {
  const _EscalationReportsCard({required this.reports});

  final List<EscalationReportModel> reports;

  @override
  State<_EscalationReportsCard> createState() => _EscalationReportsCardState();
}

class _EscalationReportsCardState extends State<_EscalationReportsCard> {
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

        final Widget list = widget.reports.isEmpty
            ? Padding(
                padding: const EdgeInsets.fromLTRB(29, 8, 29, 24),
                child: Text(
                  'No escalation reports yet.',
                  style: dashboardTableBodyStyle(context),
                ),
              )
            : ListView.builder(
                shrinkWrap: !bounded,
                physics: bounded ? null : const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
                itemCount: pageReports.length,
                itemBuilder: (context, i) => _ReportTile(
                  key: ValueKey('report-${pageReports[i].id}'),
                  report: pageReports[i],
                ),
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
                      'Escalation Reports',
                      style: GoogleFonts.poppins(
                        fontSize: context.isMobileWidth ? 16 : 18,
                        fontWeight: FontWeight.w600,
                        color: DisciplineOfficerColors.rowText(context),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$total ${total == 1 ? 'report' : 'reports'}'
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
                  'Reports go to the Guidance Counselor first. The parent is '
                  'only notified (SMS / email) once the counselor approves.',
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
            '${report.isAuto ? 'Automatic flag' : 'By ${report.createdByName ?? 'Student Affairs'}'}'
            ' · ${report.channelsLabel} · ${formatDateTime12h(report.createdAt)}',
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
            Text('Counselor note: ${report.decisionNote}',
                style: dashboardTableSubStyle(context)),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Issue Escalation Report popup
// ---------------------------------------------------------------------------

class _IssueEscalationDialog extends StatefulWidget {
  const _IssueEscalationDialog({
    required this.cases,
    this.studentNumber,
    this.violationIds,
  });

  final List<DisciplineCaseModel> cases;

  /// Opens with this student already chosen...
  final String? studentNumber;

  /// ...and these of their violations already ticked (default: all their
  /// escalated ones).
  final Set<String>? violationIds;

  @override
  State<_IssueEscalationDialog> createState() => _IssueEscalationDialogState();
}

class _IssueEscalationDialogState extends State<_IssueEscalationDialog> {
  String? _studentNumber;
  final Set<String> _selected = {};
  final _summary = TextEditingController();
  final _message = TextEditingController();
  bool _sms = true;
  bool _email = false;

  late final Map<String, DisciplineCaseModel> _students = {
    for (final c in widget.cases) c.studentNumber: c,
  };

  @override
  void initState() {
    super.initState();
    final preset = widget.studentNumber;
    if (preset != null && _students.containsKey(preset)) {
      _pickStudent(preset, ids: widget.violationIds, rebuild: false);
    }
  }

  List<DisciplineCaseModel> get _studentCases =>
      widget.cases.where((c) => c.studentNumber == _studentNumber).toList();

  @override
  void dispose() {
    _summary.dispose();
    _message.dispose();
    super.dispose();
  }

  bool get _valid =>
      _studentNumber != null &&
      _selected.isNotEmpty &&
      _message.text.trim().isNotEmpty &&
      (_sms || _email);

  void _pickStudent(String? number, {Set<String>? ids, bool rebuild = true}) {
    void apply() {
      _studentNumber = number;
      _selected
        ..clear()
        ..addAll(ids ??
            _studentCases.where((c) => c.isEscalated).map((c) => c.id));
      final name = number == null ? '' : _students[number]!.studentName;
      _message.text = number == null
          ? ''
          : '$name has repeated conduct concerns on record. Please visit '
              'the Guidance Office to discuss. Thank you.';
    }

    rebuild ? setState(apply) : apply();
  }

  @override
  Widget build(BuildContext context) {
    return AppPopup(
      title: 'Issue Escalation Report',
      subtitle: 'Goes to the Guidance Counselor for approval first.',
      width: 520,
      actions: [
        AppPopupSecondaryButton(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppPopupPrimaryButton(
          label: 'Send to Guidance',
          onPressed: _valid
              ? () => Navigator.of(context).pop(EscalationDraft(
                    studentNumber: _studentNumber!,
                    violationIds: _selected.toList(),
                    summary: _summary.text.trim(),
                    message: _message.text.trim(),
                    channels: [if (_sms) 'sms', if (_email) 'email'],
                  ))
              : null,
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AppPopupSection('Student Information',
              icon: Icons.person_outline_rounded),
          AppPopupDropdown<String>(
            label: 'Student',
            value: _studentNumber,
            hint: 'Choose a student',
            items: [
              for (final e in _students.entries)
                DropdownMenuItem(
                  value: e.key,
                  child: Text('${e.value.studentName} · ${e.key}',
                      overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: _pickStudent,
          ),
          if (_studentNumber != null) ...[
            kAppPopupFieldGap,
            const AppPopupFieldLabel('Violations to include'),
            for (final c in _studentCases) ...[
              AppPopupCheckboxTile(
                key: ValueKey('escalation-violation-${c.id}'),
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
          const SizedBox(height: 8),
          const AppPopupSection('Report Details',
              icon: Icons.description_outlined),
          AppPopupTextField(
            label: 'Report to the Guidance Counselor',
            controller: _summary,
            hint: 'What happened and why this needs intervention',
            minLines: 3,
            maxLines: 3,
          ),
          kAppPopupFieldGap,
          AppPopupTextField(
            label: 'Message to the parent (counselor may edit)',
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
                  key: const Key('escalation-sms'),
                  title: 'SMS',
                  value: _sms,
                  onChanged: (v) => setState(() => _sms = v),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AppPopupCheckboxTile(
                  key: const Key('escalation-email'),
                  title: 'Email',
                  value: _email,
                  onChanged: (v) => setState(() => _email = v),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The chevron that opens or closes a student's dropdown (clicking anywhere on
/// the header row does the same; this just marks it as expandable).
class _ExpandToggle extends StatelessWidget {
  const _ExpandToggle({super.key, required this.expanded, required this.onTap});

  final bool expanded;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Tooltip(
          message: expanded ? 'Hide violations' : 'Show violations',
          child: SizedBox(
            width: 28,
            height: 40,
            child: Icon(
              expanded
                  ? Icons.expand_less_rounded
                  : Icons.expand_more_rounded,
              size: 20,
              color: DisciplineOfficerColors.mutedText(context),
            ),
          ),
        ),
      ),
    );
  }
}
