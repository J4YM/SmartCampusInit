import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/registrar_colors.dart';
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

  Color get badgeBackground => switch (this) {
        GradeRemark.outstanding => const Color(0xFFE6F4EA),
        GradeRemark.verySatisfactory => const Color(0x33345892),
        GradeRemark.satisfactory => const Color(0x33FFCC00),
        GradeRemark.failing => const Color(0x33CD4855),
      };

  Color get badgeText => switch (this) {
        GradeRemark.outstanding => RegistrarColors.successGreen,
        GradeRemark.verySatisfactory => RegistrarColors.brightBlue,
        GradeRemark.satisfactory => const Color(0xFF279142),
        GradeRemark.failing => RegistrarColors.dangerRed,
      };

  static GradeRemark fromValue(String? value) => switch (value) {
        'Very Satisfactory' => GradeRemark.verySatisfactory,
        'Satisfactory' => GradeRemark.satisfactory,
        'Failing' => GradeRemark.failing,
        _ => GradeRemark.outstanding,
      };

  /// Computes the remark directly from a numeric grade — used by real data
  /// (RegistrarRepository.fetchGradeRecords), which never stores or reads a
  /// remark string. 75 matches GradesView's own passing-rate threshold.
  static GradeRemark fromGrade(double grade) {
    if (grade < 75) return GradeRemark.failing;
    if (grade >= 90) return GradeRemark.outstanding;
    if (grade >= 85) return GradeRemark.verySatisfactory;
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
    this.onGradeChanged,
    this.onSaveChanges,
    this.onImportGpaRecords,
  });

  final List<GradeRecordModel> records;

  /// Called with a record's id and its new grade when the Grade column's
  /// stepper is edited. Falls back to no-op when omitted (demo behavior).
  final void Function(String id, double grade)? onGradeChanged;

  /// Called when "Save Changes" is tapped, once at least one grade has been
  /// edited. Falls back to no-op when omitted (demo behavior).
  final VoidCallback? onSaveChanges;

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

  bool _hasUnsavedChanges = false;

  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _handleGradeChanged(String id, double grade) {
    widget.onGradeChanged?.call(id, grade);
    setState(() => _hasUnsavedChanges = true);
  }

  void _handleSaveChanges() {
    widget.onSaveChanges?.call();
    setState(() => _hasUnsavedChanges = false);
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

    final average = records.isEmpty
        ? 0.0
        : records.map((r) => r.grade).reduce((a, b) => a + b) / records.length;
    final highest = records.isEmpty
        ? 0.0
        : records.map((r) => r.grade).reduce((a, b) => a > b ? a : b);
    final lowest = records.isEmpty
        ? 0.0
        : records.map((r) => r.grade).reduce((a, b) => a < b ? a : b);
    final passingRate = records.isEmpty
        ? 0.0
        : records.where((r) => r.grade >= 75).length / records.length * 100;

    final statCards = [
      _GradeStatCard(
        label: 'Class Average',
        value: average.toStringAsFixed(1),
        icon: Icons.checklist_rtl_rounded,
      ),
      _GradeStatCard(
        label: 'Highest Grade',
        value: highest.toStringAsFixed(1),
        icon: Icons.arrow_upward_rounded,
      ),
      _GradeStatCard(
        label: 'Lowest Grade',
        value: lowest.toStringAsFixed(1),
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
      onGradeChanged: _handleGradeChanged,
      hasUnfilteredRecords: widget.records.isNotEmpty,
      hasUnsavedChanges: _hasUnsavedChanges,
      onSaveChanges: _handleSaveChanges,
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
    this.onGradeChanged,
    this.hasUnfilteredRecords = true,
    this.hasUnsavedChanges = false,
    this.onSaveChanges,
    required this.educationLevel,
    required this.onEducationLevelChanged,
    required this.semester,
    required this.onSemesterChanged,
    required this.sectionFilter,
    this.onGpaFileSelected,
    required this.searchController,
    required this.onSearchChanged,
  });

  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;

  final List<GradeRecordModel> records;
  final int totalCount;
  final int currentPage;
  final int totalPages;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final void Function(String id, double grade)? onGradeChanged;

  /// Whether the tab has any records at all before the Filter button's
  /// selection is applied — lets the empty state tell "no data" apart from
  /// "no rows match this filter".
  final bool hasUnfilteredRecords;

  /// True once at least one grade has been edited since the last save —
  /// "Save Changes" stays disabled until there's something to save.
  final bool hasUnsavedChanges;
  final VoidCallback? onSaveChanges;

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
    final saveButton =
        SaveChangesButton(enabled: hasUnsavedChanges, onTap: onSaveChanges);

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
        final Widget list = records.isEmpty
            ? DashboardTableEmptyState(
                message: hasUnfilteredRecords
                    ? 'No students match your search or filters'
                    : 'No grade records yet',
              )
            : ListView.builder(
                shrinkWrap: !bounded,
                padding: EdgeInsets.zero,
                itemCount: records.length,
                itemBuilder: (context, index) => _GradeRow(
                  record: records[index],
                  showDivider: index < records.length - 1,
                  onGradeChanged: onGradeChanged,
                ),
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
                            children: [filterButton, uploadButton, saveButton],
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
                                  const SizedBox(width: 10),
                                  saveButton,
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
                              const SizedBox(width: 10),
                              saveButton,
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
  DashboardTableColumn('Student', flex: 2),
  DashboardTableColumn('Student ID', flex: 2),
  DashboardTableColumn('Subject', flex: 2),
  DashboardTableColumn('Grade & Section', flex: 2),
  // Fixed: the editable grade box (padding + 32px field + arrows) needs 66px,
  // and a flex share of a narrow table is less than that.
  DashboardTableColumn('Grade', width: 68),
  DashboardTableColumn('Remarks', flex: 1, compact: true),
];

class _GradeRow extends StatelessWidget {
  const _GradeRow({
    required this.record,
    required this.showDivider,
    this.onGradeChanged,
  });

  final GradeRecordModel record;
  final bool showDivider;
  final void Function(String id, double grade)? onGradeChanged;

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
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: dashboardTableBodyStyle(context),
        ),
        Text(
          record.gradeSection,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: dashboardTableBodyStyle(context),
        ),
        _GradeStepper(
          value: record.grade,
          onChanged: (grade) => onGradeChanged?.call(record.id, grade),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: record.remark.badgeBackground,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            record.remark.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.poppins(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: record.remark.badgeText,
            ),
          ),
        ),
      ],
    );
  }
}

