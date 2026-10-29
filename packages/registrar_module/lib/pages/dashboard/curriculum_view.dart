import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/registrar_colors.dart';

/// One course in a program's curriculum. [yearLevel]/[term] 0 = elective.
class CurriculumEntryModel {
  const CurriculumEntryModel({
    this.id,
    this.subjectId,
    required this.program,
    required this.yearLevel,
    required this.term,
    required this.code,
    required this.title,
    required this.units,
    this.prerequisites,
  });

  /// `curriculum_entries.id` and `subjects.id` — what Edit / Delete act on.
  /// Null for demo data, which can't be changed.
  final String? id;
  final String? subjectId;
  final String program;
  final int yearLevel;
  final int term;
  final String code;
  final String title;
  final num units;
  final String? prerequisites;
}

/// The values typed into the Add / Edit Course dialog.
class CurriculumCourseForm {
  const CurriculumCourseForm({
    required this.program,
    required this.yearLevel,
    required this.term,
    required this.code,
    required this.title,
    required this.units,
    this.prerequisites,
  });

  final String program;
  final int yearLevel;
  final int term;
  final String code;
  final String title;
  final num units;
  final String? prerequisites;
}

/// Outcome of one curriculum upload, shown under the Upload button.
class CurriculumUploadResult {
  const CurriculumUploadResult({
    required this.subjects,
    required this.placements,
    required this.programs,
    required this.mergedAutoSubjects,
    required this.errors,
  });

  final int subjects;
  final int placements;
  final List<String> programs;
  final int mergedAutoSubjects;
  final List<String> errors;
}

String _ordinal(int n) => switch (n) {
      1 => '1st',
      2 => '2nd',
      3 => '3rd',
      _ => '${n}th',
    };

String _groupLabel(int year, int term) =>
    year == 0 ? 'Electives' : '${_ordinal(year)} Year · ${_ordinal(term)} Term';

/// The Registrar's Curriculum tab: upload every program's course list once
/// so schedule imports match real subjects instead of auto-generating a
/// course code, and browse what is on file per program / year / term.
class CurriculumView extends StatefulWidget {
  const CurriculumView({
    super.key,
    required this.entries,
    this.onUpload,
    this.onSaveCourse,
    this.onDeleteCourse,
  });

  final List<CurriculumEntryModel> entries;

  /// Adds a course ([existing] null) or saves an edit to [existing]. Throws
  /// with a readable message on a conflict — the dialog shows it and stays
  /// open. Null hides Add and Edit (demo).
  final Future<void> Function(
      CurriculumEntryModel? existing, CurriculumCourseForm form)? onSaveCourse;

  /// Removes a course from its program's curriculum. Null hides Delete.
  final Future<void> Function(CurriculumEntryModel entry)? onDeleteCourse;

  /// Reads and stores the picked CSV/Excel file; throws on a fatal problem
  /// (unreadable file, missing columns). Null hides the Upload button (demo).
  final Future<CurriculumUploadResult> Function(PlatformFile file)? onUpload;

  @override
  State<CurriculumView> createState() => _CurriculumViewState();
}

class _CurriculumViewState extends State<CurriculumView> {
  bool _uploading = false;
  String? _error;
  CurriculumUploadResult? _result;

  /// The program being browsed; falls back to the first one on file.
  String? _program;

  /// The year-level filter (0 = electives); null shows every year.
  int? _year;

  final _search = TextEditingController();
  String _query = '';

  /// The term cards the user folded up, as `program|year-term`.
  final Set<String> _collapsed = {};

  static String _groupId(String program, int year, int term) =>
      '$program|$year-$term';

