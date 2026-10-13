import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/registrar_colors.dart';
import 'gwa_entry_dialog.dart';
import 'import_gpa_records_dialog.dart';
import 'registrar_dashboard_page.dart';

// ---------------------------------------------------------------------------
// Data models
// ---------------------------------------------------------------------------

/// How a grade reads against the school's remarks scale, shown as a colored
/// pill next to the numeric grade.
enum GradeRemark {
  outstanding,
  verySatisfactory,
  satisfactory,
  failing;

  String get label => switch (this) {
        GradeRemark.outstanding => 'Outstanding',
        GradeRemark.verySatisfactory => 'Very Satisfactory',
        GradeRemark.satisfactory => 'Satisfactory',
        GradeRemark.failing => 'Failing',
      };

  /// The pill's fill and label for the current theme. "Outstanding" is the
  /// shared success pill, so it is soft on a dark card.
  (Color, Color) badgeColors(BuildContext context) => switch (this) {
        GradeRemark.outstanding => StatusPillColors.success(context),
        GradeRemark.verySatisfactory =>
          (const Color(0x33345892), RegistrarColors.brightBlue),
        GradeRemark.satisfactory =>
          (const Color(0x33FFCC00), const Color(0xFF279142)),
        GradeRemark.failing =>
          (const Color(0x33CD4855), RegistrarColors.dangerRed),
      };

  static GradeRemark fromValue(String? value) => switch (value) {
        'Very Satisfactory' => GradeRemark.verySatisfactory,
        'Satisfactory' => GradeRemark.satisfactory,
        'Failing' => GradeRemark.failing,
        _ => GradeRemark.outstanding,
      };

  /// Computes the remark directly from a numeric grade — used by real data
  /// (RegistrarRepository.fetchGradeRecords), which never stores or reads a
  /// remark string. Philippine college scale: 1.00-5.00, 1.00 = best,
  /// lower is better — inverted from (and not to be confused with) a 0-100
  /// percentage scale. 3.00 matches both GradesView's own passing-rate
  /// threshold and the highest breakpoint gwaToPercentage
  /// (lib/data/guidance_counselor_repository.dart) defines, the school's
  /// established lowest-passing-grade cutoff.
  static GradeRemark fromGrade(double grade) {
    if (grade > 3.00) return GradeRemark.failing;
    if (grade <= 1.50) return GradeRemark.outstanding;
    if (grade <= 2.00) return GradeRemark.verySatisfactory;
    return GradeRemark.satisfactory;
  }
}

class GradeRecordModel {
  const GradeRecordModel({
    required this.id,
    required this.studentName,
    required this.studentId,
    required this.gradeSection,
    required this.subject,
    required this.grade,
    required this.remark,
    this.educationLevel = 'College',
    this.semester = '1st',
  });

  final String id;
  final String studentName;
  final String studentId;
  final String gradeSection;
  final String subject;
  final double grade;
  final GradeRemark remark;

  /// 'Senior High School' or 'College' — matches the Filter panel's
  /// Education Level toggle.
  final String educationLevel;

  /// '1st' or '2nd' — matches the Filter panel's Semester toggle.
  final String semester;

  factory GradeRecordModel.fromJson(Map<String, dynamic> json) {
    return GradeRecordModel(
      id: json['id'] as String,
      studentName: json['student_name'] as String,
      studentId: json['student_id'] as String? ?? '',
      gradeSection: json['grade_section'] as String? ?? '',
      subject: json['subject'] as String? ?? '',
      grade: (json['grade'] as num?)?.toDouble() ?? 0,
      remark: GradeRemark.fromValue(json['remark'] as String?),
      educationLevel: json['education_level'] as String? ?? 'College',
      semester: json['semester'] as String? ?? '1st',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'student_name': studentName,
      'student_id': studentId,
      'grade_section': gradeSection,
      'subject': subject,
      'grade': grade,
      'remark': remark.label,
      'education_level': educationLevel,
      'semester': semester,
    };
  }

