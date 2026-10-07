import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'registrar_dashboard_page.dart' show RegistrarStudentModel;

/// Everything [EditStudentDialog] hands back to persist — a student's
/// personal and parent/guardian details. Course, year level and section are
/// deliberately absent: "Change Section" owns those as one consistent unit,
/// and the RFID card is IT Technician's.
class EditStudentForm {
  const EditStudentForm({
    required this.studentNumber,
    required this.firstName,
    required this.middleInitial,
    required this.lastName,
    required this.email,
    required this.contactNo,
    required this.guardianName,
    required this.guardianContactNo,
  });

  final String studentNumber;
  final String firstName;
  final String middleInitial;
  final String lastName;
  final String email;

  /// The student's own phone number (`profiles.phone_number`).
  final String contactNo;
  final String guardianName;

  /// The guardian's mobile (`students.guardian_contact_no`) — the number SMS
  /// alerts (tap in/out, parent interventions) are sent to.
  final String guardianContactNo;
}

/// Same acceptance rule as `normalize_ph_mobile` in
/// `supabase/add_sms_alerts_schema.sql` and `isValidPhMobile` in the app's
/// guidance repository: 09XXXXXXXXX, 9XXXXXXXXX or 639XXXXXXXXX, ignoring
/// spaces, dashes and a leading '+'. Kept local because this package cannot
/// import the app package.
bool isValidGuardianMobile(String raw) {
  final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
  return RegExp(r'^(639\d{9}|09\d{9}|9\d{9})$').hasMatch(digits);
}

/// Registrar's "Edit Student Details" form — lets an enrolled student's
/// name, student number, email, phone and parent/guardian details be
/// corrected by hand after they're already in the system.
class EditStudentDialog extends StatefulWidget {
  const EditStudentDialog({
    super.key,
    required this.student,
    required this.onSave,
  });

  final RegistrarStudentModel student;
  final Future<void> Function(String studentId, EditStudentForm form) onSave;

  @override
  State<EditStudentDialog> createState() => _EditStudentDialogState();
}

class _EditStudentDialogState extends State<EditStudentDialog> {
  late final _studentNumberController =
      TextEditingController(text: widget.student.studentId);
  late final _firstNameController =
      TextEditingController(text: widget.student.firstName);
  late final _middleInitialController =
      TextEditingController(text: widget.student.middleInitial);
  late final _lastNameController =
      TextEditingController(text: widget.student.lastName);
  late final _emailController =
      TextEditingController(text: widget.student.email);
  late final _contactController =
      TextEditingController(text: widget.student.contactNo);
  late final _guardianNameController =
      TextEditingController(text: widget.student.parentGuardian);
  late final _guardianContactController =
      TextEditingController(text: widget.student.guardianContactNo);
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _studentNumberController.dispose();
    _firstNameController.dispose();
    _middleInitialController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _contactController.dispose();
    _guardianNameController.dispose();
    _guardianContactController.dispose();
    super.dispose();
  }

  String? get _emailError {
    final v = _emailController.text.trim();
    return v.isEmpty || v.contains('@') ? null : 'Enter a valid email address';
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
      _emailError == null &&
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
        widget.student.id,
        EditStudentForm(
          studentNumber: _studentNumberController.text.trim(),
          firstName: _firstNameController.text.trim(),
          middleInitial: _middleInitialController.text.trim(),
          lastName: _lastNameController.text.trim(),
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
  // Laid out exactly like IT Technician's Edit Student popup — the same shared
  // popup pieces (`AppPopup`, grouped sections with an icon and a rule, field
  // cells that sit side by side and stack on a narrow screen, the Cancel /
  // Save Changes footer) — with the fields a Registrar may edit.

  /// A labelled text field, one cell of a form row.
  AppPopupFormCell _cell(
    String label,
    Key fieldKey,
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
          key: fieldKey,
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

  @override
  Widget build(BuildContext context) {
    return AppPopup(
      title: 'Edit Student',
      width: 720,
      closeEnabled: !_saving,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[
            Text(
              _error!,
              key: const Key('edit-student-error'),
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
            _cell('Student Number', const Key('edit-student-number'),
                _studentNumberController,
                flex: 2, rebuildOnChange: true),
            _cell('Email (optional)', const Key('edit-email'),
                _emailController,
                flex: 3,
                keyboardType: TextInputType.emailAddress,
                errorText: _emailError,
                rebuildOnChange: true),
            _cell('Contact No. (optional)',
                const Key('edit-contact'), _contactController,
                flex: 3, keyboardType: TextInputType.phone),
          ]),
          const AppPopupSection('Personal Details',
              icon: Icons.person_outline_rounded),
          AppPopupFormRow(children: [
            _cell('First Name', const Key('edit-first-name'),
                _firstNameController,
                flex: 3, rebuildOnChange: true),
            _cell('Last Name', const Key('edit-last-name'),
                _lastNameController,
                flex: 3, rebuildOnChange: true),
            _cell('M.I.', const Key('edit-middle-initial'),
                _middleInitialController),
          ]),
          const AppPopupSection('Parent / Guardian',
              icon: Icons.family_restroom_outlined),
          AppPopupFormRow(children: [
            _cell('Parent/Guardian Name', const Key('edit-guardian-name'),
                _guardianNameController,
                flex: 3),
            _cell('Guardian Contact No.', const Key('edit-guardian-contact'),
                _guardianContactController,
                flex: 2,
                keyboardType: TextInputType.phone,
                errorText: _guardianContactError,
                rebuildOnChange: true),
          ]),
          Text(
            'SMS alerts (tap in/out, parent interventions) are sent to the '
            'guardian contact number.',
            style: GoogleFonts.poppins(
              fontSize: context.isMobileWidth ? 10 : 11,
              color: AppPopupColors.of(context).muted,
            ),
          ),
        ],
      ),
      actions: [
        AppPopupSecondaryButton(
          key: const Key('edit-student-cancel'),
          label: 'Cancel',
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
        ),
        AppPopupPrimaryButton(
          key: const Key('edit-student-save'),
          label: 'Save Changes',
          loading: _saving,
          onPressed: _canSave ? _handleSave : null,
        ),
      ],
    );
  }
}