  void _toggleGroup(String id) => setState(() {
        if (!_collapsed.remove(id)) _collapsed.add(id);
      });

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _handle(PlatformFile file) async {
    final upload = widget.onUpload;
    if (upload == null || _uploading) return;
    setState(() {
      _uploading = true;
      _error = null;
      _result = null;
    });
    try {
      final result = await upload(file);
      if (mounted) setState(() => _result = result);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  List<String> get _programs =>
      {for (final e in widget.entries) e.program}.toList()..sort();

  Future<void> _openCourseDialog({
    CurriculumEntryModel? editing,
    String? program,
    int? year,
    int? term,
  }) {
    final save = widget.onSaveCourse!;
    return showAppPopup<void>(
      context: context,
      builder: (_) => _CourseDialog(
        editing: editing,
        initialProgram: program,
        initialYear: year,
        initialTerm: term,
        programs: _programs,
        onSave: (form) => save(editing, form),
      ),
    );
  }

  Future<void> _confirmDelete(CurriculumEntryModel entry) async {
    final confirmed = await confirmArchiveDelete(
      context,
      title: 'Remove course?',
      message: 'Remove ${entry.code} — ${entry.title} from ${entry.program}\'s '
          'curriculum? The subject itself stays on file, so existing class '
          'schedules are not affected.',
      confirmLabel: 'Remove',
    );
    if (!confirmed) return;
    try {
      await widget.onDeleteCourse!(entry);
    } catch (e) {
      if (mounted) {
        showAppMessage(context, title: 'Could not remove course', message: '$e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final programs = _programs;
    final active = programs.contains(_program)
        ? _program
        : (programs.isEmpty ? null : programs.first);
    final inProgram = [
      for (final e in widget.entries)
        if (e.program == active) e,
    ];
    final years = {for (final e in inProgram) e.yearLevel}.toList()
      ..sort(_yearOrder);
    final yearFilter = years.contains(_year) ? _year : null;
    final q = _query.trim().toLowerCase();
    final shown = [
      for (final e in inProgram)
        if ((yearFilter == null || e.yearLevel == yearFilter) &&
            (q.isEmpty ||
                e.code.toLowerCase().contains(q) ||
                e.title.toLowerCase().contains(q) ||
                (e.prerequisites ?? '').toLowerCase().contains(q)))
          e,
    ];
    final groups = <(int, int), List<CurriculumEntryModel>>{};
    for (final e in shown) {
      (groups[(e.yearLevel, e.term)] ??= []).add(e);
    }
    final groupKeys = groups.keys.toList()
      ..sort((a, b) {
        final byYear = _yearOrder(a.$1, b.$1);
        return byYear != 0 ? byYear : _yearOrder(a.$2, b.$2);
      });
    for (final list in groups.values) {
      list.sort((a, b) => a.code.compareTo(b.code));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // One card: the title and upload actions on top, then (once there is a
        // curriculum) a divider and the program picker, search and totals.
        _card(
          context,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(context, programs.length),
              const SizedBox(height: 20),
              Divider(height: 1, color: RegistrarColors.background(context)),
              const SizedBox(height: 20),
              if (widget.entries.isEmpty)
                const DashboardTableEmptyState(
                  icon: Icons.menu_book_outlined,
                  message: 'No curriculum on file yet. Upload one above.',
                )
              else
                _browser(
                    context, programs, active, inProgram, years, yearFilter),
            ],
          ),
        ),
        if (widget.entries.isNotEmpty) ...[
          for (final key in groupKeys) ...[
            const SizedBox(height: 16),
            _groupCard(context, active!, key, groups[key]!),
          ],
          if (groupKeys.isEmpty) ...[
            const SizedBox(height: 16),
            _card(
              context,
              child: const DashboardTableEmptyState(
                message: 'No courses match your search',
              ),
            ),
          ],
        ],
      ],
    );
  }

  Widget _card(BuildContext context,
      {required Widget child, EdgeInsetsGeometry? padding}) {
    return BentoCard(
      backgroundColor: RegistrarColors.card(context),
      borderColor: RegistrarColors.cardBorder(context),
      padding:
          padding ?? const EdgeInsets.symmetric(vertical: 24, horizontal: 29),
      child: child,
    );
  }

  /// Title, the two actions, the file-format note and the last upload's result.
  Widget _header(BuildContext context, int programCount) {
    final text = RegistrarColors.rowText(context);
    final muted = RegistrarColors.mutedText(context);
    final courseCount = widget.entries.length;
    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Curriculum',
            style: dashboardCardTitleStyle(context, color: text)),
        const SizedBox(height: 4),
        Text(
          '$programCount ${programCount == 1 ? 'program' : 'programs'}'
          ' | $courseCount ${courseCount == 1 ? 'course' : 'courses'} on file',
          style: TitledTableCard.subtitleStyle(context, color: muted),
        ),
      ],
    );
    final actions = Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (widget.onUpload != null)
          if (_uploading)
            const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2))
          else
            UploadSpreadsheetButton(
              label: 'Upload Curriculum',
              tooltip: 'Upload a curriculum CSV / Excel file',
              onFileSelected: _handle,
            ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (context.isMobileWidth) ...[
          titleBlock,
          const SizedBox(height: 14),
          actions,
        ] else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: titleBlock),
              const SizedBox(width: 12),
              actions,
            ],
          ),
        if (widget.onUpload != null) ...[
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: RegistrarColors.background(context),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, size: 18, color: muted),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Upload a CSV or Excel file with the columns Program, '
                    'Year, Term, Code, Title, Units and (optional) '
                    'Prerequisites — one row per course; use Year 0 / Term 0 '
                    '(or "Elective") for electives. Re-uploading updates '
                    'existing courses. Once a subject is on file here, '
                    'schedule imports match it by title instead of '
                    'generating a course code.',
                    style: GoogleFonts.poppins(
                        fontSize: 12, height: 1.5, color: muted),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!,
              style: GoogleFonts.poppins(
                  fontSize: 12.5, color: kDangerTextColor)),
        ],
        if (_result != null) ...[
          const SizedBox(height: 12),
          Text(
            'Imported ${_result!.subjects} subjects into '
            '${_result!.placements} placements across '
            '${_result!.programs.length} program(s)'
            '${_result!.mergedAutoSubjects > 0 ? ', merged ${_result!.mergedAutoSubjects} auto-generated subject(s) into real ones' : ''}.',
            style: GoogleFonts.poppins(
                fontSize: 12.5, fontWeight: FontWeight.w600, color: text),
          ),
          for (final e in _result!.errors.take(10))
            Text('• $e',
                style: GoogleFonts.poppins(
                    fontSize: 11.5, color: const Color(0xFFD97706))),
          if (_result!.errors.length > 10)
            Text('…and ${_result!.errors.length - 10} more skipped rows',
                style: GoogleFonts.poppins(fontSize: 11.5, color: muted)),
        ],
      ],
    );
  }

  /// Program picker, search + year filter, and the program's totals with its
  /// Add course button.
  Widget _browser(
    BuildContext context,
    List<String> programs,
    String? active,
    List<CurriculumEntryModel> inProgram,
    List<int> years,
    int? yearFilter,
  ) {
    final units = inProgram.fold<num>(0, (s, e) => s + e.units);
    final terms = {for (final e in inProgram) (e.yearLevel, e.term)}.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilterLabelBand(
          label: 'Program',
          surface: RegistrarColors.card(context),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in programs)
              _ProgramPill(
                key: ValueKey('curriculum-program-$p'),
                label: p,
                count: widget.entries.where((e) => e.program == p).length,
                selected: p == active,
                onTap: () => setState(() {
                  _program = p;
                  _year = null;
                }),
              ),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: DashboardSearchField(
                key: const Key('curriculum-search'),
                controller: _search,
                hint: 'Search code, title or prerequisite',
                fillColor: RegistrarColors.background(context),
                textColor: RegistrarColors.rowText(context),
                hintColor: RegistrarColors.placeholderText(context),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            if (years.length > 1) ...[
              const SizedBox(width: 10),
              FilterMenuButton(
                key: const Key('curriculum-filter'),
                backgroundColor: RegistrarColors.background(context),
                menuColor: RegistrarColors.card(context),
                borderColor: RegistrarColors.cardBorder(context),
                iconColor: RegistrarColors.placeholderText(context),
                textColor: RegistrarColors.rowText(context),
                mutedTextColor: RegistrarColors.mutedText(context),
                accentColor: RegistrarColors.azureBlue,
                sections: [
                  FilterMenuSection(
                    title: 'Year level',
                    options: [
                      for (final y in years)
                        FilterMenuOption(
                          label: y == 0 ? 'Electives' : '${_ordinal(y)} Year',
                          value: '$y',
                        ),
                    ],
                    selectedValue: yearFilter?.toString(),
                    onChanged: (v) => setState(
                        () => _year = v == null ? null : int.parse(v)),
                  ),
                ],
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _StatChip(label: 'Courses', value: '${inProgram.length}'),
            _StatChip(label: 'Units', value: _fmtUnits(units)),
            _StatChip(label: 'Terms', value: '$terms'),
            if (active != null && terms > 1)
              Builder(builder: (context) {
                final ids = {
                  for (final e in inProgram)
                    _groupId(active, e.yearLevel, e.term),
                };
                final allCollapsed = ids.every(_collapsed.contains);
                return SecondaryPillButton(
                  key: const Key('curriculum-toggle-all'),
                  label: allCollapsed ? 'Expand all' : 'Collapse all',
                  icon: allCollapsed
                      ? Icons.unfold_more_rounded
                      : Icons.unfold_less_rounded,
                  onTap: () => setState(() {
                    if (allCollapsed) {
                      _collapsed.removeAll(ids);
                    } else {
                      _collapsed.addAll(ids);
                    }
                  }),
                );
              }),
            if (widget.onSaveCourse != null && active != null)
              SecondaryPillButton(
                key: const Key('curriculum-add-to-program'),
                label: 'Add course to $active',
                icon: Icons.add_rounded,
                onTap: () => _openCourseDialog(program: active),
              ),
          ],
        ),
      ],
    );
  }

  /// One year / term as its own table card, in the app-wide table layout.
  Widget _groupCard(
    BuildContext context,
    String program,
    (int, int) key,
    List<CurriculumEntryModel> courses,
  ) {
    final units = courses.fold<num>(0, (s, e) => s + e.units);
    final canEdit = widget.onSaveCourse != null;
    final canDelete = widget.onDeleteCourse != null;
    final hasActions = canEdit || canDelete;
    final columns = <DashboardTableColumn>[
      const DashboardTableColumn('Code', width: 130),
      const DashboardTableColumn('Course Title', flex: 5, minWidth: 260),
      const DashboardTableColumn('Prerequisites', flex: 3, minWidth: 170),
      const DashboardTableColumn('Units', width: 70),
      if (hasActions)
        const DashboardTableColumn('Actions',
            flex: 1, minWidth: 72, sticky: true),
    ];
    final accent = subNavActiveColor(context, RegistrarColors.azureBlue);

    return TitledTableCard(
      key: ValueKey('curriculum-group-${key.$1}-${key.$2}'),
      headerKey: ValueKey('curriculum-toggle-${key.$1}-${key.$2}'),
      // Searching opens every card so a match is never hidden in a folded one.
      collapsed: _query.trim().isEmpty &&
          _collapsed.contains(_groupId(program, key.$1, key.$2)),
      onToggleCollapsed: () => _toggleGroup(_groupId(program, key.$1, key.$2)),
      title: _groupLabel(key.$1, key.$2),
      subtitle: Text(
        '${courses.length} ${courses.length == 1 ? 'course' : 'courses'}'
        ' | ${_fmtUnits(units)} units',
        style: TitledTableCard.subtitleStyle(context,
            color: RegistrarColors.mutedText(context)),
      ),
      toolbar: canEdit
          ? Align(
              alignment: Alignment.centerRight,
              child: SecondaryPillButton(
                key: ValueKey('curriculum-add-${key.$1}-${key.$2}'),
                label: 'Add to this term',
                icon: Icons.add_rounded,
                onTap: () => _openCourseDialog(
                    program: program, year: key.$1, term: key.$2),
              ),
            )
          : null,
      columns: columns,
      rows: [
        for (var i = 0; i < courses.length; i++)
          DashboardTableRow(
            key: ValueKey(
                'curriculum-row-${courses[i].id ?? '${courses[i].program}|${courses[i].code}'}'),
            columns: columns,
            showDivider: i < courses.length - 1,
            cells: [
              Text(courses[i].code,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: dashboardTableIdStyle(context, color: accent)),
              Text(courses[i].title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: dashboardTablePrimaryStyle(context,
                      color: RegistrarColors.rowText(context))),
              Text(
                (courses[i].prerequisites ?? '').trim().isEmpty
                    ? '—'
                    : courses[i].prerequisites!.trim(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: dashboardTableBodyStyle(context,
                    color: RegistrarColors.mutedText(context)),
              ),
              Text(_fmtUnits(courses[i].units),
                  style: dashboardTableBodyStyle(context,
                      color: RegistrarColors.rowText(context))),
              if (hasActions)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Demo rows have no id and can't be changed.
                    if (canEdit && courses[i].id != null)
                      DashboardRowIconButton(
                        icon: Icons.edit_outlined,
                        tooltip: 'Edit course',
                        onPressed: () => _openCourseDialog(editing: courses[i]),
                      ),
                    if (canDelete && courses[i].id != null)
                      DashboardRowIconButton(
                        icon: Icons.delete_outline_rounded,
                        tooltip: 'Remove course',
                        color: kDangerTextColor,
                        onPressed: () => _confirmDelete(courses[i]),
                      ),
                  ],
                ),
            ],
          ),
      ],
      empty: const DashboardTableEmptyState(message: 'No courses'),
      backgroundColor: RegistrarColors.card(context),
      borderColor: RegistrarColors.cardBorder(context),
      titleColor: RegistrarColors.rowText(context),
    );
  }
}