  GradeRecordModel copyWith({double? grade}) {
    final newGrade = grade ?? this.grade;
    return GradeRecordModel(
      id: id,
      studentName: studentName,
      studentId: studentId,
      gradeSection: gradeSection,
      subject: subject,
      grade: newGrade,
      remark: GradeRemark.fromGrade(newGrade),
      educationLevel: educationLevel,
      semester: semester,
    );
  }
}

// ---------------------------------------------------------------------------
// Grades tab — stat cards + Student List + Filter panel.
// ---------------------------------------------------------------------------

class GradesView extends StatefulWidget {
  const GradesView({
    super.key,
    required this.records,
    this.onImportGpaRecords,
    this.students = const [],
    this.onSaveGwa,
  });

  /// Every student on file — the "Enter GWA" dialog's course/section filters
  /// and picker are built from these.
  final List<RegistrarStudentModel> students;

  /// Saves one student's manually entered GWA and returns the "school year /
  /// term" it was filed under. No "Enter GWA" button when omitted.
  final Future<String> Function(String studentId, double gwa)? onSaveGwa;

  /// The Grade column is read-only: grades come from the records themselves
  /// (the GPA upload), never typed in here.
  final List<GradeRecordModel> records;

  /// Runs a GPA-records batch upload (see GradeImportRunner,
  /// lib/data/grade_import_runner.dart) — a separate concept from the
  /// per-subject grades this tab otherwise shows/edits; see
  /// add_student_gpa_records_schema.sql's own comment for why. Falls back
  /// to the upload button's generic "Selected x.xlsx" demo snackbar when
  /// omitted, same as every other optional callback on this page.
  final Future<ImportGpaRecordsResult> Function({required PlatformFile file})?
      onImportGpaRecords;

  @override
  State<GradesView> createState() => _GradesViewState();
}

class _GradesViewState extends State<GradesView> {
  int get _pageSize => context.cardPageSize;
  int _currentPage = 1;

  // Single-select facets — "All" (null) shows every level/semester, same
  // convention as every other dashboard's own single-select filters
  // (Status, Risk Level, Severity, …).
  String? _educationLevel;
  String? _semester;

