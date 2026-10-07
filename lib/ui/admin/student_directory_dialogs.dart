import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app/session_controller.dart';
import '../../models/student_record.dart';

// The Student Directory's three popups — View, Edit, Delete — are all built
// from the shared popup pieces in `dashboard_layout` (`AppPopup` and friends),
// so they match every other popup in the app, in both themes.

/// Read-only detail view opened by the Student Directory's "View" action.
Future<void> showStudentViewDialog(
  BuildContext context,
  StudentRecord student,
) {
  return showAppPopup<void>(
    context: context,
    builder: (dialogContext) {
      final colors = AppPopupColors.of(dialogContext);
      return AppPopup(
        title: student.fullName,
        width: 460,
        body: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: colors.fieldFill,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _DetailRow(label: 'Student number', value: student.studentNumber),
              _DetailRow(label: 'Course', value: student.course),
              _DetailRow(label: 'Year level', value: student.yearLevel),
              _DetailRow(
                  label: 'Section',
                  value: student.section.isEmpty ? '—' : student.section),
              _DetailRow(
                label: 'RFID card',
                value:
                    student.rfidUid.isEmpty ? 'Unassigned' : student.rfidUid,
              ),
              _DetailRow(
                label: 'Guardian',
                value:
                    student.guardianName.isEmpty ? '—' : student.guardianName,
              ),
            ],
          ),
        ),
        actions: [
          AppPopupSecondaryButton(
            label: 'Close',
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
        ],
      );
    },
  );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = AppPopupColors.of(context);
    final size = context.isMobileWidth ? 11.0 : 13.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: GoogleFonts.poppins(fontSize: size, color: colors.muted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.poppins(
                fontSize: size,
                fontWeight: FontWeight.w600,
                color: colors.text,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Data collected by [showStudentEditDialog].
class StudentEditResult {
  const StudentEditResult({
    required this.firstName,
    required this.middleInitial,
    required this.lastName,
    required this.course,
    required this.yearLevel,
    required this.sectionName,
  });

  final String firstName;
  final String middleInitial;
  final String lastName;
  final String course;
  final int yearLevel;
  final String sectionName;
}

const _courseOptions = [
  'BS Business Administration',
  'BS Hospitality Management',
  'BS Information Technology',
  'BS Tourism Management',
];

/// Edit form opened by the Student Directory's "Edit" action. Returns the
/// edited fields via `Navigator.pop`, or `null` if cancelled.
Future<StudentEditResult?> showStudentEditDialog(
  BuildContext context,
  StudentRecord student, {
  required Future<List<String>> Function({
    required String program,
    required int yearLevel,
  }) fetchSectionNames,
}) {
  return showAppPopup<StudentEditResult>(
    context: context,
    builder: (dialogContext) => _StudentEditDialog(
      student: student,
      fetchSectionNames: fetchSectionNames,
    ),
  );
}

class _StudentEditDialog extends StatefulWidget {
  const _StudentEditDialog({
    required this.student,
    required this.fetchSectionNames,
  });

  final StudentRecord student;
  final Future<List<String>> Function({
    required String program,
    required int yearLevel,
  }) fetchSectionNames;

  @override
  State<_StudentEditDialog> createState() => _StudentEditDialogState();
}

class _StudentEditDialogState extends State<_StudentEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _firstNameController =
      TextEditingController(text: widget.student.firstName);
  late final _middleInitialController =
      TextEditingController(text: widget.student.middleInitial);
  late final _lastNameController =
      TextEditingController(text: widget.student.lastName);

  late String _course = _courseOptions.contains(widget.student.course)
      ? widget.student.course
      : _courseOptions.first;
  late int _yearLevel = widget.student.yearLevelInt;
  String? _sectionName;
  List<String> _sectionOptions = [];
  bool _loadingSections = true;

  @override
  void initState() {
    super.initState();
    _loadSections(initial: widget.student.section);
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _middleInitialController.dispose();
    _lastNameController.dispose();
    super.dispose();
  }

  Future<void> _loadSections({String? initial}) async {
    setState(() => _loadingSections = true);
    try {
      final names = await widget.fetchSectionNames(
        program: _course,
        yearLevel: _yearLevel,
      );
      if (!mounted) return;
      setState(() {
        _sectionOptions = names;
        _sectionName = (initial != null && names.contains(initial))
            ? initial
            : (names.isEmpty ? null : names.first);
      });
    } finally {
      if (mounted) setState(() => _loadingSections = false);
    }
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final section = _sectionName;
    if (section == null) return;
    Navigator.of(context).pop(
      StudentEditResult(
        firstName: _firstNameController.text.trim(),
        middleInitial: _middleInitialController.text.trim(),
        lastName: _lastNameController.text.trim(),
        course: _course,
        yearLevel: _yearLevel,
        sectionName: section,
      ),
    );
  }

  AppPopupFormCell _textCell(
    String label,
    TextEditingController controller, {
    int flex = 1,
    bool required = false,
  }) {
    return AppPopupFormCell(
      label: label,
      flex: flex,
      child: Builder(
        builder: (context) => TextFormField(
          controller: controller,
          style: appPopupFieldStyle(context),
          cursorColor: AppPopupColors.accent,
          decoration: appPopupInputDecoration(context),
          validator: required
              ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null
              : null,
        ),
      ),
    );
  }

  Widget _arrow(BuildContext context) => Icon(
        Icons.keyboard_arrow_down_rounded,
        size: 20,
        color: AppPopupColors.of(context).muted,
      );

  @override
  Widget build(BuildContext context) {
    final colors = AppPopupColors.of(context);
    return AppPopup(
      title: 'Edit Student',
      width: 720,
      body: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AppPopupSection('Personal Details',
                icon: Icons.person_outline_rounded),
            AppPopupFormRow(children: [
              _textCell('First Name', _firstNameController,
                  flex: 3, required: true),
              _textCell('Last Name', _lastNameController,
                  flex: 3, required: true),
              _textCell('M.I.', _middleInitialController),
            ]),
            const AppPopupSection('Academic Details',
                icon: Icons.school_outlined),
            AppPopupFormRow(children: [
              AppPopupFormCell(
                label: 'Course',
                flex: 3,
                child: DropdownButtonFormField<String>(
                  value: _course,
                  isExpanded: true,
                  icon: _arrow(context),
                  style: appPopupFieldStyle(context),
                  dropdownColor: colors.card,
                  decoration: appPopupInputDecoration(context),
                  items: _courseOptions
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _course = value);
                    _loadSections();
                  },
                ),
              ),
              AppPopupFormCell(
                label: 'Year Level',
                flex: 2,
                child: DropdownButtonFormField<int>(
                  value: _yearLevel,
                  isExpanded: true,
                  icon: _arrow(context),
                  style: appPopupFieldStyle(context),
                  dropdownColor: colors.card,
                  decoration: appPopupInputDecoration(context),
                  items: [1, 2, 3, 4]
                      .map((y) => DropdownMenuItem(
                            value: y,
                            child: Text(StudentRecord.yearLevelToLabel(y)),
                          ))
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _yearLevel = value);
                    _loadSections();
                  },
                ),
              ),
              AppPopupFormCell(
                label: 'Section',
                flex: 2,
                child: DropdownButtonFormField<String>(
                  value: _sectionOptions.contains(_sectionName)
                      ? _sectionName
                      : null,
                  isExpanded: true,
                  icon: _arrow(context),
                  style: appPopupFieldStyle(context),
                  dropdownColor: colors.card,
                  decoration: appPopupInputDecoration(
                    context,
                    hint: _loadingSections
                        ? 'Loading sections...'
                        : (_sectionOptions.isEmpty ? 'No sections found' : null),
                  ),
                  items: _sectionOptions
                      .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
                  onChanged: (value) => setState(() => _sectionName = value),
                ),
              ),
            ]),
          ],
        ),
      ),
      actions: [
        AppPopupSecondaryButton(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppPopupPrimaryButton(
          label: 'Save Changes',
          onPressed: _sectionName == null ? null : _save,
        ),
      ],
    );
  }
}