/// Year 0 (electives) sorts after every real year / term.
int _yearOrder(int a, int b) => (a == 0 ? 99 : a).compareTo(b == 0 ? 99 : b);

/// 21 not 21.0; 1.5 stays 1.5.
String _fmtUnits(num n) => n == n.roundToDouble() ? '${n.toInt()}' : '$n';

/// A program in the picker: its name and how many courses it has.
class _ProgramPill extends StatelessWidget {
  const _ProgramPill({
    super.key,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground =
        selected ? Colors.white : RegistrarColors.rowText(context);
    return Material(
      color: selected
          ? RegistrarColors.azureBlue
          : RegistrarColors.background(context),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: kDashboardControlHeight),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    label,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: foreground,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                  decoration: BoxDecoration(
                    color: foreground.withOpacity(selected ? 0.22 : 0.10),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$count',
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: foreground,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A "Courses 52" style total next to the program's Add button.
class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: kDashboardControlHeight),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: RegistrarColors.background(context),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: GoogleFonts.poppins(
                  fontSize: 12, color: RegistrarColors.mutedText(context))),
          const SizedBox(width: 8),
          Text(value,
              style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: RegistrarColors.rowText(context))),
        ],
      ),
    );
  }
}

/// Add / Edit Course. Stays open on a save error so the message sits beside
/// what caused it.
class _CourseDialog extends StatefulWidget {
  const _CourseDialog({
    required this.editing,
    required this.initialProgram,
    required this.programs,
    required this.onSave,
    this.initialYear,
    this.initialTerm,
  });

