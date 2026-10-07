import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/registrar_colors.dart';
import 'class_schedule_view.dart' show SubjectOption;
import 'registrar_dashboard_page.dart' show RegistrarPillButton;

/// One of a student's active `enrollments` rows, joined through to its
/// class_sections/subjects/sections/profiles — see
/// docs/superpowers/specs/2026-09-04-irregular-students-schema-design.md
/// for why a student can have an enrollment whose section differs from
/// their own `students.section_id` ("irregular" for that one subject,
/// e.g. retaking it with an earlier cohort, or taking it ahead of time).
class StudentEnrollmentModel {
  const StudentEnrollmentModel({
    required this.enrollmentId,
    required this.subjectTitle,
    required this.sectionName,
    required this.professorName,
    required this.isIrregular,
  });

  final String enrollmentId;
  final String subjectTitle;
  final String sectionName;
  final String professorName;
  final bool isIrregular;
}

/// One class_sections row offering a subject — a candidate in
/// [SubjectEnrollmentsSection]'s "Enroll in Subject" dialog, once a
/// subject is chosen. Deliberately not scoped to the student's own home
/// section — offerings from every section are valid candidates, which is
/// exactly what lets a student enroll "irregularly".
class ClassSectionOffering {
  const ClassSectionOffering({
    required this.id,
    required this.sectionName,
    required this.professorName,
  });

  final String id;
  final String sectionName;
  final String professorName;
}

/// A student's subject-level enrollments, shown on their profile panel,
/// with an action to enroll them in another offering — including one
/// belonging to a different section than their own, which is the entire
/// mechanism for handling an irregular student (see this file's own doc
/// comments and the schema design spec). Owns its own load state so the
/// profile panel doesn't have to; refetches whenever [studentId] changes.
class SubjectEnrollmentsSection extends StatefulWidget {
  const SubjectEnrollmentsSection({
    super.key,
    required this.studentId,
    required this.onFetchEnrollments,
    this.subjectOptions = const [],
    this.onFetchOfferings,
    this.onEnroll,
    this.onDrop,
  });

  final String studentId;
  final Future<List<StudentEnrollmentModel>> Function(String studentId)
      onFetchEnrollments;

  final List<SubjectOption> subjectOptions;
  final Future<List<ClassSectionOffering>> Function(String subjectId)?
      onFetchOfferings;

  /// Falls back to no "Enroll in Subject" button when omitted (alongside
  /// [onFetchOfferings]).
  final Future<void> Function(String studentId, String classSectionId)?
      onEnroll;

  /// Falls back to no per-row "Drop" action when omitted.
  final Future<void> Function(String enrollmentId)? onDrop;

  @override
  State<SubjectEnrollmentsSection> createState() =>
      _SubjectEnrollmentsSectionState();
}