/// Danger-zone delete confirmation opened by the Student Directory's
/// "Delete" action. Requires typing the student number to confirm intent,
/// plus a password re-check when [SessionController.canVerifyPassword] is
/// true (only the static demo accounts have a password to re-check —
/// Microsoft-authenticated accounts fall back to the typed confirmation
/// alone). Returns `true` if the deletion should proceed.
Future<bool> showStudentDeleteDialog(
  BuildContext context,
  StudentRecord student,
  SessionController session,
) async {
  final result = await showAppPopup<bool>(
    context: context,
    builder: (dialogContext) => _StudentDeleteDialog(
      student: student,
      session: session,
    ),
  );
  return result ?? false;
}

class _StudentDeleteDialog extends StatefulWidget {
  const _StudentDeleteDialog({required this.student, required this.session});

  final StudentRecord student;
  final SessionController session;

  @override
  State<_StudentDeleteDialog> createState() => _StudentDeleteDialogState();
}

class _StudentDeleteDialogState extends State<_StudentDeleteDialog> {
  final _confirmController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _confirmController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _attemptDelete() {
    final typedNumber = _confirmController.text.trim();
    if (typedNumber != widget.student.studentNumber) {
      setState(() => _error = 'Student number does not match.');
      return;
    }

    if (widget.session.canVerifyPassword) {
      if (!widget.session.verifyPassword(_passwordController.text)) {
        setState(() => _error = 'Incorrect password.');
        return;
      }
    }

    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final requiresPassword = widget.session.canVerifyPassword;
    final colors = AppPopupColors.of(context);
    final textSize = context.isMobileWidth ? 11.0 : 13.0;

    return AppPopup(
      title: 'Delete Student Record',
      width: 460,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.warning_amber_rounded,
                  color: AppPopupColors.danger, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'You are about to permanently delete '
                  '${widget.student.fullName} (${widget.student.studentNumber}). '
                  'This also removes their attendance, violation, and RFID '
                  'records. This action cannot be undone.',
                  style: GoogleFonts.poppins(
                    fontSize: textSize,
                    height: 1.5,
                    color: colors.text,
                  ),
                ),
              ),
            ],
          ),
          kAppPopupFieldGap,
          AppPopupTextField(
            label: 'Type the student number '
                '"${widget.student.studentNumber}" to confirm',
            controller: _confirmController,
            hint: 'Student number',
          ),
          if (requiresPassword) ...[
            kAppPopupFieldGap,
            AppPopupTextField(
              label: 'Confirm your password',
              controller: _passwordController,
              hint: 'Password',
              obscureText: true,
            ),
          ] else ...[
            const SizedBox(height: 12),
            Text(
              'Signed in with Microsoft — there\'s no separate password to '
              're-check, so typing the student number above is the '
              'confirmation for this account.',
              style: GoogleFonts.poppins(
                fontSize: context.isMobileWidth ? 10 : 12,
                color: colors.muted,
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
          onPressed: () => Navigator.of(context).pop(false),
        ),
        AppPopupPrimaryButton(
          label: 'Delete Permanently',
          destructive: true,
          onPressed: _attemptDelete,
        ),
      ],
    );
  }
}
