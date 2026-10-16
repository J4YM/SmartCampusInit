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

  Future<void> _openCourseDialog(
      {CurriculumEntryModel? editing, String? program}) {
    final save = widget.onSaveCourse!;
    return showAppPopup<void>(
      context: context,
      builder: (_) => _CourseDialog(
        editing: editing,
        initialProgram: program,
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
    final text = RegistrarColors.rowText(context);
    final muted = RegistrarColors.mutedText(context);

    final byProgram = <String, List<CurriculumEntryModel>>{};
    for (final e in widget.entries) {
      (byProgram[e.program] ??= []).add(e);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: RegistrarColors.card(context),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: RegistrarColors.cardBorder(context)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Curriculum',
                        style: dashboardCardTitleStyle(context, color: text)),
                  ),
                  if (widget.onSaveCourse != null) ...[
                    OutlinedButton.icon(
                      onPressed: _openCourseDialog,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: Text('Add Course',
                          style: GoogleFonts.poppins(
                              fontSize: 12.5, fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 8),
                  ],
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
              ),
              const SizedBox(height: 6),
              Text(
                'Upload a CSV or Excel file with the columns Program, Year, '
                'Term, Code, Title, Units and (optional) Prerequisites — one '
                'row per course; use Year 0 / Term 0 (or "Elective") for '
                'electives. Re-uploading updates existing courses. Once a '
                'subject is on file here, schedule imports match it by title '
                'instead of generating a course code.',
                style: GoogleFonts.poppins(fontSize: 12, color: muted),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!,
                    style: GoogleFonts.poppins(fontSize: 12.5, color: Colors.red)),
              ],
              if (_result != null) ...[
                const SizedBox(height: 10),
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
          ),
        ),
        const SizedBox(height: 16),
        if (byProgram.isEmpty)
          Text('No curriculum on file yet. Upload one above.',
              style: GoogleFonts.poppins(fontSize: 12.5, color: muted))
        else
          for (final program in byProgram.keys)
            _ProgramTile(
              program: program,
              entries: byProgram[program]!,
              onAdd: widget.onSaveCourse == null
                  ? null
                  : () => _openCourseDialog(program: program),
              onEdit: widget.onSaveCourse == null
                  ? null
                  : (e) => _openCourseDialog(editing: e),
              onDelete: widget.onDeleteCourse == null ? null : _confirmDelete,
            ),
      ],
    );
  }
}

class _ProgramTile extends StatelessWidget {
  const _ProgramTile({
    required this.program,
    required this.entries,
    this.onAdd,
    this.onEdit,
    this.onDelete,
  });

  final String program;
  final List<CurriculumEntryModel> entries;
  final VoidCallback? onAdd;
  final ValueChanged<CurriculumEntryModel>? onEdit;
  final ValueChanged<CurriculumEntryModel>? onDelete;

  @override
  Widget build(BuildContext context) {
    final muted = RegistrarColors.mutedText(context);
    final groups = <String, List<CurriculumEntryModel>>{};
    for (final e in entries) {
      (groups[_groupLabel(e.yearLevel, e.term)] ??= []).add(e);
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: RegistrarColors.card(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: RegistrarColors.cardBorder(context)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          title: Text(program,
              style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600)),
          subtitle: Text('${entries.length} courses',
              style: GoogleFonts.poppins(fontSize: 12, color: muted)),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final group in groups.entries) ...[
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 4),
                child: Text(
                  '${group.key} · ${group.value.fold<num>(0, (s, e) => s + e.units)} units',
                  style: GoogleFonts.poppins(
                      fontSize: 12.5, fontWeight: FontWeight.w700),
                ),
              ),
              for (final e in group.value)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 84,
                        child: Text(e.code,
                            style: GoogleFonts.poppins(fontSize: 12, color: muted)),
                      ),
                      Expanded(
                        child: Text(
                          e.prerequisites == null || e.prerequisites!.isEmpty
                              ? e.title
                              : '${e.title}  (prereq: ${e.prerequisites})',
                          style: GoogleFonts.poppins(fontSize: 12.5),
                        ),
                      ),
                      Text('${e.units}',
                          style: GoogleFonts.poppins(fontSize: 12, color: muted)),
                      // Demo rows have no id and can't be changed.
                      if (onEdit != null && e.id != null)
                        _RowIcon(
                          icon: Icons.edit_outlined,
                          tooltip: 'Edit course',
                          onTap: () => onEdit!(e),
                        ),
                      if (onDelete != null && e.id != null)
                        _RowIcon(
                          icon: Icons.delete_outline_rounded,
                          tooltip: 'Remove course',
                          color: kDangerTextColor,
                          onTap: () => onDelete!(e),
                        ),
                    ],
                  ),
                ),
            ],
            if (onAdd != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: Text('Add course to $program',
                      style: GoogleFonts.poppins(fontSize: 12)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RowIcon extends StatelessWidget {
  const _RowIcon({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 16, color: color),
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 30, height: 26),
      padding: EdgeInsets.zero,
      onPressed: onTap,
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
  });

  final CurriculumEntryModel? editing;
  final String? initialProgram;
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
    _year = e?.yearLevel ?? 1;
    _term = e?.term ?? 1;
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
    return AppPopup(
      title: editing ? 'Edit Course' : 'Add Course',
      subtitle: editing
          ? 'Code, title and units apply to this subject in every program '
              'that lists it.'
          : null,
      width: 560,
      closeEnabled: !_saving,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppPopupTextField(
            label: 'Program',
            controller: _program,
            hint: 'e.g. BS Information Technology',
          ),
          if (widget.programs.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final p in widget.programs)
                  ActionChip(
                    label: Text(p, style: GoogleFonts.poppins(fontSize: 11)),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(() => _program.text = p),
                  ),
              ],
            ),
          ],
          kAppPopupFieldGap,
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: _levelDropdown(
                title: 'Year',
                value: _year,
                max: 6,
                label: (n) => n == 0 ? 'Elective' : 'Year $n',
                onChanged: (v) => setState(() => _year = v),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _levelDropdown(
                title: 'Term',
                value: _term,
                max: 3,
                label: (n) => n == 0 ? 'Elective' : 'Term $n',
                onChanged: (v) => setState(() => _term = v),
              ),
            ),
          ]),
          kAppPopupFieldGap,
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              flex: 2,
              child: AppPopupTextField(
                label: 'Code',
                controller: _code,
                hint: 'e.g. CITE1003',
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: AppPopupTextField(
                label: 'Units',
                controller: _units,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
            ),
          ]),
          AppPopupTextField(label: 'Title', controller: _title),
          kAppPopupFieldGap,
          AppPopupTextField(
            label: 'Prerequisites (optional)',
            controller: _prereq,
            hint: 'e.g. CITE1003',
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            AppPopupError(_error!),
          ],
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

  Widget _levelDropdown({
    required String title,
    required int value,
    required int max,
    required String Function(int) label,
    required ValueChanged<int> onChanged,
  }) {
    return AppPopupDropdown<int>(
      label: title,
      value: value,
      items: [
        for (var n = 0; n <= max; n++)
          DropdownMenuItem(value: n, child: Text(label(n))),
      ],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}
