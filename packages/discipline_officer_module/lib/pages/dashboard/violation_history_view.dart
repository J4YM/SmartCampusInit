import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/discipline_case_model.dart';
import '../../models/discipline_ticket_model.dart';
import '../../theme/discipline_officer_colors.dart';
import 'violations_view.dart' show violationSeverity;

/// "Pending", "Under Investigation" or "Resolved" for [c]. Demo cases carry no
/// status; they come from the pending queue, so they read as pending.
String violationStatusLabel(DisciplineCaseModel c) {
  switch ((c.status ?? '').toLowerCase()) {
    case 'resolved':
      return 'Resolved';
    case 'under_investigation':
    case 'under investigation':
      return 'Under Investigation';
    default:
      return 'Pending';
  }
}

const _historyColumns = <DashboardTableColumn>[
  DashboardTableColumn('Student', flex: 4, minWidth: 170),
  DashboardTableColumn('Section', flex: 2, minWidth: 100),
  DashboardTableColumn('Violations', flex: 2, compact: true, minWidth: 100),
  DashboardTableColumn('Open', flex: 2, compact: true, minWidth: 80),
  DashboardTableColumn('Latest Violation', flex: 4, minWidth: 190),
  DashboardTableColumn('Last Filed', flex: 3, minWidth: 170),
];

/// The Students Violation History tab: one row per STUDENT who has any
/// violation on record, newest activity first, in a searchable, filterable
/// table. Clicking a student opens a popup with all of that student's
/// violations — pending, under investigation and resolved — newest first, so
/// a student with many violations is one row here instead of many.
/// Read-only: acting on a violation still happens in the Violations tab.
class ViolationHistoryView extends StatefulWidget {
  const ViolationHistoryView({super.key, required this.cases});

  /// Every violation on record, any student, any status.
  final List<DisciplineCaseModel> cases;

  @override
  State<ViolationHistoryView> createState() => _ViolationHistoryViewState();
}

class _ViolationHistoryViewState extends State<ViolationHistoryView> {
  int get _pageSize => context.cardPageSize;

  final _searchController = TextEditingController();
  String _searchQuery = '';
  int _currentPage = 1;

  String? _statusFilter;
  String? _severityFilter;

  /// The one section picked in the Filter popup, or null for all sections.
  String? _sectionFilter;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _refilter(VoidCallback change) => setState(() {
        change();
        _currentPage = 1;
      });

  FilterSectionPicker get _sectionPicker => FilterSectionPicker(
        entries: sectionFilterEntries([
          for (final g in _students) (g.primaryCase.programGradeSection, null),
        ]),
        selectedId: _sectionFilter,
        onChanged: (id) => _refilter(() => _sectionFilter = id),
      );

  /// Every student with a violation, their violations newest first, the
  /// students ordered by their latest violation (newest first).
  List<DisciplineStudentGroup> get _students => groupCasesByStudent(widget.cases)
    ..sort((a, b) => b.primaryCase.incidentDateTime
        .compareTo(a.primaryCase.incidentDateTime));

  /// True when [c] satisfies the search box and the Status / Severity filters.
  bool _matches(DisciplineCaseModel c, String query) {
    final matchesQuery = query.isEmpty ||
        c.studentName.toLowerCase().contains(query) ||
        c.studentNumber.toLowerCase().contains(query) ||
        c.programGradeSection.toLowerCase().contains(query) ||
        c.violationType.toLowerCase().contains(query) ||
        c.submittedBy.toLowerCase().contains(query) ||
        violationStatusLabel(c).toLowerCase().contains(query);
    return matchesQuery &&
        (_statusFilter == null || violationStatusLabel(c) == _statusFilter) &&
        (_severityFilter == null || violationSeverity(c) == _severityFilter);
  }

  /// Students with at least one violation that matches — and, for the Section
  /// filter, whose own section matches. Each row still counts (and the popup
  /// still lists) the student's WHOLE history, not just the matching part.
  List<DisciplineStudentGroup> get _filtered {
    final query = _searchQuery.trim().toLowerCase();
    return _students
        .where((g) =>
            matchesSectionFilter(
                _sectionFilter, g.primaryCase.programGradeSection) &&
            g.cases.any((c) => _matches(c, query)))
        .toList();
  }

