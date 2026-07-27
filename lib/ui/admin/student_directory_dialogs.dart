import 'package:flutter/material.dart';

import '../../app/session_controller.dart';
import '../../models/student_record.dart';

/// Read-only detail view opened by the Student Directory's "View" action.
Future<void> showStudentViewDialog(
  BuildContext context,
  StudentRecord student,
) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: Text(student.fullName),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DetailRow(label: 'Student number', value: student.studentNumber),
              _DetailRow(label: 'Course', value: student.course),
              _DetailRow(label: 'Year level', value: student.yearLevel),
              _DetailRow(label: 'Section', value: student.section.isEmpty ? '—' : student.section),
              _DetailRow(
                label: 'RFID card',
                value: student.rfidUid.isEmpty ? 'Unassigned' : student.rfidUid,
              ),
              _DetailRow(
                label: 'Guardian',
                value: student.guardianName.isEmpty ? '—' : student.guardianName,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
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
  return showDialog<StudentEditResult>(
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

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit Student'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: _firstNameController,
                        decoration: const InputDecoration(
                          labelText: 'First name',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _middleInitialController,
                        decoration: const InputDecoration(
                          labelText: 'M.I.',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _lastNameController,
                  decoration: const InputDecoration(
                    labelText: 'Last name',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _course,
                  decoration: const InputDecoration(
                    labelText: 'Course',
                    border: OutlineInputBorder(),
                  ),
                  items: _courseOptions
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _course = value);
                    _loadSections();
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  value: _yearLevel,
                  decoration: const InputDecoration(
                    labelText: 'Year level',
                    border: OutlineInputBorder(),
                  ),
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
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _sectionOptions.contains(_sectionName) ? _sectionName : null,
                  decoration: InputDecoration(
                    labelText: 'Section',
                    border: const OutlineInputBorder(),
                    helperText: _loadingSections
                        ? 'Loading sections...'
                        : (_sectionOptions.isEmpty ? 'No sections found.' : null),
                  ),
                  items: _sectionOptions
                      .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
                  onChanged: (value) => setState(() => _sectionName = value),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _sectionName == null ? null : _save,
          child: const Text('Save Changes'),
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
  final result = await showDialog<bool>(
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

    return AlertDialog(
      backgroundColor: Colors.white,
      title: const Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626)),
          SizedBox(width: 8),
          Text('Delete Student Record', style: TextStyle(color: Color(0xFFDC2626))),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                border: Border.all(color: const Color(0xFFFECACA)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'You are about to permanently delete '
                '${widget.student.fullName} (${widget.student.studentNumber}). '
                'This also removes their attendance, violation, and RFID '
                'records. This action cannot be undone.',
                style: const TextStyle(color: Color(0xFF991B1B), fontSize: 13),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Type the student number "${widget.student.studentNumber}" to confirm:',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _confirmController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Student number',
              ),
            ),
            if (requiresPassword) ...[
              const SizedBox(height: 16),
              const Text(
                'Confirm your password:',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Password',
                ),
                onSubmitted: (_) => _attemptDelete(),
              ),
            ] else ...[
              const SizedBox(height: 12),
              const Text(
                'Signed in with Microsoft — there\'s no separate password to '
                're-check, so typing the student number above is the '
                'confirmation for this account.',
                style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Color(0xFFDC2626), fontSize: 12)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
          onPressed: _attemptDelete,
          child: const Text('Delete Permanently'),
        ),
      ],
    );
  }
}