  /// The one section picked in the Filter popup (its full `gradeSection`
  /// string), or null for "All sections".
  String? _sectionFilter;

  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _handleGpaFileSelected(PlatformFile file) {
    final onImportGpaRecords = widget.onImportGpaRecords;
    if (onImportGpaRecords == null) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ImportGpaRecordsResultDialog(
        onImport: () => onImportGpaRecords(file: file),
      ),
    );
  }

  void _openGwaEntry() {
    final onSaveGwa = widget.onSaveGwa;
    if (onSaveGwa == null) return;
    final theme = Theme.of(context);
    showDialog<void>(
      context: context,
      builder: (_) => Theme(
        data: theme,
        child: GwaEntryDialog(students: widget.students, onSave: onSaveGwa),
      ),
    );
  }

  bool _matchesFilters(GradeRecordModel record) {
    if (_educationLevel != null && record.educationLevel != _educationLevel) {
      return false;
    }
    if (_semester != null && record.semester != _semester) return false;
    if (!matchesSearchQuery(_query, [
      record.studentName,
      record.studentId,
      record.subject,
      record.gradeSection,
    ])) {
      return false;
    }
    if (!matchesSectionFilter(_sectionFilter, record.gradeSection)) {
      return false;
    }
    return true;
  }

  /// The Filter popup's section list — every section with grade records.
  FilterSectionPicker get _sectionPicker => FilterSectionPicker(
        entries: sectionFilterEntries(
            [for (final r in widget.records) (r.gradeSection, null)]),
        selectedId: _sectionFilter,
        onChanged: (id) => setState(() {
          _sectionFilter = id;
          _currentPage = 1;
        }),
      );

  @override
  Widget build(BuildContext context) {
    final records = widget.records.where(_matchesFilters).toList();
    final totalPages =
        records.isEmpty ? 1 : (records.length / _pageSize).ceil();
    final currentPage = _currentPage.clamp(1, totalPages);
    final pageRecords =
        records.skip((currentPage - 1) * _pageSize).take(_pageSize).toList();

    // 1.00-5.00, 1.00 = best — the numeric minimum is the class's best
    // grade and the numeric maximum is its weakest, the opposite of a
    // 0-100 scale. Card labels below are named for what they mean
    // ("Best"/"Weakest"), not for the min/max direction, so this doesn't
    // read backwards next to "Highest"/"Lowest" wording.
    final average = records.isEmpty
        ? 0.0
        : records.map((r) => r.grade).reduce((a, b) => a + b) / records.length;
    final best = records.isEmpty
        ? 0.0
        : records.map((r) => r.grade).reduce((a, b) => a < b ? a : b);
    final weakest = records.isEmpty
        ? 0.0
        : records.map((r) => r.grade).reduce((a, b) => a > b ? a : b);
    final passingRate = records.isEmpty
        ? 0.0
        : records.where((r) => r.grade <= 3.00).length / records.length * 100;

    final statCards = [
      _GradeStatCard(
        label: 'Class Average',
        value: average.toStringAsFixed(2),
        icon: Icons.checklist_rtl_rounded,
      ),
      _GradeStatCard(
        label: 'Best Grade',
        value: best.toStringAsFixed(2),
        icon: Icons.arrow_upward_rounded,
      ),
      _GradeStatCard(
        label: 'Weakest Grade',
        value: weakest.toStringAsFixed(2),
        icon: Icons.arrow_downward_rounded,
      ),
      _GradeStatCard(
        label: 'Passing Rate',
        value: '${passingRate.round()}%',
        icon: Icons.trending_up_rounded,
      ),
    ];

    final statsRow = LayoutBuilder(
      builder: (context, constraints) {
        if (context.isMobileWidth) return MobileMetricGrid(cards: statCards);
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final card in statCards) ...[
                Expanded(child: card),
                if (card != statCards.last) const SizedBox(width: 18),
              ],
            ],
          ),
        );
      },
    );

    final listCard = _GradesListCard(
      records: pageRecords,
      totalCount: records.length,
      currentPage: currentPage,
      totalPages: totalPages,
      onPrevious: () => setState(() => _currentPage = currentPage - 1),
      onNext: () => setState(() => _currentPage = currentPage + 1),
      hasUnfilteredRecords: widget.records.isNotEmpty,
      educationLevel: _educationLevel,
      onEducationLevelChanged: (v) => setState(() {
        _educationLevel = v;
        _currentPage = 1;
      }),
      semester: _semester,
      onSemesterChanged: (v) => setState(() {
        _semester = v;
        _currentPage = 1;
      }),
      sectionFilter: _sectionPicker,
      onGpaFileSelected: _handleGpaFileSelected,
      onEnterGwa: widget.onSaveGwa == null ? null : _openGwaEntry,
      searchController: _searchController,
      onSearchChanged: (value) => setState(() {
        _query = value;
        _currentPage = 1;
      }),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            statsRow,
            const SizedBox(height: 18),
            listCard,
          ],
        );
      },
    );
  }
}

class _GradeStatCard extends StatelessWidget {
  const _GradeStatCard(
      {required this.label, required this.value, required this.icon});

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return BentoCard(
      backgroundColor: RegistrarColors.card(context),
      borderColor: RegistrarColors.cardBorder(context),
      padding: const EdgeInsets.fromLTRB(27, 16, 20, 16),
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
                    color: RegistrarColors.mutedText(context),
                  ),
                ),
                Text(
                  value,
                  style: GoogleFonts.poppins(
                    fontSize: context.isMobileWidth ? 26 : 32,
                    fontWeight: FontWeight.w600,
                    color: RegistrarColors.statValue(context),
                  ),
                ),
              ],
            ),
          ),
          Icon(icon, size: 24, color: RegistrarColors.mutedText(context)),
        ],
      ),
    );
  }
}

