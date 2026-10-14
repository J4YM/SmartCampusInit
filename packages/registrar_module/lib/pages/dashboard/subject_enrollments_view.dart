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

/// One class_sections row offering a subject — a candidate in the
/// "Enroll in Subject" dialog, once a subject is chosen. Deliberately not
/// scoped to the student's own home section — offerings from every section
/// are valid candidates, which is exactly what lets a student enroll
/// "irregularly".
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

/// The "View Subjects" button on a student's profile card. Tapping it opens a
/// popup with the student's subject-level enrollments and the "Enroll in
/// Subject" action — including enrolling them in an offering that belongs to
/// a different section than their own, which is the entire mechanism for
/// handling an irregular student (see the schema design spec above). The
/// popup owns its own load state; the profile card stays short.
class ViewSubjectsButton extends StatelessWidget {
  const ViewSubjectsButton({
    super.key,
    required this.studentId,
    required this.studentName,
    required this.onFetchEnrollments,
    this.subjectOptions = const [],
    this.onFetchOfferings,
    this.onEnroll,
    this.onDrop,
    this.onDropStudent,
  });

  final String studentId;
  final String studentName;
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

  /// Falls back to no "Drop Student" footer action when omitted.
  final Future<void> Function(String studentId)? onDropStudent;

  @override
  Widget build(BuildContext context) {
    return RegistrarPillButton(
      key: const Key('view-subjects'),
      label: 'View Subjects',
      icon: Icons.menu_book_rounded,
      expand: true,
      onTap: () => showAppPopup<void>(
        context: context,
        builder: (_) => _SubjectsDialog(
          studentId: studentId,
          studentName: studentName,
          onFetchEnrollments: onFetchEnrollments,
          subjectOptions: subjectOptions,
          onFetchOfferings: onFetchOfferings,
          onEnroll: onEnroll,
          onDrop: onDrop,
          onDropStudent: onDropStudent,
        ),
      ),
    );
  }
}

/// The popup behind [ViewSubjectsButton]: the student's subjects, a Drop
/// action on each (when allowed) and "Enroll in Subject" in the footer.
class _SubjectsDialog extends StatefulWidget {
  const _SubjectsDialog({
    required this.studentId,
    required this.studentName,
    required this.onFetchEnrollments,
    required this.subjectOptions,
    required this.onFetchOfferings,
    required this.onEnroll,
    required this.onDrop,
    required this.onDropStudent,
  });

  final String studentId;
  final String studentName;
  final Future<List<StudentEnrollmentModel>> Function(String studentId)
      onFetchEnrollments;
  final List<SubjectOption> subjectOptions;
  final Future<List<ClassSectionOffering>> Function(String subjectId)?
      onFetchOfferings;
  final Future<void> Function(String studentId, String classSectionId)?
      onEnroll;
  final Future<void> Function(String enrollmentId)? onDrop;

  /// Falls back to no "Drop Student" footer action when omitted.
  final Future<void> Function(String studentId)? onDropStudent;

  @override
  State<_SubjectsDialog> createState() => _SubjectsDialogState();
}

class _SubjectsDialogState extends State<_SubjectsDialog> {
  List<StudentEnrollmentModel>? _enrollments;
  bool _loading = true;
  Object? _error;

  bool get _canEnroll =>
      widget.onEnroll != null && widget.onFetchOfferings != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final enrollments = await widget.onFetchEnrollments(widget.studentId);
      if (mounted) setState(() => _enrollments = enrollments);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openEnrollDialog() async {
    final onEnroll = widget.onEnroll;
    final onFetchOfferings = widget.onFetchOfferings;
    if (onEnroll == null || onFetchOfferings == null) return;
    await showAppPopup<void>(
      context: context,
      builder: (_) => _EnrollInSubjectDialog(
        subjectOptions: widget.subjectOptions,
        onFetchOfferings: onFetchOfferings,
        onSave: (classSectionId) => onEnroll(widget.studentId, classSectionId),
      ),
    );
    if (mounted) _load();
  }

