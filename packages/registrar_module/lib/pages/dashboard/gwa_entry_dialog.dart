import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/registrar_colors.dart';
import 'registrar_dashboard_page.dart' show RegistrarStudentModel;

/// Registrar's manual GWA entry — for a student the GPA batch upload missed
/// or got wrong. Narrow the list by course and section, search by name /
/// student number, pick the student, type the GWA (1.00 best … 5.00).
///
/// [onSave] persists it and returns the "school year / term" it was filed
/// under (shown back to the Registrar). The dialog stays open after a save so
/// several students can be entered in a row; each saved value shows next to
/// the student immediately.
class GwaEntryDialog extends StatefulWidget {
  const GwaEntryDialog({
    super.key,
    required this.students,
    required this.onSave,
  });

  final List<RegistrarStudentModel> students;
  final Future<String> Function(String studentId, double gwa) onSave;

  @override
  State<GwaEntryDialog> createState() => _GwaEntryDialogState();
}

class _GwaEntryDialogState extends State<GwaEntryDialog> {
  static const _allValue = '__all__';

  final _gwaController = TextEditingController();

  /// [_allValue] while no course/section filter is applied.
  String _course = _allValue;
  String _section = _allValue;
  String? _selectedId;

  /// GWAs saved during this dialog's life, so the list reflects them before
  /// the host's student list re-fetches.
  final _saved = <String, double>{};

  bool _saving = false;
  String? _error;
  String? _notice;

  @override
  void dispose() {
    _gwaController.dispose();
    super.dispose();
  }

  /// "BSIT" whether `sections.program` holds the acronym or the full name,
  /// falling back to the section name's own prefix ("BSIT-3B").
  String _courseKey(RegistrarStudentModel s) =>
      canonicalProgramKey(s.program) ??
      canonicalProgramKey(sectionProgramCode(s.section)) ??
      'Other';

  double? _gwaOf(RegistrarStudentModel s) => _saved[s.id] ?? s.gpa;

  List<String> get _courses {
    final keys = {for (final s in widget.students) _courseKey(s)}.toList();
    keys.sort((a, b) {
      int rank(String k) {
        final i = kPickerPrograms.indexOf(k);
        return i == -1 ? kPickerPrograms.length : i;
      }

      final byRank = rank(a).compareTo(rank(b));
      return byRank != 0 ? byRank : a.compareTo(b);
    });
    return keys;
  }

  /// Sections of the chosen course (every section when "All courses").
  List<String> get _sections {
    final names = {
      for (final s in widget.students)
        if ((_course == _allValue || _courseKey(s) == _course) &&
            s.section.trim().isNotEmpty)
          s.section.trim(),
    }.toList()
      ..sort();
    return names;
  }

  List<RegistrarStudentModel> get _filtered => [
        for (final s in widget.students)
          if ((_course == _allValue || _courseKey(s) == _course) &&
              (_section == _allValue || s.section.trim() == _section))
            s,
      ];

  RegistrarStudentModel? get _selected {
    for (final s in widget.students) {
      if (s.id == _selectedId) return s;
    }
    return null;
  }

  void _select(String id) {
    if (_saving) return;
    final student = widget.students.firstWhere((s) => s.id == id);
    final gwa = _gwaOf(student);
    setState(() {
      _selectedId = id;
      _error = null;
      _notice = null;
      _gwaController.text = gwa == null ? '' : gwa.toStringAsFixed(2);
    });
  }

  Future<void> _handleSave() async {
    final student = _selected;
    if (student == null) return;
    final gwa = double.tryParse(_gwaController.text.trim().replaceAll(',', '.'));
    if (gwa == null || gwa < 1.0 || gwa > 5.0) {
      setState(() => _error = 'Enter a GWA between 1.00 and 5.00.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _notice = null;
    });
    try {
      final term = await widget.onSave(student.id, gwa);
      if (!mounted) return;
      setState(() {
        _saved[student.id] = double.parse(gwa.toStringAsFixed(2));
        _notice = '${student.name}: GWA ${gwa.toStringAsFixed(2)} saved '
            '($term).';
        _selectedId = null;
        _gwaController.clear();
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final selected = _selected;
    final colors = AppPopupColors.of(context);

    final entries = [
      for (final s in filtered)
        PickerEntry(
          id: s.id,
          title: s.name,
          subtitle: [
            s.studentId,
            if (s.section.trim().isNotEmpty) s.section.trim(),
            _gwaOf(s) == null ? 'No GWA yet' : 'GWA ${_gwaOf(s)!.toStringAsFixed(2)}',
          ].join(' · '),
          program: _courseKey(s),
        ),
    ];

    return AppPopup(
      title: 'Enter GWA',
      subtitle: 'Manually set a student\'s General Weighted Average',
      width: 560,
      closeEnabled: !_saving,
      // The picker scrolls its own list, so it gets a bounded height.
      scrollBody: false,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: AppPopupDropdown<String>(
                  label: 'Course',
                  value: _course,
                  items: [
                    const DropdownMenuItem(
                        value: _allValue, child: Text('All courses')),
                    for (final key in _courses)
                      DropdownMenuItem(
                        value: key,
                        child: Text(
                          pickerProgramLabel(key),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: _saving
                      ? null
                      : (v) => setState(() {
                            _course = v ?? _allValue;
                            // A section of another course no longer applies.
                            if (!_sections.contains(_section)) {
                              _section = _allValue;
                            }
                            if (_selectedId != null &&
                                !_filtered.any((s) => s.id == _selectedId)) {
                              _selectedId = null;
                              _gwaController.clear();
                            }
                          }),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AppPopupDropdown<String>(
                  label: 'Section',
                  value: _sections.contains(_section) ? _section : _allValue,
                  items: [
                    const DropdownMenuItem(
                        value: _allValue, child: Text('All sections')),
                    for (final name in _sections)
                      DropdownMenuItem(
                        value: name,
                        child: Text(name, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: _saving
                      ? null
                      : (v) => setState(() {
                            _section = v ?? _allValue;
                            if (_selectedId != null &&
                                !_filtered.any((s) => s.id == _selectedId)) {
                              _selectedId = null;
                              _gwaController.clear();
                            }
                          }),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Flexible(
            child: SearchablePickerList(
              searchHint: 'Search by name, student number or section',
              palette: RegistrarColors.picker(context),
              groupNoun: 'student',
              emptyMessage: 'No students match this course and section.',
              entries: entries,
              selectedId: _selectedId,
              onSelected: _select,
            ),
          ),
          const SizedBox(height: 14),
          if (selected != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                selected.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppPopupColors.accent,
                ),
              ),
            ),
          AppPopupTextField(
            label: 'GWA (1.00 best – 5.00)',
            hint: selected == null ? 'Pick a student first' : 'e.g. 1.75',
            controller: _gwaController,
            enabled: selected != null && !_saving,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            AppPopupError(_error!),
          ],
          if (_notice != null) ...[
            const SizedBox(height: 12),
            Text(
              _notice!,
              style: GoogleFonts.poppins(fontSize: 12, color: colors.muted),
            ),
          ],
        ],
      ),
      actions: [
        AppPopupSecondaryButton(
          label: 'Close',
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
        ),
        AppPopupPrimaryButton(
          key: const Key('gwa-save'),
          label: 'Save GWA',
          loading: _saving,
          onPressed: selected != null && !_saving ? _handleSave : null,
        ),
      ],
    );
  }
}