class _GradesListCard extends StatelessWidget {
  const _GradesListCard({
    required this.records,
    required this.totalCount,
    required this.currentPage,
    required this.totalPages,
    required this.onPrevious,
    required this.onNext,
    this.hasUnfilteredRecords = true,
    required this.educationLevel,
    required this.onEducationLevelChanged,
    required this.semester,
    required this.onSemesterChanged,
    required this.sectionFilter,
    this.onGpaFileSelected,
    this.onEnterGwa,
    required this.searchController,
    required this.onSearchChanged,
  });

  /// Opens the manual GWA entry dialog; no button when null.
  final VoidCallback? onEnterGwa;

  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;

  final List<GradeRecordModel> records;
  final int totalCount;
  final int currentPage;
  final int totalPages;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  /// Whether the tab has any records at all before the Filter button's
  /// selection is applied — lets the empty state tell "no data" apart from
  /// "no rows match this filter".
  final bool hasUnfilteredRecords;

  final String? educationLevel;
  final ValueChanged<String?> onEducationLevelChanged;
  final String? semester;
  final ValueChanged<String?> onSemesterChanged;

  /// The Filter popup's section list (single section or "All sections").
  final FilterSectionPicker sectionFilter;

  /// Called with the picked file for a GPA-records upload — see
  /// [GradesView.onImportGpaRecords]'s own doc comment.
  final ValueChanged<PlatformFile>? onGpaFileSelected;

