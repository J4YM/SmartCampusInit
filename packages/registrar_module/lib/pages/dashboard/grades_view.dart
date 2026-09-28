import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/registrar_colors.dart';
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
  });

  final List<GradeRecordModel> records;

  /// Called with a record's id and its new grade when the Grade column's
  /// stepper is edited. Falls back to no-op when omitted (demo behavior).
  final void Function(String id, double grade)? onGradeChanged;

  /// Called when "Save Changes" is tapped, once at least one grade has been
  /// edited. Falls back to no-op when omitted (demo behavior).
  final VoidCallback? onSaveChanges;

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

  // Checkbox (multi-select) facets, hierarchy top to bottom Program, Year,
  // Section — parsed out of `gradeSection` (e.g. "BSIT" / "4" / "B" out of
  // "BSIT - 4B"), same pattern as Student Records' own Program/Year/
  // Section filter.
  Set<String> _programFilter = {};
  Set<String> _yearFilter = {};
  Set<String> _sectionFilter = {};

  bool _hasUnsavedChanges = false;

  void _handleGradeChanged(String id, double grade) {
    widget.onGradeChanged?.call(id, grade);
    setState(() => _hasUnsavedChanges = true);
  }

  void _handleSaveChanges() {
    widget.onSaveChanges?.call();
    setState(() => _hasUnsavedChanges = false);
  }

  bool _matchesFilters(GradeRecordModel record) {
    if (_educationLevel != null && record.educationLevel != _educationLevel) {
      return false;
    }
    if (_semester != null && record.semester != _semester) return false;
    if (_programFilter.isNotEmpty &&
        !_programFilter.contains(sectionProgramCode(record.gradeSection))) {
      return false;
    }
    if (_yearFilter.isNotEmpty &&
        !_yearFilter.contains(sectionYearDigit(record.gradeSection))) {
      return false;
    }
    if (_sectionFilter.isNotEmpty &&
        !_sectionFilter.contains(sectionBlockLetter(record.gradeSection))) {
      return false;
    }
    return true;
  }

  /// Only the values actually present in [widget.records] — an empty
  /// bucket in the Filter panel would just be a dead end. Year/Section
  /// narrow with whatever's selected above them in the hierarchy.
  List<String> get _availablePrograms {
    final programs = <String>{
      for (final r in widget.records)
        if (sectionProgramCode(r.gradeSection) != null)
          sectionProgramCode(r.gradeSection)!,
    }.toList();
    programs.sort();
    return programs;
  }

  List<String> get _availableYearDigits {
    final candidates = _programFilter.isEmpty
        ? widget.records
        : widget.records.where(
            (r) => _programFilter.contains(sectionProgramCode(r.gradeSection)));
    final years = <String>{
      for (final r in candidates)
        if (sectionYearDigit(r.gradeSection) != null)
          sectionYearDigit(r.gradeSection)!,
    }.toList();
    years.sort();
    return years;
  }

  List<String> get _availableSectionBlocks {
    final candidates = widget.records.where((r) {
      final matchesProgram = _programFilter.isEmpty ||
          _programFilter.contains(sectionProgramCode(r.gradeSection));
      final matchesYear = _yearFilter.isEmpty ||
          _yearFilter.contains(sectionYearDigit(r.gradeSection));
      return matchesProgram && matchesYear;
    });
    final blocks = <String>{
      for (final r in candidates)
        if (sectionBlockLetter(r.gradeSection) != null)
          sectionBlockLetter(r.gradeSection)!,
    }.toList();
    blocks.sort();
    return blocks;
  }

  void _pruneUnavailableSelections() {
    _yearFilter = _yearFilter.intersection(_availableYearDigits.toSet());
    _sectionFilter =
        _sectionFilter.intersection(_availableSectionBlocks.toSet());
  }

  /// Passed to [FilterMenuButton] as a *builder* — see that param's own
  /// doc comment for why a plain list can't stay current while the panel
  /// is open.
  List<FilterMenuCheckboxSection> _buildCheckboxSections() => [
        FilterMenuCheckboxSection(
          title: 'Program',
          options: [
            for (final program in _availablePrograms)
              FilterMenuOption(label: program, value: program),
          ],
          selectedValues: _programFilter,
          onChanged: (value) => setState(() {
            _programFilter = value;
            _currentPage = 1;
            _pruneUnavailableSelections();
          }),
        ),
        FilterMenuCheckboxSection(
          title: 'Year',
          options: [
            for (final digit in _availableYearDigits)
              FilterMenuOption(label: yearLabelForDigit(digit), value: digit),
          ],
          selectedValues: _yearFilter,
          onChanged: (value) => setState(() {
            _yearFilter = value;
            _currentPage = 1;
            _pruneUnavailableSelections();
          }),
        ),
        FilterMenuCheckboxSection(
          title: 'Section',
          options: [
            for (final block in _availableSectionBlocks)
              FilterMenuOption(label: block, value: block),
          ],
          selectedValues: _sectionFilter,
          onChanged: (value) => setState(() {
            _sectionFilter = value;
            _currentPage = 1;
          }),
        ),
      ];

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
      checkboxSectionsBuilder: _buildCheckboxSections,
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
    required this.checkboxSectionsBuilder,
  });

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

  /// Builds the Program/Year/Section checkbox facets — see
  /// [FilterMenuButton.checkboxSections]'s own doc comment for why this is
  /// a builder rather than a plain list.
  final List<FilterMenuCheckboxSection> Function() checkboxSectionsBuilder;

  @override
  Widget build(BuildContext context) {
    final headerStyle = GoogleFonts.poppins(
      fontSize: context.isMobileWidth ? 10 : 12,
      fontWeight: FontWeight.w600,
      color: Colors.white,
    );

    final uploadButton = UploadSpreadsheetButton(
      accentColor: RegistrarColors.azureBlue,
      backgroundColor: RegistrarColors.background(context),
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
      checkboxSections: checkboxSectionsBuilder,
    );
    final saveButton =
        SaveChangesButton(enabled: hasUnsavedChanges, onTap: onSaveChanges);

    return LayoutBuilder(
      builder: (context, constraints) {
        final bounded = constraints.hasBoundedHeight;
        final Widget list = records.isEmpty
            ? Center(
                child: Text(
                  hasUnfilteredRecords
                      ? 'No students match the selected filters'
                      : 'No grade records yet',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: RegistrarColors.mutedText(context),
                  ),
                ),
              )
            : ListView.builder(
                shrinkWrap: !bounded,
                itemCount: records.length,
                itemBuilder: (context, index) => _GradeRow(
                  record: records[index],
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
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [uploadButton, filterButton, saveButton],
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Student List',
                              style: GoogleFonts.poppins(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: RegistrarColors.rowText(context),
                              ),
                            ),
                          ),
                          uploadButton,
                          const SizedBox(width: 10),
                          filterButton,
                          const SizedBox(width: 10),
                          saveButton,
                        ],
                      ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                color: RegistrarColors.navyBlue,
                child: Row(
                  children: [
                    Expanded(
                        flex: 2, child: Text('Student', style: headerStyle)),
                    Expanded(
                        flex: 2, child: Text('Student ID', style: headerStyle)),
                    Expanded(
                        flex: 2, child: Text('Subject', style: headerStyle)),
                    Expanded(
                        flex: 2,
                        child: Text('Grade & Section', style: headerStyle)),
                    Expanded(child: Text('Grade', style: headerStyle)),
                    Expanded(
                      child: Text(
                        'Remarks',
                        textAlign: TextAlign.center,
                        style: headerStyle,
                      ),
                    ),
                  ],
                ),
              ),
              bounded ? Expanded(child: list) : Flexible(child: list),
              if (records.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                  child: PillPaginationFooter(
                    shownCount: records.length,
                    totalCount: totalCount,
                    label: 'total student grade records',
                    canGoPrevious: currentPage > 1,
                    canGoNext: currentPage < totalPages,
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

class _GradeRow extends StatelessWidget {
  const _GradeRow({required this.record, this.onGradeChanged});

  final GradeRecordModel record;
  final void Function(String id, double grade)? onGradeChanged;

  @override
  Widget build(BuildContext context) {
    final style = GoogleFonts.poppins(
      fontSize: context.isMobileWidth ? 11 : 13,
      fontWeight: FontWeight.w500,
      color: RegistrarColors.rowText(context),
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        border: Border(
            bottom: BorderSide(color: RegistrarColors.cardBorder(context))),
      ),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text(record.studentName, style: style)),
          Expanded(flex: 2, child: Text(record.studentId, style: style)),
          Expanded(flex: 2, child: Text(record.subject, style: style)),
          Expanded(flex: 2, child: Text(record.gradeSection, style: style)),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: _GradeStepper(
                value: record.grade,
                onChanged: (grade) => onGradeChanged?.call(record.id, grade),
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: record.remark.badgeBackground,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  record.remark.label,
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: record.remark.badgeText,
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
