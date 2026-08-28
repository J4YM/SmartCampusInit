import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/professor_colors.dart';

// ---------------------------------------------------------------------------
// Data models — Supabase (`students` / `student_violations`) ready.
// fromJson()/toJson() map directly onto snake_case Postgres columns so rows
// can be streamed straight into these models once the backend is wired up.
// ---------------------------------------------------------------------------

class ConductStudentModel {
  const ConductStudentModel({
    required this.id,
    required this.name,
    required this.section,
    required this.studentNumber,
    this.previousViolationsCount = 0,
  });

  final String id;
  final String name;
  final String section;
  final String studentNumber;
  final int previousViolationsCount;

  factory ConductStudentModel.fromJson(Map<String, dynamic> json) {
    return ConductStudentModel(
      id: json['id'] as String,
      name: json['name'] as String,
      section: json['section'] as String,
      studentNumber: json['student_number'] as String,
      previousViolationsCount: json['previous_violations_count'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'section': section,
      'student_number': studentNumber,
      'previous_violations_count': previousViolationsCount,
    };
  }
}

/// Today's live conduct-report tally. Defaults to all-zero, matching the
/// Figma frame's empty/pre-session state (mirrors [AttendanceSummaryModel]
/// on the Attendance tab).
class ConductOffenseSummaryModel {
  const ConductOffenseSummaryModel({
    this.minorOffenseCount = 0,
    this.majorOffenseCount = 0,
    this.previousOffenseCount = 0,
  });

  final int minorOffenseCount;
  final int majorOffenseCount;
  final int previousOffenseCount;

  factory ConductOffenseSummaryModel.fromJson(Map<String, dynamic> json) {
    return ConductOffenseSummaryModel(
      minorOffenseCount: json['minor_offense_count'] as int? ?? 0,
      majorOffenseCount: json['major_offense_count'] as int? ?? 0,
      previousOffenseCount: json['previous_offense_count'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'minor_offense_count': minorOffenseCount,
      'major_offense_count': majorOffenseCount,
      'previous_offense_count': previousOffenseCount,
    };
  }
}

/// One selectable entry in the Report panel's violation-type picker — a
/// `handbook_offenses` row reduced to what the UI needs.
class ConductViolationOption {
  const ConductViolationOption({required this.id, required this.label});

  final String id;
  final String label;
}

/// What gets handed to [onSubmit] when the professor submits a report.
class ConductReportSubmission {
  const ConductReportSubmission({
    required this.studentId,
    required this.violationOptionId,
    required this.comments,
  });

  final String studentId;
  final String violationOptionId;
  final String comments;
}

// ---------------------------------------------------------------------------
// Left column — Student List
// ---------------------------------------------------------------------------

class ConductStudentListCard extends StatefulWidget {
  const ConductStudentListCard({
    super.key,
    required this.students,
    required this.totalStudentCount,
    required this.selectedStudentId,
    required this.searchController,
    required this.onSearchChanged,
    required this.onSelect,
  });

  final List<ConductStudentModel> students;
  final int totalStudentCount;
  final String? selectedStudentId;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<ConductStudentModel> onSelect;

  @override
  State<ConductStudentListCard> createState() => _ConductStudentListCardState();
}

class _ConductStudentListCardState extends State<ConductStudentListCard> {
  int get _pageSize => context.isMobileWidth ? 10 : 20;

  int _currentPage = 1;