  @override
  Widget build(BuildContext context) {
    final uploadButton = UploadSpreadsheetButton(
      accentColor: RegistrarColors.azureBlue,
      backgroundColor: RegistrarColors.background(context),
      label: 'Upload GPA Records',
      tooltip: 'Upload GPA Records',
      onFileSelected: onGpaFileSelected,
    );
    final gwaButton = onEnterGwa == null
        ? null
        : RegistrarPillButton(
            label: 'Enter GWA',
            icon: Icons.edit_note_rounded,
            onTap: onEnterGwa,
          );
    final filterButton = FilterMenuButton(
      backgroundColor: RegistrarColors.background(context),
      menuColor: RegistrarColors.card(context),
      borderColor: RegistrarColors.cardBorder(context),
      iconColor: RegistrarColors.placeholderText(context),
      textColor: RegistrarColors.rowText(context),
      mutedTextColor: RegistrarColors.mutedText(context),
      accentColor: RegistrarColors.azureBlue,
      sections: [
        FilterMenuSection(
          title: 'Education Level',
          options: const [
            FilterMenuOption(label: 'College', value: 'College'),
            FilterMenuOption(
                label: 'Senior High School', value: 'Senior High School'),
          ],
          selectedValue: educationLevel,
          onChanged: onEducationLevelChanged,
        ),
        FilterMenuSection(
          title: 'Semester',
          options: const [
            FilterMenuOption(label: '1st', value: '1st'),
            FilterMenuOption(label: '2nd', value: '2nd'),
          ],
          selectedValue: semester,
          onChanged: onSemesterChanged,
        ),
      ],
      sectionFilter: sectionFilter,
    );
    final searchField = SearchField(
      controller: searchController,
      hintText: 'Search students',
      onChanged: onSearchChanged,
    );
    final desktopTitle = Text(
      'Student List',
      style: GoogleFonts.poppins(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: RegistrarColors.rowText(context),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final bounded = constraints.hasBoundedHeight;
        final Widget list = DashboardTableRows(
          scrollable: true,
          shrinkWrap: !bounded,
          empty: DashboardTableEmptyState(
            message: hasUnfilteredRecords
                ? 'No students match your search or filters'
                : 'No grade records yet',
          ),
          rows: [
            for (var index = 0; index < records.length; index++)
              _GradeRow(
                key: ValueKey('grade-${records[index].id}'),
                record: records[index],
                showDivider: index < records.length - 1,
              ),
          ],
        );

        return BentoCard(
          backgroundColor: RegistrarColors.card(context),
          borderColor: RegistrarColors.cardBorder(context),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: bounded ? MainAxisSize.max : MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                child: context.isMobileWidth
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Student List',
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: RegistrarColors.rowText(context),
                            ),
                          ),
                          const SizedBox(height: 12),
                          MaxWidthAligned(child: searchField),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              filterButton,
                              uploadButton,
                              if (gwaButton != null) gwaButton,
                            ],
                          ),
                        ],
                      )
                    // Title, search and the three buttons only share a line
                    // when the card is wide enough; otherwise the search
                    // takes its own line under the title row.
                    : constraints.maxWidth < 900
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Expanded(child: desktopTitle),
                                  filterButton,
                                  const SizedBox(width: 10),
                                  uploadButton,
                                  if (gwaButton != null) ...[
                                    const SizedBox(width: 10),
                                    gwaButton,
                                  ],
                                ],
                              ),
                              const SizedBox(height: 12),
                              MaxWidthAligned(child: searchField),
                            ],
                          )
                        : Row(
                            children: [
                              desktopTitle,
                              const SizedBox(width: 16),
                              Expanded(
                                child: MaxWidthAligned(
                                  alignment: Alignment.centerRight,
                                  child: searchField,
                                ),
                              ),
                              const SizedBox(width: 10),
                              filterButton,
                              const SizedBox(width: 10),
                              uploadButton,
                              if (gwaButton != null) ...[
                                const SizedBox(width: 10),
                                gwaButton,
                              ],
                            ],
                          ),
              ),
              DashboardTableSection(
                columns: _gradeColumns,
                expandBody: bounded,
                body: list,
              ),
              if (records.isNotEmpty)
                DashboardTableFooter(
                  child: CardPaginationFooter(
                    currentPage: currentPage,
                    totalPages: totalPages,
                    totalCount: totalCount,
                    textColor: RegistrarColors.mutedText(context),
                    accentColor: RegistrarColors.azureBlue,
                    mutedBackground: RegistrarColors.background(context),
                    onPrevious: onPrevious,
                    onNext: onNext,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

const _gradeColumns = <DashboardTableColumn>[
  DashboardTableColumn('Student', flex: 2, minWidth: 220),
  DashboardTableColumn('Student ID', flex: 2, minWidth: 120),
  DashboardTableColumn('Subject', flex: 2, minWidth: 220),
  DashboardTableColumn('Grade & Section', flex: 2, minWidth: 150),
  DashboardTableColumn('Grade', width: 74),
  DashboardTableColumn('Remarks', flex: 1, compact: true, minWidth: 120),
];

class _GradeRow extends StatelessWidget {
  const _GradeRow({
    super.key,
    required this.record,
    required this.showDivider,
  });

  final GradeRecordModel record;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return DashboardTableRow(
      columns: _gradeColumns,
      showDivider: showDivider,
      cells: [
        Text(
          record.studentName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: dashboardTablePrimaryStyle(context),
        ),
        Text(
          record.studentId,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: dashboardTableIdStyle(context),
        ),
        Text(
          record.subject,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: dashboardTableBodyStyle(context),
        ),
        Text(
          record.gradeSection,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: dashboardTableBodyStyle(context),
        ),
        // Read-only: always 2 decimals (1.00 best … 5.00), no stepper.
        Text(
          record.grade.toStringAsFixed(2),
          key: ValueKey('grade-value-${record.id}'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: dashboardTablePrimaryStyle(context),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: record.remark.badgeColors(context).$1,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            record.remark.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.poppins(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: record.remark.badgeColors(context).$2,
            ),
          ),
        ),
      ],
    );
  }
}
