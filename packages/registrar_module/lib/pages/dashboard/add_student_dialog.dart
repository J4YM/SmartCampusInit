import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'edit_student_dialog.dart' show isValidGuardianMobile;

const _courseOptions = [
  'BS Business Administration',
  'BS Hospitality Management',
  'BS Information Technology',
  'BS Tourism Management',
];
const _yearLevelOptions = ['1st Year', '2nd Year', '3rd Year', '4th Year'];

/// Everything [AddStudentDialog] collects to hand off to
/// `StudentsRepository.create()` — a new student's enrollment record. RFID
/// isn't collected here; it gets linked later, once IT Technician prints
/// and hands over the physical card.
class NewStudentForm {
  const NewStudentForm({
    required this.studentNumber,
    required this.firstName,
    required this.middleInitial,
    required this.lastName,
    required this.course,
    required this.yearLevel,
    required this.section,
    required this.email,
    required this.contactNo,
    this.guardianName = '',
    this.guardianContactNo = '',
  });

  /// Optional parent/guardian details; `guardianContactNo` is the number SMS
  /// alerts are sent to.
  final String guardianName;
  final String guardianContactNo;

  final String studentNumber;
  final String firstName;
  final String middleInitial;
  final String lastName;
  final String course;
  final String yearLevel;
  final String section;
  final String email;
  final String contactNo;
}

/// Registrar's "Add New Student" form — the entry point for onboarding a
/// student into `students`/`profiles`, the same tables IT Technician's own
/// Student Records tab already reads and writes.
class AddStudentDialog extends StatefulWidget {
  const AddStudentDialog({super.key, required this.onSave});

  final Future<void> Function(NewStudentForm form) onSave;

  @override
  State<AddStudentDialog> createState() => _AddStudentDialogState();
}

