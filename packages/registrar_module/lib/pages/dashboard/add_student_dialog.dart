import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/registrar_colors.dart';

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
  });

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
    super.dispose();
  }

  bool get _canSave =>
      _studentNumberController.text.trim().isNotEmpty &&
      _firstNameController.text.trim().isNotEmpty &&
      _lastNameController.text.trim().isNotEmpty &&
      _course != null &&
      _yearLevel != null &&
      _sectionController.text.trim().isNotEmpty &&
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
        ),
      );
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
                      'Add New Student',
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
                      TextField(
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
                              controller: _firstNameController,
                              decoration: _decoration(context, 'First Name'),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _middleInitialController,
                              decoration: _decoration(context, 'M.I.'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _lastNameController,
                        decoration: _decoration(context, 'Last Name'),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: _course,
                        decoration: _decoration(context, 'Course'),
                        items: [
                          for (final c in _courseOptions)
                            DropdownMenuItem(value: c, child: Text(c)),
                        ],
                        onChanged: (value) => setState(() => _course = value),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: _yearLevel,
                              decoration: _decoration(context, 'Year Level'),
                              items: [
                                for (final y in _yearLevelOptions)
                                  DropdownMenuItem(value: y, child: Text(y)),
                              ],
                              onChanged: (value) =>
                                  setState(() => _yearLevel = value),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _sectionController,
                              decoration: _decoration(context, 'Section'),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _emailController,
                        decoration: _decoration(context, 'Email (optional)'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _contactController,
                        decoration:
                            _decoration(context, 'Contact No. (optional)'),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
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
                  _DialogPillButton(
                    label: 'Cancel',
                    background: RegistrarColors.background(context),
                    foreground: RegistrarColors.rowText(context),
                    onTap: _saving ? null : () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 10),
                  _DialogPillButton(
                    label: 'Add Student',
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: disabled ? foreground.withOpacity(0.6) : foreground,
                  ),
                ),
        ),
      ),
    );
  }
}