  /// Opens [group]'s full violation history. The popup renders through the
  /// root navigator's overlay, outside this page's own Theme, so the page's
  /// theme is captured here and re-applied inside it.
  Future<void> _openStudent(DisciplineStudentGroup group) {
    final theme = Theme.of(context);
    return showResponsiveSheet<void>(
      context: context,
      backgroundColor: DisciplineOfficerColors.card(context),
      handleColor: DisciplineOfficerColors.mutedText(context),
      desktopMaxWidth: 580,
      builder: (sheetContext) => Theme(
        data: theme,
        child: StudentViolationHistorySheet(group: group),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final students = _filtered;
    final totalPages =
        students.isEmpty ? 1 : (students.length / _pageSize).ceil();
    final currentPage = _currentPage.clamp(1, totalPages);
    final pageStudents =
        students.skip((currentPage - 1) * _pageSize).take(_pageSize).toList();

    final studentCount = groupCasesByStudent(widget.cases).length;
    final mutedStyle = GoogleFonts.poppins(
      fontSize: context.isMobileWidth ? 11 : 13,
      fontWeight: FontWeight.w400,
      color: DisciplineOfficerColors.placeholderText(context),
    );

    return SizedBox(
      width: double.infinity,
      child: BentoCard(
        backgroundColor: DisciplineOfficerColors.card(context),
        borderColor: DisciplineOfficerColors.cardBorder(context),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(29, 24, 29, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Students Violation History',
                    style: GoogleFonts.poppins(
                      fontSize: context.isMobileWidth ? 16 : 18,
                      fontWeight: FontWeight.w600,
                      color: DisciplineOfficerColors.rowText(context),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$studentCount ${studentCount == 1 ? 'student' : 'students'}'
                    ' | ${widget.cases.length} '
                    '${widget.cases.length == 1 ? 'violation' : 'violations'}'
                    ' on record',
                    style: mutedStyle,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(25, 19, 25, 18),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: kDashboardControlHeight,
                      child: TextField(
                        key: const Key('violation-history-search'),
                        expands: true,
                        maxLines: null,
                        minLines: null,
                        textAlignVertical: TextAlignVertical.center,
                        controller: _searchController,
                        onChanged: (value) =>
                            _refilter(() => _searchQuery = value),
                        style: GoogleFonts.poppins(
                          fontSize: context.isMobileWidth ? 11 : 13,
                          color: DisciplineOfficerColors.rowText(context),
                        ),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: 'Search student, violation or status',
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
                  const SizedBox(width: 10),
                  FilterMenuButton(
                    compact: true,
                    backgroundColor: DisciplineOfficerColors.background(context),
                    menuColor: DisciplineOfficerColors.card(context),
                    borderColor: DisciplineOfficerColors.cardBorder(context),
                    iconColor: DisciplineOfficerColors.placeholderText(context),
                    textColor: DisciplineOfficerColors.rowText(context),
                    mutedTextColor: DisciplineOfficerColors.mutedText(context),
                    accentColor: DisciplineOfficerColors.azureBlue,
                    sections: [
                      FilterMenuSection(
                        title: 'Status',
                        options: const [
                          FilterMenuOption(label: 'Pending', value: 'Pending'),
                          FilterMenuOption(
                              label: 'Under Investigation',
                              value: 'Under Investigation'),
                          FilterMenuOption(
                              label: 'Resolved', value: 'Resolved'),
                        ],
                        selectedValue: _statusFilter,
                        onChanged: (v) => _refilter(() => _statusFilter = v),
                      ),
                      FilterMenuSection(
                        title: 'Severity',
                        options: const [
                          FilterMenuOption(label: 'Minor', value: 'Minor'),
                          FilterMenuOption(label: 'Major', value: 'Major'),
                        ],
                        selectedValue: _severityFilter,
                        onChanged: (v) => _refilter(() => _severityFilter = v),
                      ),
                    ],
                    sectionFilter: _sectionPicker,
                  ),
                ],
              ),
            ),
            DashboardTableSection(
              columns: _historyColumns,
              body: students.isEmpty
                  ? DashboardTableEmptyState(
                      icon: Icons.history_rounded,
                      message: widget.cases.isEmpty
                          ? 'No violations on record'
                          : 'No students match your search',
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: EdgeInsets.zero,
                      itemCount: pageStudents.length,
                      itemBuilder: (context, index) {
                        final group = pageStudents[index];
                        return _StudentHistoryRow(
                          key: ValueKey('history-student-${group.studentKey}'),
                          group: group,
                          showDivider: index < pageStudents.length - 1,
                          onTap: () => _openStudent(group),
                        );
                      },
                    ),
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
      ),
    );
  }
}

/// One student's row: who they are, how many violations they have, how many
/// are still open, and their latest one. The whole row opens their history.
class _StudentHistoryRow extends StatelessWidget {
  const _StudentHistoryRow({
    super.key,
    required this.group,
    required this.showDivider,
    required this.onTap,
  });

  final DisciplineStudentGroup group;
  final bool showDivider;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final latest = group.primaryCase;
    final open =
        group.cases.where((c) => violationStatusLabel(c) != 'Resolved').length;
    return DashboardTableRow(
      columns: _historyColumns,
      showDivider: showDivider,
      onTap: onTap,
      cells: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              latest.studentName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: dashboardTablePrimaryStyle(context),
            ),
            Text(
              latest.studentNumber,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: dashboardTableSubStyle(context),
            ),
          ],
        ),
        Text(
          latest.programGradeSection,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: dashboardTableBodyStyle(context),
        ),
        Text(
          '${group.cases.length}',
          style: dashboardTablePrimaryStyle(context),
        ),
        open == 0
            ? Text('—', style: dashboardTableBodyStyle(context))
            : _Pill(
                label: '$open',
                color: _statusColor(context, 'Pending'),
              ),
        Text(
          latest.violationType,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: dashboardTableBodyStyle(context),
        ),
        Row(
          children: [
            Expanded(
              child: Text(
                formatDateTime12h(latest.incidentDateTime),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: dashboardTableMetaStyle(context),
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                size: 20, color: DisciplineOfficerColors.mutedText(context)),
          ],
        ),
      ],
    );
  }
}

