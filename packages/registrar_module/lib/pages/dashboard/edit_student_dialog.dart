import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/registrar_colors.dart';
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

  InputDecoration _decoration(
    BuildContext context,
    String label, {
    String? errorText,
  }) {
    return InputDecoration(
      labelText: label,
      errorText: errorText,
      labelStyle: GoogleFonts.poppins(
        fontSize: 13,
        color: RegistrarColors.mutedText(context),
      ),
      filled: true,
      fillColor: RegistrarColors.background(context),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 10),
      child: Text(
        text,
        style: GoogleFonts.poppins(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: RegistrarColors.rowText(context),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: SizedBox(
        width: 460,
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
                      'Edit Student Details',
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
                        child: Icon(
                          Icons.close_rounded,
                          size: 22,
                          color: RegistrarColors.rowText(context),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _sectionLabel(context, 'Student'),
                      TextField(
                        key: const Key('edit-student-number'),
                        controller: _studentNumberController,
                        decoration: _decoration(context, 'Student Number'),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: TextField(
                              key: const Key('edit-first-name'),
                              controller: _firstNameController,
                              decoration: _decoration(context, 'First Name'),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              key: const Key('edit-middle-initial'),
                              controller: _middleInitialController,
                              decoration: _decoration(context, 'M.I.'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const Key('edit-last-name'),
                        controller: _lastNameController,
                        decoration: _decoration(context, 'Last Name'),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const Key('edit-email'),
                        controller: _emailController,
                        decoration: _decoration(
                          context,
                          'Email (optional)',
                          errorText: _emailError,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const Key('edit-contact'),
                        controller: _contactController,
                        decoration:
                            _decoration(context, 'Student Contact No. (optional)'),
                      ),
                      const SizedBox(height: 20),
                      _sectionLabel(context, 'Parent / Guardian'),
                      TextField(
                        key: const Key('edit-guardian-name'),
                        controller: _guardianNameController,
                        decoration:
                            _decoration(context, 'Parent/Guardian Name'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const Key('edit-guardian-contact'),
                        controller: _guardianContactController,
                        keyboardType: TextInputType.phone,
                        decoration: _decoration(
                          context,
                          'Guardian Contact No.',
                          errorText: _guardianContactError,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'SMS alerts (tap in/out, parent interventions) are sent '
                        'to this number.',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: RegistrarColors.mutedText(context),
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          key: const Key('edit-student-error'),
                          style:
                              const TextStyle(color: RegistrarColors.dangerRed),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  SecondaryPillButton(
                    label: 'Cancel',
                    onTap: _saving ? null : () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    key: const Key('edit-student-save'),
                    onPressed: _canSave ? _handleSave : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: RegistrarColors.azureBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      minimumSize: const Size(0, kDashboardControlHeight),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : Text(
                            'Save Changes',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
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
