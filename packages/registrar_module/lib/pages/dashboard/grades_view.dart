import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/registrar_colors.dart';
import 'registrar_dashboard_page.dart';

/// Sentinel [_GradesViewState._yearLevel]/[_GradesFilterCard.yearLevel]
/// value meaning "don't filter by year level" — matches the Filter panel's
/// own "All Years" pill below the 1st–4th grid.
const _allYears = 'All Years';

/// Sentinel [_GradesViewState._section]/[_GradesFilterCard.section] value
/// meaning "don't filter by section" — matches the Filter panel's own "All
/// Sections" pill below the A/B/C row.
const _allSections = 'All Sections';

// ---------------------------------------------------------------------------
// Data models
// ---------------------------------------------------------------------------

/// How a grade reads against the school's remarks scale, shown as a colored
/// pill next to the numeric grade.
enum GradeRemark {
  outstanding,
  verySatisfactory,
  satisfactory;

  String get label => switch (this) {
        GradeRemark.outstanding => 'Outstanding',
        GradeRemark.verySatisfactory => 'Very Satisfactory',
        GradeRemark.satisfactory => 'Satisfactory',
      };

  Color get badgeBackground => switch (this) {
        GradeRemark.outstanding => const Color(0xFFE6F4EA),
        GradeRemark.verySatisfactory => const Color(0x33345892),
        GradeRemark.satisfactory => const Color(0x33FFCC00),
      };

  Color get badgeText => switch (this) {
        GradeRemark.outstanding => RegistrarColors.successGreen,
        GradeRemark.verySatisfactory => RegistrarColors.brightBlue,
        GradeRemark.satisfactory => const Color(0xFF279142),
      };

  static GradeRemark fromValue(String? value) => switch (value) {
        'Very Satisfactory' => GradeRemark.verySatisfactory,
        'Satisfactory' => GradeRemark.satisfactory,
        _ => GradeRemark.outstanding,
      };
}

class GradeRecordModel {
  const GradeRecordModel({
    required this.id,
    required this.studentName,
    required this.studentId,
    required this.gradeSection,
    required this.grade,
    required this.remark,
    this.educationLevel = 'College',
    this.semester = '1st',
  });