class _AddStudentDialogState extends State<AddStudentDialog> {
  final _studentNumberController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _middleInitialController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _sectionController = TextEditingController();
  final _emailController = TextEditingController();
  final _contactController = TextEditingController();
  final _guardianNameController = TextEditingController();
  final _guardianContactController = TextEditingController();
  String? _course;
  String? _yearLevel;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _studentNumberController.dispose();
    _firstNameController.dispose();
    _middleInitialController.dispose();
    _lastNameController.dispose();
    _sectionController.dispose();
    _emailController.dispose();
    _contactController.dispose();
    _guardianNameController.dispose();
    _guardianContactController.dispose();
    super.dispose();
  }

  String? get _guardianContactError {
    final v = _guardianContactController.text.trim();
    return v.isEmpty || isValidGuardianMobile(v)
        ? null
        : 'Use a PH mobile number, e.g. 09171234567';
  }

  bool get _canSave =>
      _studentNumberController.text.trim().isNotEmpty &&
      _firstNameController.text.trim().isNotEmpty &&
      _lastNameController.text.trim().isNotEmpty &&
      _course != null &&
      _yearLevel != null &&
      _sectionController.text.trim().isNotEmpty &&
      _guardianContactError == null &&
      !_saving;

  Future<void> _handleSave() async {
    if (!_canSave) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(
        NewStudentForm(
          studentNumber: _studentNumberController.text.trim(),
          firstName: _firstNameController.text.trim(),
          middleInitial: _middleInitialController.text.trim(),
          lastName: _lastNameController.text.trim(),
          course: _course!,
          yearLevel: _yearLevel!,
          section: _sectionController.text.trim(),
          email: _emailController.text.trim(),
          contactNo: _contactController.text.trim(),
          guardianName: _guardianNameController.text.trim(),
          guardianContactNo: _guardianContactController.text.trim(),
        ),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ---- Presentation -------------------------------------------------------
  //
  // The shared popup (`AppPopup`), laid out like Edit Student and IT
  // Technician's Register Student: grouped sections, field cells that sit
  // side by side and stack on a narrow screen, the Cancel / primary footer.

  AppPopupFormCell _text(
    String label,
    Key key,
    TextEditingController controller, {
    int flex = 1,
    String? errorText,
    TextInputType? keyboardType,
    bool rebuildOnChange = false,
  }) {
    return AppPopupFormCell(
      label: label,
      flex: flex,
      child: Builder(
        builder: (context) => TextField(
          key: key,
          controller: controller,
          enabled: !_saving,
          keyboardType: keyboardType,
          style: appPopupFieldStyle(context),
          cursorColor: AppPopupColors.accent,
          decoration: appPopupInputDecoration(context, errorText: errorText),
          onChanged: rebuildOnChange ? (_) => setState(() {}) : null,
        ),
      ),
    );
  }

  AppPopupFormCell _dropdown(
    String label,
    Key key,
    String? value,
    List<String> options,
    ValueChanged<String?> onChanged, {
    int flex = 1,
  }) {
    return AppPopupFormCell(
      label: label,
      flex: flex,
      child: Builder(
        builder: (context) {
          final colors = AppPopupColors.of(context);
          return DropdownButtonFormField<String>(
            key: key,
            value: value,
            isExpanded: true,
            icon: Icon(Icons.keyboard_arrow_down_rounded,
                size: 20, color: colors.muted),
            style: appPopupFieldStyle(context),
            dropdownColor: colors.card,
            decoration: appPopupInputDecoration(context),
            items: [
              for (final o in options)
                DropdownMenuItem(value: o, child: Text(o)),
            ],
            onChanged: _saving ? null : onChanged,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppPopup(
      title: 'Add New Student',
      width: 720,
      closeEnabled: !_saving,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[
            Text(
              _error!,
              key: const Key('add-student-error'),
              style: GoogleFonts.poppins(
                fontSize: context.isMobileWidth ? 10 : 12,
                fontWeight: FontWeight.w500,
                color: AppPopupColors.danger,
              ),
            ),
            const SizedBox(height: 12),
          ],
          const AppPopupSection('Student Information',
              icon: Icons.badge_outlined),
          AppPopupFormRow(children: [
            _text('Student Number', const Key('add-student-number'),
                _studentNumberController,
                flex: 2, rebuildOnChange: true),
            _text('Email (optional)', const Key('add-email'),
                _emailController,
                flex: 3, keyboardType: TextInputType.emailAddress),
            _text('Contact No. (optional)', const Key('add-contact'),
                _contactController,
                flex: 3, keyboardType: TextInputType.phone),
          ]),
          const AppPopupSection('Academic Details',
              icon: Icons.school_outlined),
          AppPopupFormRow(children: [
            _dropdown('Course', const Key('add-course'), _course,
                _courseOptions, (v) => setState(() => _course = v),
                flex: 3),
            _dropdown('Year Level', const Key('add-year-level'), _yearLevel,
                _yearLevelOptions, (v) => setState(() => _yearLevel = v),
                flex: 2),
            _text('Section', const Key('add-section'), _sectionController,
                flex: 2, rebuildOnChange: true),
          ]),
          const AppPopupSection('Personal Details',
              icon: Icons.person_outline_rounded),
          AppPopupFormRow(children: [
            _text('First Name', const Key('add-first-name'),
                _firstNameController,
                flex: 3, rebuildOnChange: true),
            _text('Last Name', const Key('add-last-name'),
                _lastNameController,
                flex: 3, rebuildOnChange: true),
            _text('M.I.', const Key('add-middle-initial'),
                _middleInitialController),
          ]),
          const AppPopupSection('Parent / Guardian',
              icon: Icons.family_restroom_outlined),
          AppPopupFormRow(children: [
            _text('Parent/Guardian Name (optional)',
                const Key('add-guardian-name'), _guardianNameController,
                flex: 3),
            _text('Guardian Contact No. (optional)',
                const Key('add-guardian-contact'), _guardianContactController,
                flex: 2,
                keyboardType: TextInputType.phone,
                errorText: _guardianContactError,
                rebuildOnChange: true),
          ]),
        ],
      ),
      actions: [
        AppPopupSecondaryButton(
          key: const Key('add-student-cancel'),
          label: 'Cancel',
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
        ),
        AppPopupPrimaryButton(
          key: const Key('add-student-save'),
          label: 'Add Student',
          loading: _saving,
          onPressed: _canSave ? _handleSave : null,
        ),
      ],
    );
  }
}