  Future<void> _handleDrop(StudentEnrollmentModel enrollment) async {
    final onDrop = widget.onDrop;
    if (onDrop == null) return;
    // Dropping changes the student's load, so it is a deliberate act.
    final confirmed = await showAppPopup<bool>(
      context: context,
      builder: (_) => _ConfirmDropDialog(
        studentName: widget.studentName,
        enrollment: enrollment,
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await onDrop(enrollment.enrollmentId);
    } catch (e) {
      if (mounted) setState(() => _error = e);
      return;
    }
    if (mounted) _load();
  }

  Future<void> _handleDropStudent() async {
    final onDropStudent = widget.onDropStudent;
    if (onDropStudent == null) return;
    final confirmed = await showAppPopup<bool>(
      context: context,
      builder: (_) => _ConfirmDropStudentDialog(
        studentName: widget.studentName,
        subjectCount: (_enrollments ?? const []).length,
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await onDropStudent(widget.studentId);
    } catch (e) {
      if (mounted) setState(() => _error = e);
      return;
    }
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppPopupColors.of(context);
    final mobile = context.isMobileWidth;
    final enrollments = _enrollments ?? const <StudentEnrollmentModel>[];

    final Widget content;
    if (_loading && _enrollments == null) {
      content = const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    } else if (enrollments.isEmpty) {
      content = Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            _error != null
                ? 'Could not load the subjects.'
                : 'No subject enrollments on file yet.',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: mobile ? 11 : 13,
              color: c.muted,
            ),
          ),
        ),
      );
    } else {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final e in enrollments)
            Container(
              key: ValueKey('subject-${e.enrollmentId}'),
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
              decoration: BoxDecoration(
                color: c.fieldFill,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          e.subjectTitle,
                          style: GoogleFonts.poppins(
                            fontSize: mobile ? 12 : 13,
                            fontWeight: FontWeight.w600,
                            color: c.text,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${e.sectionName} — ${e.professorName}'
                          '${e.isIrregular ? '  ·  Irregular' : ''}',
                          style: GoogleFonts.poppins(
                            fontSize: mobile ? 10 : 11.5,
                            color: e.isIrregular
                                ? subNavActiveColor(
                                    context, AppPopupColors.accent)
                                : c.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (widget.onDrop != null)
                    Tooltip(
                      message: 'Drop',
                      child: IconButton(
                        key: ValueKey('drop-${e.enrollmentId}'),
                        onPressed: () => _handleDrop(e),
                        padding: const EdgeInsets.all(8),
                        constraints:
                            const BoxConstraints.tightFor(width: 36, height: 36),
                        icon: Icon(Icons.close_rounded,
                            size: 18, color: c.muted, semanticLabel: 'Drop'),
                      ),
                    ),
                ],
              ),
            ),
        ],
      );
    }

    return AppPopup(
      title: 'Subjects',
      subtitle: widget.studentName,
      width: 520,
      actions: [
        AppPopupSecondaryButton(
          label: 'Close',
          onPressed: () => Navigator.of(context).pop(),
        ),
        if (widget.onDropStudent != null)
          AppPopupPrimaryButton(
            key: const Key('drop-student'),
            label: 'Drop Student',
            icon: Icons.person_remove_rounded,
            destructive: true,
            onPressed: _handleDropStudent,
          ),
        if (_canEnroll)
          AppPopupPrimaryButton(
            key: const Key('enroll-in-subject'),
            label: 'Enroll in Subject',
            icon: Icons.add_rounded,
            onPressed: _openEnrollDialog,
          ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          content,
          if (_error != null && enrollments.isNotEmpty) ...[
            const SizedBox(height: 4),
            AppPopupError('$_error'),
          ],
        ],
      ),
    );
  }
}

/// "Drop this subject?" — asked before a subject is dropped from a student.
class _ConfirmDropDialog extends StatelessWidget {
  const _ConfirmDropDialog({
    required this.studentName,
    required this.enrollment,
  });

  final String studentName;
  final StudentEnrollmentModel enrollment;

  @override
  Widget build(BuildContext context) {
    final c = AppPopupColors.of(context);
    final mobile = context.isMobileWidth;
    return AppPopup(
      title: 'Drop this subject?',
      width: 460,
      actions: [
        AppPopupSecondaryButton(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(false),
        ),
        AppPopupPrimaryButton(
          key: const Key('confirm-drop-subject'),
          label: 'Drop Subject',
          destructive: true,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '$studentName will be dropped from ${enrollment.subjectTitle} '
            '(${enrollment.sectionName} — ${enrollment.professorName}).',
            style: GoogleFonts.poppins(
              fontSize: mobile ? 11 : 13,
              height: 1.5,
              color: c.text,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'The enrollment is marked Dropped and leaves their subject list. '
            'You can enroll them in it again with Enroll in Subject.',
            style: GoogleFonts.poppins(
              fontSize: mobile ? 10 : 12,
              height: 1.5,
              color: c.muted,
            ),
          ),
        ],
      ),
    );
  }
}

/// "Drop this student?" — asked before every one of a student's subjects is
/// dropped at once (a withdrawal).
class _ConfirmDropStudentDialog extends StatelessWidget {
  const _ConfirmDropStudentDialog({
    required this.studentName,
    required this.subjectCount,
  });

  final String studentName;
  final int subjectCount;

  @override
  Widget build(BuildContext context) {
    final c = AppPopupColors.of(context);
    final mobile = context.isMobileWidth;
    return AppPopup(
      title: 'Drop this student?',
      width: 460,
      actions: [
        AppPopupSecondaryButton(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(false),
        ),
        AppPopupPrimaryButton(
          key: const Key('confirm-drop-student'),
          label: 'Drop Student',
          destructive: true,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '$studentName will be withdrawn: all $subjectCount of their '
            'subjects are marked Dropped.',
            style: GoogleFonts.poppins(
              fontSize: mobile ? 11 : 13,
              height: 1.5,
              color: c.text,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'The student is then counted as a dropout in the ML risk model. '
            'Subjects can be restored one by one with Enroll in Subject.',
            style: GoogleFonts.poppins(
              fontSize: mobile ? 10 : 12,
              height: 1.5,
              color: c.muted,
            ),
          ),
        ],
      ),
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