  final String id;
  final String studentName;
  final String studentId;
  final String gradeSection;
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
      'grade': grade,
      'remark': remark.label,
      'education_level': educationLevel,
      'semester': semester,
    };
  }

  GradeRecordModel copyWith({double? grade}) {
    return GradeRecordModel(
      id: id,
      studentName: studentName,
      studentId: studentId,
      gradeSection: gradeSection,
      grade: grade ?? this.grade,
      remark: remark,
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

  String _educationLevel = 'College';
  String _yearLevel = '4th';
  String _section = 'B';
  String _semester = '1st';

  bool _hasUnsavedChanges = false;

  void _handleGradeChanged(String id, double grade) {
    widget.onGradeChanged?.call(id, grade);
    setState(() => _hasUnsavedChanges = true);
  }

  void _handleSaveChanges() {
    widget.onSaveChanges?.call();
    setState(() => _hasUnsavedChanges = false);
  }

  /// Matches a trailing "<year digit><section letter>" off the end of
  /// `gradeSection` (e.g. "BSIT - 4B" -> year "4", section "B").
  static final _yearSectionPattern = RegExp(r'(\d)\s*([A-Za-z])\s*$');

  bool _matchesFilters(GradeRecordModel record) {
    if (record.educationLevel != _educationLevel) return false;
    if (record.semester != _semester) return false;
    final match = _yearSectionPattern.firstMatch(record.gradeSection);
    if (match != null) {
      if (_yearLevel != _allYears && match.group(1) != _yearLevel[0]) {
        return false;
      }
      if (_section != _allSections &&
          match.group(2)?.toUpperCase() != _section) {
        return false;
      }
    }
    return true;
  }

  void _resetToFirstPage(VoidCallback update) {
    setState(() {
      update();
      _currentPage = 1;
    });
  }

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
    );

    final filterCard = _GradesFilterCard(
      educationLevel: _educationLevel,
      onEducationLevelChanged: (v) =>
          _resetToFirstPage(() => _educationLevel = v),
      yearLevel: _yearLevel,
      onYearLevelChanged: (v) => _resetToFirstPage(() => _yearLevel = v),
      section: _section,
      onSectionChanged: (v) => _resetToFirstPage(() => _section = v),
      semester: _semester,
      onSemesterChanged: (v) => _resetToFirstPage(() => _semester = v),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final stackColumns = constraints.maxWidth < 900;

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            statsRow,
            const SizedBox(height: 18),
            if (stackColumns)
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  filterCard,
                  const SizedBox(height: 18),
                  listCard,
                ],
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(
                    maxHeight: context.masterDetailRowMaxHeight()),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: listCard),
                    const SizedBox(width: 18),
                    SizedBox(width: 320, child: filterCard),
                  ],
                ),
              ),
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
    return Container(
      padding: const EdgeInsets.fromLTRB(27, 16, 20, 16),
      decoration: BoxDecoration(
        color: RegistrarColors.card(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: RegistrarColors.cardBorder(context)),
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
  });

  final List<GradeRecordModel> records;
  final int totalCount;
  final int currentPage;
  final int totalPages;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final void Function(String id, double grade)? onGradeChanged;

  /// Whether the tab has any records at all before the Filter panel's
  /// selection is applied — lets the empty state tell "no data" apart from
  /// "no rows match this filter".
  final bool hasUnfilteredRecords;

  /// True once at least one grade has been edited since the last save —
  /// "Save Changes" stays disabled until there's something to save.
  final bool hasUnsavedChanges;
  final VoidCallback? onSaveChanges;

  @override
  Widget build(BuildContext context) {
    final headerStyle = GoogleFonts.poppins(
      fontSize: context.isMobileWidth ? 10 : 12,
      fontWeight: FontWeight.w600,
      color: Colors.white,
    );

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

        return Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: RegistrarColors.card(context),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: RegistrarColors.cardBorder(context)),
          ),
          child: Column(
            mainAxisSize: bounded ? MainAxisSize.max : MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Student List',
                        style: GoogleFonts.poppins(
                          fontSize: context.isMobileWidth ? 16 : 18,
                          fontWeight: FontWeight.w600,
                          color: RegistrarColors.rowText(context),
                        ),
                      ),
                    ),
                    SaveChangesButton(
                      enabled: hasUnsavedChanges,
                      onTap: onSaveChanges,
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                color: RegistrarColors.navyBlue,
                child: Row(
                  children: [
                    Expanded(flex: 2, child: Text('Student', style: headerStyle)),
                    Expanded(
                        flex: 2,
                        child: Text('Student ID', style: headerStyle)),
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

class _GradesFilterCard extends StatelessWidget {
  const _GradesFilterCard({
    required this.educationLevel,
    required this.onEducationLevelChanged,
    required this.yearLevel,
    required this.onYearLevelChanged,
    required this.section,
    required this.onSectionChanged,
    required this.semester,
    required this.onSemesterChanged,
  });

  final String educationLevel;
  final ValueChanged<String> onEducationLevelChanged;
  final String yearLevel;
  final ValueChanged<String> onYearLevelChanged;
  final String section;
  final ValueChanged<String> onSectionChanged;
  final String semester;
  final ValueChanged<String> onSemesterChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: RegistrarColors.card(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: RegistrarColors.cardBorder(context)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Filter',
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: RegistrarColors.rowText(context),
                    ),
                  ),
                ),
                const UploadSpreadsheetButton(),
              ],
            ),
            const SizedBox(height: 20),
            const FieldLabel('Education Levels'),
            EducationLevelToggle(
              value: educationLevel,
              onChanged: onEducationLevelChanged,
            ),
            const SizedBox(height: 16),
            const FieldLabel('Program'),
            const DropdownField(value: 'BS Information Technology'),
            const SizedBox(height: 16),
            const FieldLabel('Year Level'),
            Row(
              children: [
                for (final y in ['1st', '2nd']) ...[
                  Expanded(
                    child: SelectionPill(
                      label: y,
                      isSelected: yearLevel == y,
                      onTap: () => onYearLevelChanged(y),
                    ),
                  ),
                  if (y != '2nd') const SizedBox(width: 8),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final y in ['3rd', '4th']) ...[
                  Expanded(
                    child: SelectionPill(
                      label: y,
                      isSelected: yearLevel == y,
                      onTap: () => onYearLevelChanged(y),
                    ),
                  ),
                  if (y != '4th') const SizedBox(width: 8),
                ],
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: SelectionPill(
                label: 'All Years',
                isSelected: yearLevel == _allYears,
                onTap: () => onYearLevelChanged(_allYears),
              ),
            ),
            const SizedBox(height: 16),
            const FieldLabel('Section'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in ['A', 'B', 'C'])
                  SelectionPill(
                    label: s,
                    isSelected: section == s,
                    onTap: () => onSectionChanged(s),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: SelectionPill(
                label: 'All Sections',
                isSelected: section == _allSections,
                onTap: () => onSectionChanged(_allSections),
              ),
            ),
            const SizedBox(height: 16),
            const FieldLabel('Semester'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in ['1st', '2nd'])
                  SelectionPill(
                    label: s,
                    isSelected: semester == s,
                    onTap: () => onSemesterChanged(s),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            const FieldLabel('Subject'),
            const DropdownField(value: 'Computer Programming'),
          ],
        ),
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
  late final _controller =
      TextEditingController(text: _format(widget.value));

  static String _format(double value) =>
      value == value.roundToDouble()
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
                FilteringTextInputFormatter.allow(RegExp(r'^\d{0,3}(\.\d{0,1})?$')),
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
                onTap: () => _step(1),
              ),
              _GradeStepperArrow(
                icon: Icons.keyboard_arrow_down_rounded,
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
  const _GradeStepperArrow({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Icon(icon, size: 14, color: RegistrarColors.mutedText(context)),
    );
  }
}