  final CurriculumEntryModel? editing;
  final String? initialProgram;

  /// Pre-selected year / term when adding from a term's own card.
  final int? initialYear;
  final int? initialTerm;
  final List<String> programs;
  final Future<void> Function(CurriculumCourseForm form) onSave;

  @override
  State<_CourseDialog> createState() => _CourseDialogState();
}

class _CourseDialogState extends State<_CourseDialog> {
  late final TextEditingController _program;
  late final TextEditingController _code;
  late final TextEditingController _title;
  late final TextEditingController _units;
  late final TextEditingController _prereq;
  late int _year;
  late int _term;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    _program = TextEditingController(text: e?.program ?? widget.initialProgram);
    _code = TextEditingController(text: e?.code);
    _title = TextEditingController(text: e?.title);
    _units = TextEditingController(text: e == null ? '3' : '${e.units}');
    _prereq = TextEditingController(text: e?.prerequisites);
    _year = e?.yearLevel ?? widget.initialYear ?? 1;
    _term = e?.term ?? widget.initialTerm ?? 1;
  }

  @override
  void dispose() {
    _program.dispose();
    _code.dispose();
    _title.dispose();
    _units.dispose();
    _prereq.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final program = _program.text.trim();
    final code = _code.text.trim();
    final title = _title.text.trim();
    final units = num.tryParse(_units.text.trim());
    String? problem;
    if (program.isEmpty || code.isEmpty || title.isEmpty) {
      problem = 'Program, Code and Title are required.';
    } else if (units == null || units < 0) {
      problem = 'Units must be a number, 0 or more.';
    } else if ((_year == 0) != (_term == 0)) {
      problem = 'An elective uses Year and Term both set to Elective.';
    }
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(CurriculumCourseForm(
        program: program,
        yearLevel: _year,
        term: _term,
        code: code,
        title: title,
        units: units!,
        prerequisites: _prereq.text,
      ));
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.editing != null;
    final typedProgram = _program.text.trim();
    // Laid out like Add Student: grouped sections, field cells that sit side
    // by side and stack on a narrow screen, the Cancel / primary footer.
    return AppPopup(
      title: editing ? 'Edit Course' : 'Add Course',
      subtitle: editing
          ? 'Code, title and units apply to this subject in every program '
              'that lists it.'
          : null,
      width: 600,
      closeEnabled: !_saving,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AppPopupSection('Program', icon: Icons.school_outlined),
          AppPopupTextField(
            label: 'Program name',
            controller: _program,
            hint: 'e.g. BS Information Technology',
            onChanged: (_) => setState(() {}),
          ),
          if (widget.programs.isNotEmpty) ...[
            const SizedBox(height: 10),
            // Quick picks: the popup's own selectable pills, the one matching
            // what is typed is highlighted.
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in widget.programs)
                  AppPopupChoicePill(
                    label: p,
                    selected: typedProgram == p,
                    onTap: () => setState(() => _program.text = p),
                  ),
              ],
            ),
          ],
          kAppPopupFieldGap,
          const AppPopupSection('Placement',
              icon: Icons.calendar_view_month_outlined),
          AppPopupFormRow(children: [
            _levelCell(
              title: 'Year',
              value: _year,
              max: 6,
              label: (n) => n == 0 ? 'Elective' : 'Year $n',
              onChanged: (v) => setState(() => _year = v),
            ),
            _levelCell(
              title: 'Term',
              value: _term,
              max: 3,
              label: (n) => n == 0 ? 'Elective' : 'Term $n',
              onChanged: (v) => setState(() => _term = v),
            ),
          ]),
          const AppPopupSection('Course Details',
              icon: Icons.menu_book_outlined),
          AppPopupFormRow(children: [
            _textCell('Code', _code, hint: 'e.g. CITE1003', flex: 2),
            _textCell('Units', _units,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true)),
          ]),
          AppPopupFormRow(children: [
            _textCell('Title', _title, hint: 'e.g. Computer Programming 1'),
          ]),
          AppPopupFormRow(children: [
            _textCell('Prerequisites (optional)', _prereq,
                hint: 'e.g. CITE1003'),
          ]),
          if (_error != null) AppPopupError(_error!),
        ],
      ),
      actions: [
        AppPopupSecondaryButton(
          label: 'Cancel',
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
        ),
        AppPopupPrimaryButton(
          label: editing ? 'Save Changes' : 'Add Course',
          loading: _saving,
          onPressed: _submit,
        ),
      ],
    );
  }

  AppPopupFormCell _textCell(
    String label,
    TextEditingController controller, {
    String? hint,
    TextInputType? keyboardType,
    int flex = 1,
  }) {
    return AppPopupFormCell(
      label: label,
      flex: flex,
      child: Builder(
        builder: (context) => TextField(
          controller: controller,
          enabled: !_saving,
          keyboardType: keyboardType,
          style: appPopupFieldStyle(context),
          cursorColor: AppPopupColors.accent,
          decoration: appPopupInputDecoration(context, hint: hint),
        ),
      ),
    );
  }

  AppPopupFormCell _levelCell({
    required String title,
    required int value,
    required int max,
    required String Function(int) label,
    required ValueChanged<int> onChanged,
  }) {
    return AppPopupFormCell(
      label: title,
      child: Builder(
        builder: (context) {
          final colors = AppPopupColors.of(context);
          return DropdownButtonFormField<int>(
            value: value,
            isExpanded: true,
            icon: Icon(Icons.keyboard_arrow_down_rounded,
                size: 20, color: colors.muted),
            style: appPopupFieldStyle(context),
            dropdownColor: colors.card,
            decoration: appPopupInputDecoration(context),
            items: [
              for (var n = 0; n <= max; n++)
                DropdownMenuItem(value: n, child: Text(label(n))),
            ],
            onChanged: _saving
                ? null
                : (v) {
                    if (v != null) onChanged(v);
                  },
          );
        },
      ),
    );
  }
}
