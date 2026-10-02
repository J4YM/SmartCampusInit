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
  List<ClassSectionOffering>? _offerings;
  bool _loadingOfferings = false;
  String? _offeringId;
  bool _saving = false;
  String? _error;

  Future<void> _handleSubjectChanged(String? subjectId) async {
    setState(() {
      _subjectId = subjectId;
      _offerings = null;
      _offeringId = null;
      _error = null;
    });
    if (subjectId == null) return;
    setState(() => _loadingOfferings = true);
    try {
      final offerings = await widget.onFetchOfferings(subjectId);
      if (mounted) setState(() => _offerings = offerings);
    } finally {
      if (mounted) setState(() => _loadingOfferings = false);
    }
  }

  bool get _canSave => _offeringId != null && !_saving;

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

  InputDecoration _decoration(BuildContext context, String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: GoogleFonts.poppins(fontSize: 13, color: RegistrarColors.mutedText(context)),
      filled: true,
      fillColor: RegistrarColors.background(context),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final offerings = _offerings ?? const <ClassSectionOffering>[];
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: SizedBox(
        width: 440,
        child: BentoCard(
          backgroundColor: RegistrarColors.card(context),
          borderColor: RegistrarColors.cardBorder(context),
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Enroll in Subject',
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: RegistrarColors.rowText(context),
                      ),
                    ),
                  ),
                  Tooltip(
                    message: 'Close',
                    child: InkWell(
                      onTap: _saving ? null : () => Navigator.of(context).pop(),
                      borderRadius: BorderRadius.circular(20),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(Icons.close_rounded, size: 22, color: RegistrarColors.rowText(context)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'The offering can belong to any section — pick a different '
                'one than the student\'s own to enroll them irregularly for '
                'just this subject.',
                style: GoogleFonts.poppins(fontSize: 12, color: RegistrarColors.mutedText(context)),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                value: _subjectId,
                isExpanded: true,
                decoration: _decoration(context, 'Subject'),
                items: [
                  for (final s in widget.subjectOptions)
                    DropdownMenuItem(value: s.id, child: Text(s.label)),
                ],
                onChanged: _saving ? null : _handleSubjectChanged,
              ),
              const SizedBox(height: 12),
              if (_loadingOfferings)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else if (_subjectId != null && offerings.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'No offerings exist yet for this subject.',
                    style: GoogleFonts.poppins(fontSize: 12, color: RegistrarColors.mutedText(context)),
                  ),
                )
              else if (offerings.isNotEmpty)
                DropdownButtonFormField<String>(
                  value: _offeringId,
                  isExpanded: true,
                  decoration: _decoration(context, 'Offering (section — professor)'),
                  items: [
                    for (final o in offerings)
                      DropdownMenuItem(
                        value: o.id,
                        child: Text('${o.sectionName} — ${o.professorName}'),
                      ),
                  ],
                  onChanged: _saving ? null : (value) => setState(() => _offeringId = value),
                ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: RegistrarColors.dangerRed)),
              ],
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  SecondaryPillButton(
                    label: 'Cancel',
                    onTap: _saving ? null : () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 10),
                  _DialogPillButton(
                    label: 'Enroll',
                    background: RegistrarColors.azureBlue,
                    foreground: Colors.white,
                    onTap: _canSave ? _handleSave : null,
                    loading: _saving,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DialogPillButton extends StatelessWidget {
  const _DialogPillButton({
    required this.label,
    required this.background,
    required this.foreground,
    required this.onTap,
    this.loading = false,
  });

  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback? onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return Material(
      color: disabled && !loading ? background.withOpacity(0.5) : background,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: loading
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(foreground),
                  ),
                )
              : Text(
                  label,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: disabled ? foreground.withOpacity(0.6) : foreground,
                  ),
                ),
        ),
      ),
    );
  }
}