class _SubjectEnrollmentsSectionState extends State<SubjectEnrollmentsSection> {
  List<StudentEnrollmentModel>? _enrollments;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant SubjectEnrollmentsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.studentId != widget.studentId) _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final enrollments = await widget.onFetchEnrollments(widget.studentId);
      if (mounted) setState(() => _enrollments = enrollments);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openEnrollDialog(BuildContext context) {
    final onEnroll = widget.onEnroll;
    final onFetchOfferings = widget.onFetchOfferings;
    if (onEnroll == null || onFetchOfferings == null) return;
    final theme = Theme.of(context);
    showDialog<void>(
      context: context,
      builder: (_) => Theme(
        data: theme,
        child: _EnrollInSubjectDialog(
          subjectOptions: widget.subjectOptions,
          onFetchOfferings: onFetchOfferings,
          onSave: (classSectionId) => onEnroll(widget.studentId, classSectionId),
        ),
      ),
    ).then((_) => _load());
  }

  Future<void> _handleDrop(String enrollmentId) async {
    final onDrop = widget.onDrop;
    if (onDrop == null) return;
    await onDrop(enrollmentId);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final enrollments = _enrollments ?? const <StudentEnrollmentModel>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Divider(color: RegistrarColors.cardBorder(context)),
        const SizedBox(height: 12),
        Text(
          'Subject Enrollments',
          style: GoogleFonts.poppins(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: RegistrarColors.rowText(context),
          ),
        ),
        // Just below the label, spanning the card's full width — same as
        // the "Change Section" button above.
        if (widget.onEnroll != null && widget.onFetchOfferings != null) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: RegistrarPillButton(
              label: 'Enroll in Subject',
              icon: Icons.add,
              expand: true,
              onTap: () => _openEnrollDialog(context),
            ),
          ),
        ],
        const SizedBox(height: 8),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (enrollments.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'No subject enrollments on file yet.',
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: RegistrarColors.mutedText(context),
              ),
            ),
          )
        else
          for (final e in enrollments)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          e.subjectTitle,
                          style: GoogleFonts.poppins(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: RegistrarColors.rowText(context),
                          ),
                        ),
                        Text(
                          '${e.sectionName} — ${e.professorName}'
                          '${e.isIrregular ? '  ·  Irregular' : ''}',
                          style: GoogleFonts.poppins(
                            fontSize: 11.5,
                            color: e.isIrregular
                                ? RegistrarColors.azureBlue
                                : RegistrarColors.mutedText(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (widget.onDrop != null)
                    Tooltip(
                      message: 'Drop',
                      child: InkWell(
                        onTap: () => _handleDrop(e.enrollmentId),
                        borderRadius: BorderRadius.circular(14),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(
                            Icons.close_rounded,
                            size: 16,
                            color: RegistrarColors.mutedText(context),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
      ],
    );
  }
}

class _EnrollInSubjectDialog extends StatefulWidget {
  const _EnrollInSubjectDialog({
    required this.subjectOptions,
    required this.onFetchOfferings,
    required this.onSave,
  });

  final List<SubjectOption> subjectOptions;
  final Future<List<ClassSectionOffering>> Function(String subjectId)
      onFetchOfferings;
  final Future<void> Function(String classSectionId) onSave;

  @override
  State<_EnrollInSubjectDialog> createState() => _EnrollInSubjectDialogState();
}

class _EnrollInSubjectDialogState extends State<_EnrollInSubjectDialog> {
  String? _subjectId;
  List<PickerEntry> _offeringEntries = const [];
  bool _loadingOfferings = false;
  String? _offeringId;
  bool _saving = false;
  String? _error;

  Future<void> _handleSubjectChanged(String? subjectId) async {
    setState(() {
      _subjectId = subjectId;
      _offeringEntries = const [];
      _offeringId = null;
      _error = null;
    });
    if (subjectId == null) return;
    setState(() => _loadingOfferings = true);
    try {
      final offerings = await widget.onFetchOfferings(subjectId);
      if (mounted) {
        setState(() {
          _offeringEntries = [for (final o in offerings) _entryFor(o)];
        });
      }
    } finally {
      if (mounted) setState(() => _loadingOfferings = false);
    }
  }

  bool get _canSave => _offeringId != null && !_saving;

  late final List<PickerEntry> _subjectEntries = [
    for (final s in widget.subjectOptions)
      PickerEntry(id: s.id, title: s.code, subtitle: s.title),
  ];

  SubjectOption? get _subject {
    for (final s in widget.subjectOptions) {
      if (s.id == _subjectId) return s;
    }
    return null;
  }

  /// Grouped under the program of the section the class belongs to (read
  /// from its name, e.g. "BSIT-3B"); the row's subtitle is its year and the
  /// professor.
  PickerEntry _entryFor(ClassSectionOffering o) => PickerEntry.section(
        id: o.id,
        name: o.sectionName,
        subtitle: o.professorName,
      );

  Future<void> _handleSave() async {
    final offeringId = _offeringId;
    if (offeringId == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(offeringId);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppPopup(
      title: 'Enroll in Subject',
      subtitle: _subjectId == null
          ? 'Step 1 of 2 — pick the subject.'
          : 'Step 2 of 2 — pick the offering. It can belong to any '
              'section; choose a different one than the student\'s '
              'own to enroll them irregularly for just this subject.',
      width: 520,
      closeEnabled: !_saving,
      // The pickers scroll their own lists, so they get a bounded height.
      scrollBody: false,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_subjectId == null)
            Flexible(
              child: SearchablePickerList(
                searchHint: 'Search subjects',
                emptyMessage: 'No subjects available.',
                palette: RegistrarColors.picker(context),
                groupNoun: 'subject',
                entries: _subjectEntries,
                onSelected: (id) {
                  if (!_saving) _handleSubjectChanged(id);
                },
              ),
            )
          else ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    _subject?.label ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppPopupColors.of(context).text,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SecondaryPillButton(
                  label: 'Change subject',
                  onTap: _saving ? null : () => _handleSubjectChanged(null),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_loadingOfferings)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else
              Flexible(
                child: SearchablePickerList(
                  key: ValueKey(_subjectId),
                  searchHint: 'Search sections or professors',
                  emptyMessage: 'No offerings exist yet for this subject.',
                  palette: RegistrarColors.picker(context),
                  groupByProgram: true,
                  groupNoun: 'offering',
                  entries: _offeringEntries,
                  selectedId: _offeringId,
                  onSelected: (id) {
                    if (!_saving) setState(() => _offeringId = id);
                  },
                ),
              ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
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
          label: 'Enroll',
          loading: _saving,
          onPressed: _canSave ? _handleSave : null,
        ),
      ],
    );
  }
}