/// Editable grade cell — typing a number or tapping the up/down arrows both
/// commit through [onChanged], clamped to a 0-100 scale.
class _GradeStepper extends StatefulWidget {
  const _GradeStepper({required this.value, required this.onChanged});

  final double value;
  final ValueChanged<double> onChanged;

  @override
  State<_GradeStepper> createState() => _GradeStepperState();
}

class _GradeStepperState extends State<_GradeStepper> {
  late final _controller = TextEditingController(text: _format(widget.value));

  static String _format(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);

  @override
  void didUpdateWidget(covariant _GradeStepper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _controller.text = _format(widget.value);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _commit(String text) {
    final parsed = double.tryParse(text);
    if (parsed == null) {
      _controller.text = _format(widget.value);
      return;
    }
    final clamped = parsed.clamp(0, 100).toDouble();
    _controller.text = _format(clamped);
    if (clamped != widget.value) widget.onChanged(clamped);
  }

  void _step(double delta) {
    final next = (widget.value + delta).clamp(0, 100).toDouble();
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final style = GoogleFonts.poppins(
      fontSize: context.isMobileWidth ? 11 : 13,
      fontWeight: FontWeight.w500,
      color: RegistrarColors.rowText(context),
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: RegistrarColors.background(context),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 32,
            child: TextField(
              controller: _controller,
              style: style,
              textAlign: TextAlign.center,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(
                    RegExp(r'^\d{0,3}(\.\d{0,1})?$')),
              ],
              decoration: const InputDecoration(
                isDense: true,
                isCollapsed: true,
                border: InputBorder.none,
              ),
              onSubmitted: _commit,
              onTapOutside: (_) => _commit(_controller.text),
            ),
          ),
          const SizedBox(width: 4),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _GradeStepperArrow(
                icon: Icons.keyboard_arrow_up_rounded,
                tooltip: 'Increase grade',
                onTap: () => _step(1),
              ),
              _GradeStepperArrow(
                icon: Icons.keyboard_arrow_down_rounded,
                tooltip: 'Decrease grade',
                onTap: () => _step(-1),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GradeStepperArrow extends StatelessWidget {
  const _GradeStepperArrow({
    required this.icon,
    required this.onTap,
    required this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        child: Icon(icon, size: 14, color: RegistrarColors.mutedText(context)),
      ),
    );
  }
}