  @override
  Widget build(BuildContext context) {
    final students = widget.students;
    final totalPages =
        students.isEmpty ? 1 : (students.length / _pageSize).ceil();
    final currentPage = _currentPage.clamp(1, totalPages);
    final pageStudents =
        students.skip((currentPage - 1) * _pageSize).take(_pageSize).toList();

    // Header/search stay fixed; only the list scrolls — as a bounded,
    // real-scrolling Expanded when an ancestor gives this card a fixed
    // height to match its report-panel sibling (the desktop master-detail
    // Row), or as a Flexible that hugs up to whatever's available when it
    // doesn't (mobile/stacked, where the page itself scrolls instead).
    return LayoutBuilder(
      builder: (context, constraints) {
        final bounded = constraints.hasBoundedHeight;
        final Widget list = students.isEmpty
            ? const _StudentListEmptyState()
            : ListView.separated(
                shrinkWrap: !bounded,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                itemCount: pageStudents.length,
                separatorBuilder: (context, index) => const SizedBox(height: 0),
                itemBuilder: (context, index) {
                  final student = pageStudents[index];
                  return _StudentRow(
                    student: student,
                    isSelected: student.id == widget.selectedStudentId,
                    onTap: () => widget.onSelect(student),
                  );
                },
              );

        return Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: ProfessorColors.card(context),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: ProfessorColors.cardBorder(context)),
          ),
          child: Column(
            mainAxisSize: bounded ? MainAxisSize.max : MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(29, 24, 29, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Student List',
                      style: GoogleFonts.poppins(
                        fontSize: context.isMobileWidth ? 16 : 18,
                        fontWeight: FontWeight.w600,
                        color: ProfessorColors.rowText(context),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Total students: ${widget.totalStudentCount}',
                      style: GoogleFonts.poppins(
                        fontSize: context.isMobileWidth ? 11 : 13,
                        fontWeight: FontWeight.w400,
                        color: ProfessorColors.placeholderText(context),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(25, 19, 25, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: _StudentSearchField(
                        controller: widget.searchController,
                        onChanged: (value) {
                          setState(() => _currentPage = 1);
                          widget.onSearchChanged(value);
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    _StudentFilterButton(onTap: () {}),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              bounded ? Expanded(child: list) : Flexible(child: list),
              if (students.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
                  child: CardPaginationFooter(
                    currentPage: currentPage,
                    totalPages: totalPages,
                    totalCount: students.length,
                    textColor: ProfessorColors.placeholderText(context),
                    accentColor: ProfessorColors.azureBlue,
                    mutedBackground: ProfessorColors.background(context),
                    onPrevious: () =>
                        setState(() => _currentPage = currentPage - 1),
                    onNext: () =>
                        setState(() => _currentPage = currentPage + 1),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _StudentSearchField extends StatelessWidget {
  const _StudentSearchField(
      {required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: GoogleFonts.poppins(
          fontSize: context.isMobileWidth ? 11 : 13,
          color: ProfessorColors.rowText(context),
        ),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Search',
          hintStyle: GoogleFonts.poppins(
            fontSize: context.isMobileWidth ? 11 : 13,
            color: ProfessorColors.placeholderText(context),
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            size: 20,
            color: ProfessorColors.placeholderText(context),
          ),
          filled: true,
          fillColor: ProfessorColors.background(context),
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}

class _StudentFilterButton extends StatelessWidget {
  const _StudentFilterButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: ProfessorColors.background(context),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 32,
          width: 107,
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.filter_list_rounded,
                size: 16,
                color: ProfessorColors.placeholderText(context),
              ),
              const SizedBox(width: 6),
              Text(
                'Filter',
                style: GoogleFonts.poppins(
                  fontSize: context.isMobileWidth ? 11 : 13,
                  fontWeight: FontWeight.w400,
                  color: ProfessorColors.placeholderText(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StudentListEmptyState extends StatelessWidget {
  const _StudentListEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'No students found',
        style: GoogleFonts.poppins(
          fontSize: context.isMobileWidth ? 11 : 13,
          fontWeight: FontWeight.w500,
          color: ProfessorColors.mutedText(context),
        ),
      ),
    );
  }
}

class _StudentRow extends StatelessWidget {
  const _StudentRow({
    required this.student,
    required this.isSelected,
    required this.onTap,
  });

  final ConductStudentModel student;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected
          ? ProfessorColors.selectedRow(context)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            border: Border(
                bottom: BorderSide(color: ProfessorColors.cardBorder(context))),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                student.name,
                style: GoogleFonts.poppins(
                  fontSize: context.isMobileWidth ? 12 : 14,
                  fontWeight: FontWeight.w600,
                  color: ProfessorColors.rowText(context),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                student.section,
                style: GoogleFonts.poppins(
                  fontSize: context.isMobileWidth ? 10 : 12,
                  fontWeight: FontWeight.w400,
                  color: ProfessorColors.mutedText(context),
                ),
              ),
              Text(
                student.studentNumber,
                style: GoogleFonts.poppins(
                  fontSize: context.isMobileWidth ? 10 : 12,
                  fontWeight: FontWeight.w400,
                  color: ProfessorColors.mutedText(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Right column — offense stat cards
// ---------------------------------------------------------------------------

class ConductOffenseStatsRow extends StatelessWidget {
  const ConductOffenseStatsRow({super.key, required this.summary});

  final ConductOffenseSummaryModel summary;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 560;
        final cards = [
          _OffenseStatCard(
            label: 'Minor Offense',
            value: '${summary.minorOffenseCount}',
            icon: Icons.error_outline_rounded,
          ),
          _OffenseStatCard(
            label: 'Major Offense',
            value: '${summary.majorOffenseCount}',
            icon: Icons.warning_amber_rounded,
          ),
          _OffenseStatCard(
            label: 'Previous Offense',
            value: '${summary.previousOffenseCount}',
            icon: Icons.history_rounded,
          ),
        ];

        if (isNarrow) {
          return MobileMetricGrid(cards: cards);
        }

        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final card in cards) ...[
                Expanded(child: card),
                if (card != cards.last) const SizedBox(width: 18),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _OffenseStatCard extends StatelessWidget {
  const _OffenseStatCard(
      {required this.label, required this.value, required this.icon});

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(27, 16, 20, 16),
      decoration: BoxDecoration(
        color: ProfessorColors.card(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: ProfessorColors.cardBorder(context)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  label,
                  style: GoogleFonts.poppins(
                    fontSize: context.isMobileWidth ? 10 : 12,
                    fontWeight: FontWeight.w600,
                    color: ProfessorColors.mutedText(context),
                  ),
                ),
                Text(
                  value,
                  style: GoogleFonts.poppins(
                    fontSize: context.isMobileWidth ? 30 : 32,
                    fontWeight: FontWeight.w600,
                    color: ProfessorColors.statValue(context),
                  ),
                ),
              ],
            ),
          ),
          Icon(icon, size: 24, color: ProfessorColors.mutedText(context)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Right column — Report panel
// ---------------------------------------------------------------------------

class ConductReportCard extends StatelessWidget {
  const ConductReportCard({
    super.key,
    required this.selectedStudent,
    required this.violationOptions,
    required this.selectedViolation,
    required this.submittedByName,
    required this.submittedByRole,
    required this.reportDateTime,
    required this.commentsController,
    required this.onViolationSelected,
    required this.onCancel,
    required this.onSubmit,
  });

  final ConductStudentModel? selectedStudent;
  final List<ConductViolationOption> violationOptions;
  final ConductViolationOption? selectedViolation;
  final String submittedByName;
  final String submittedByRole;
  final DateTime reportDateTime;
  final TextEditingController commentsController;
  final ValueChanged<ConductViolationOption> onViolationSelected;
  final VoidCallback onCancel;
  final VoidCallback onSubmit;

  Future<void> _pickViolation(BuildContext context) async {
    // showModalBottomSheet renders into the root Navigator's Overlay, which
    // sits outside the local Theme this page builds around its Scaffold —
    // so the sheet's own context can't see the live dark/light mode via
    // Theme.of. Resolve the tokens up front from this widget's context
    // (which IS nested under that local Theme) and thread the plain Color
    // values down instead.
    final sheetSurface = ProfessorColors.card(context);
    final sheetText = ProfessorColors.rowText(context);

    final choice = await showModalBottomSheet<ConductViolationOption>(
      context: context,
      backgroundColor: sheetSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Choose a violation',
                    style: GoogleFonts.poppins(
                      fontSize: context.isMobileWidth ? 14 : 16,
                      fontWeight: FontWeight.w700,
                      color: sheetText,
                    ),
                  ),
                ),
              ),
              for (final option in violationOptions)
                ListTile(
                  title: Text(
                    option.label,
                    style: GoogleFonts.poppins(
                        fontSize: context.isMobileWidth ? 12 : 14,
                        color: sheetText),
                  ),
                  trailing: option.id == selectedViolation?.id
                      ? const Icon(Icons.check_rounded,
                          color: ProfessorColors.azureBlue)
                      : null,
                  onTap: () => Navigator.of(sheetContext).pop(option),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (choice != null) onViolationSelected(choice);
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit = selectedStudent != null && selectedViolation != null;
    final title = Text(
      'Report',
      style: GoogleFonts.poppins(
        fontSize: context.isMobileWidth ? 16 : 18,
        fontWeight: FontWeight.w600,
        color: ProfessorColors.rowText(context),
      ),
    );
    final middle = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ViolationPickerField(
          label: selectedViolation?.label ?? 'Choose a violation',
          isPlaceholder: selectedViolation == null,
          onTap: () => _pickViolation(context),
        ),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, constraints) {
            final stack = constraints.maxWidth < 640;
            final studentInfo = _InfoCard(
              icon: Icons.person_outline_rounded,
              title: 'Student Information',
              fields: [
                _InfoField(label: 'Name', value: selectedStudent?.name ?? '—'),
                _InfoField(
                  label: 'Student number',
                  value: selectedStudent?.studentNumber ?? '—',
                ),
                _InfoField(
                  label: 'Year & Section',
                  value: selectedStudent?.section ?? '—',
                ),
                _InfoField(
                  label: 'Previous violations',
                  value: selectedStudent == null
                      ? '—'
                      : '${selectedStudent!.previousViolationsCount} violations',
                ),
              ],
            );
            final violationDetails = _InfoCard(
              icon: Icons.menu_book_outlined,
              title: 'Violation Details',
              fields: [
                _InfoField(label: 'Submitted by', value: submittedByName),
                _InfoField(label: 'Role', value: submittedByRole),
                _InfoField(
                  label: 'Date & Time',
                  value: _formatDateTime(reportDateTime),
                ),
              ],
            );

            if (stack) {
              return Column(
                children: [
                  studentInfo,
                  const SizedBox(height: 16),
                  violationDetails,
                ],
              );
            }

            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: studentInfo),
                  const SizedBox(width: 19),
                  Expanded(child: violationDetails),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 160,
          child: _CommentsCard(controller: commentsController),
        ),
      ],
    );
    final actions = Row(
      children: [
        Expanded(
          child: _ActionButton(
            label: 'Cancel',
            color: ProfessorColors.dangerRed,
            icon: Icons.delete_outline_rounded,
            onTap: onCancel,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ActionButton(
            label: 'Submit',
            color: ProfessorColors.successGreen,
            icon: Icons.check_rounded,
            onTap: canSubmit ? onSubmit : null,
          ),
        ),
      ],
    );

    // Title and action buttons stay fixed; when an ancestor gives this
    // card a bounded height to match its student-list sibling (the
    // desktop master-detail Row), the middle content scrolls internally
    // within whatever's left instead of overflowing past a fixed action
    // button row.
    return LayoutBuilder(
      builder: (context, constraints) {
        final bounded = constraints.hasBoundedHeight;
        return Container(
          clipBehavior: Clip.antiAlias,
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
          decoration: BoxDecoration(
            color: ProfessorColors.card(context),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: ProfessorColors.cardBorder(context)),
          ),
          child: Column(
            mainAxisSize: bounded ? MainAxisSize.max : MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              title,
              const SizedBox(height: 18),
              bounded
                  ? Expanded(child: SingleChildScrollView(child: middle))
                  : middle,
              const SizedBox(height: 16),
              actions,
            ],
          ),
        );
      },
    );
  }

  static String _formatDateTime(DateTime dateTime) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final month = months[dateTime.month - 1];
    final hour12 = dateTime.hour % 12 == 0 ? 12 : dateTime.hour % 12;
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final period = dateTime.hour >= 12 ? 'PM' : 'AM';
    return '$month ${dateTime.day}, ${dateTime.year} | $hour12:$minute $period';
  }
}

class _ViolationPickerField extends StatelessWidget {
  const _ViolationPickerField({
    required this.label,
    required this.isPlaceholder,
    required this.onTap,
  });

  final String label;
  final bool isPlaceholder;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: ProfessorColors.card(context),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: ProfessorColors.cardBorder(context)),
          ),
          child: Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                size: 24,
                color: isPlaceholder
                    ? ProfessorColors.mutedText(context)
                    : ProfessorColors.azureBlue,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.poppins(
                    fontSize: context.isMobileWidth ? 12 : 14,
                    fontWeight: FontWeight.w600,
                    color: isPlaceholder
                        ? ProfessorColors.mutedText(context)
                        : ProfessorColors.rowText(context),
                  ),
                ),
              ),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 24,
                color: ProfessorColors.mutedText(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoField {
  const _InfoField({required this.label, required this.value});

  final String label;
  final String value;
}

class _InfoCard extends StatelessWidget {
  const _InfoCard(
      {required this.icon, required this.title, required this.fields});

  final IconData icon;
  final String title;
  final List<_InfoField> fields;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 30),
      decoration: BoxDecoration(
        color: ProfessorColors.card(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: ProfessorColors.cardBorderLight(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: ProfessorColors.rowText(context)),
              const SizedBox(width: 8),
              Text(
                title,
                style: GoogleFonts.poppins(
                  fontSize: context.isMobileWidth ? 12 : 14,
                  fontWeight: FontWeight.w600,
                  color: ProfessorColors.rowText(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 26),
          Wrap(
            runSpacing: 26,
            children: [
              for (var i = 0; i < fields.length; i += 2)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _InfoFieldText(field: fields[i])),
                    if (i + 1 < fields.length)
                      Expanded(child: _InfoFieldText(field: fields[i + 1])),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoFieldText extends StatelessWidget {
  const _InfoFieldText({required this.field});

  final _InfoField field;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          field.label,
          style: GoogleFonts.poppins(
            fontSize: context.isMobileWidth ? 9 : 11,
            fontWeight: FontWeight.w400,
            color: ProfessorColors.mutedText(context),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          field.value,
          style: GoogleFonts.poppins(
            fontSize: context.isMobileWidth ? 11 : 13,
            fontWeight: FontWeight.w500,
            color: ProfessorColors.rowText(context),
          ),
        ),
      ],
    );
  }
}

class _CommentsCard extends StatelessWidget {
  const _CommentsCard({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: ProfessorColors.card(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: ProfessorColors.cardBorderLight(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.chat_bubble_outline_rounded,
                  size: 16, color: ProfessorColors.rowText(context)),
              const SizedBox(width: 8),
              Text(
                'Comments',
                style: GoogleFonts.poppins(
                  fontSize: context.isMobileWidth ? 12 : 14,
                  fontWeight: FontWeight.w600,
                  color: ProfessorColors.rowText(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: ProfessorColors.background(context),
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.all(18),
              child: TextField(
                controller: controller,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                style: GoogleFonts.poppins(
                  fontSize: context.isMobileWidth ? 10 : 12,
                  fontWeight: FontWeight.w400,
                  color: ProfessorColors.rowText(context),
                ),
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: 'Describe the incident…',
                  hintStyle: GoogleFonts.poppins(
                    fontSize: context.isMobileWidth ? 10 : 12,
                    fontWeight: FontWeight.w400,
                    color: ProfessorColors.mutedText(context),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.color,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final Color color;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Material(
      color: enabled ? color : color.withOpacity(0.4),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 33,
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: Colors.white),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: context.isMobileWidth ? 11 : 13,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