/// The popup a student's row opens: who they are, then every violation on
/// their record, newest first, each with its severity, status, when it was
/// filed, by whom, and any notes. Read-only.
class StudentViolationHistorySheet extends StatelessWidget {
  const StudentViolationHistorySheet({super.key, required this.group});

  final DisciplineStudentGroup group;

  @override
  Widget build(BuildContext context) {
    final student = group.primaryCase;
    final open =
        group.cases.where((c) => violationStatusLabel(c) != 'Resolved').length;
    final text = DisciplineOfficerColors.rowText(context);
    final muted = DisciplineOfficerColors.mutedText(context);
    final maxHeight = MediaQuery.of(context).size.height * 0.78;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 0),
              child: AppPopupHeader(
                title: 'Violation History',
                onClose: () => Navigator.of(context).pop(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 8, 22, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    student.studentName,
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [student.studentNumber, student.programGradeSection]
                        .where((p) => p.trim().isNotEmpty)
                        .join('  •  '),
                    style: GoogleFonts.poppins(fontSize: 12, color: muted),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _Pill(
                        label: '${group.cases.length} '
                            '${group.cases.length == 1 ? 'violation' : 'violations'}',
                        color: DisciplineOfficerColors.azureBlue,
                      ),
                      if (open > 0)
                        _Pill(
                          label: '$open open',
                          color: _statusColor(context, 'Pending'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: DisciplineOfficerColors.cardBorder(context)),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(22, 14, 22, 20),
                itemCount: group.cases.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) => _ViolationCard(
                  key: ValueKey('student-history-case-${group.cases[index].id}'),
                  caseItem: group.cases[index],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One violation in a student's history popup.
class _ViolationCard extends StatelessWidget {
  const _ViolationCard({super.key, required this.caseItem});

  final DisciplineCaseModel caseItem;

  @override
  Widget build(BuildContext context) {
    final severity = violationSeverity(caseItem);
    final status = violationStatusLabel(caseItem);
    final text = DisciplineOfficerColors.rowText(context);
    final muted = DisciplineOfficerColors.mutedText(context);
    final small = GoogleFonts.poppins(fontSize: 12, color: muted);
    final description = caseItem.description.trim();
    final penalty = caseItem.penaltyImposed?.trim() ?? '';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: DisciplineOfficerColors.background(context),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            caseItem.violationType,
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: text,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (severity != null)
                _Pill(
                  label: severity,
                  color: severity == 'Major'
                      ? DisciplineOfficerColors.denyRed
                      : const Color(0xFFD97706),
                ),
              _Pill(label: status, color: _statusColor(context, status)),
              if (caseItem.isEscalated)
                const _Pill(
                    label: 'Escalated', color: DisciplineOfficerColors.denyRed),
            ],
          ),
          const SizedBox(height: 10),
          Text(formatDateTime12h(caseItem.incidentDateTime), style: small),
          if (caseItem.submittedBy.trim().isNotEmpty)
            Text('Filed by ${caseItem.submittedBy}', style: small),
          if (description.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(description,
                style: GoogleFonts.poppins(fontSize: 12, height: 1.45, color: text)),
          ],
          if (penalty.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Penalty: $penalty', style: small),
          ],
        ],
      ),
    );
  }
}

Color _statusColor(BuildContext context, String status) {
  final dark = context.isDarkMode;
  switch (status) {
    case 'Resolved':
      return dark ? const Color(0xFF4ADE80) : const Color(0xFF15803D);
    case 'Under Investigation':
      return dark ? const Color(0xFF93C5FD) : const Color(0xFF2563EB);
    default:
      return dark ? const Color(0xFFFDBA74) : const Color(0xFFEA580C);
  }
}

/// A soft-tinted label: [color] text over a faint wash of the same color.
class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color});

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
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.poppins(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
