import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app/session_controller.dart';
import '../data/students_repository.dart';
import '../env.dart';
import '../models/student_record.dart';

/// Shown after a student-pattern Microsoft sign-in when `profiles.status` is
/// approved (assigned automatically by `handle_new_auth_user`) but no
/// `students` row exists yet for this account — see
/// `SessionController.needsStudentSetup` and
/// supabase/add_student_self_registration_schema.sql.
///
/// Two outcomes, decided by whether a `students` row already exists for the
/// student number embedded in the signed-in email:
///   - None found: a short registration form creates one (name, course,
///     year, section). The student number itself is fixed — read-only,
///     derived from the verified school email — and assigned server-side.
///   - One found (most likely pre-registered by the RFID Management module
///     under an anonymous account): a "claim my record" prompt re-homes it
///     onto this Microsoft-linked account instead.
class StudentRegistrationGatePage extends StatefulWidget {
  const StudentRegistrationGatePage({super.key, required this.session});

  final SessionController session;

  @override
  State<StudentRegistrationGatePage> createState() =>
      _StudentRegistrationGatePageState();
}

enum _GateMode { loading, error, register, claim }

class _StudentRegistrationGatePageState
    extends State<StudentRegistrationGatePage> {
  static const _courseOptions = [
    'BS Business Administration',
    'BS Hospitality Management',
    'BS Information Technology',
    'BS Tourism Management',
  ];
  static const _yearLevels = [1, 2, 3, 4];

  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _middleInitialController = TextEditingController();
  final _lastNameController = TextEditingController();

  String? _course;
  int? _yearLevel;
  String? _sectionName;
  List<String> _sectionOptions = [];
  bool _loadingSections = false;

  _GateMode _mode = _GateMode.loading;
  String? _error;
  bool _submitting = false;
  String? _studentNumber;

  StudentsRepository? get _repo {
    if (!AppEnv.supabaseConfigured) return null;
    return StudentsRepository(Supabase.instance.client);
  }

  String? get _email => widget.session.studentSetupEmail;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkExistingRecord());
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _middleInitialController.dispose();
    _lastNameController.dispose();
    super.dispose();
  }

  String? _deriveStudentNumber(String? email) {
    if (email == null) return null;
    final match =
        RegExp(r'\.(\d{6})@baliuag\.sti\.edu\.ph$', caseSensitive: false)
            .firstMatch(email.trim());
    return match?.group(1);
  }

  Future<void> _checkExistingRecord() async {
    final repo = _repo;
    final number = _deriveStudentNumber(_email);
    _studentNumber = number;

    if (repo == null || number == null) {
      setState(() {
        _mode = _GateMode.error;
        _error = number == null
            ? 'Could not determine your student number from your Microsoft '
                'account email (${_email ?? 'unknown'}). Contact an '
                'administrator.'
            : 'Supabase is not configured.';
      });
      return;
    }

    setState(() {
      _mode = _GateMode.loading;
      _error = null;
    });
    try {
      final existing = await repo.fetchByStudentNumber(number);
      if (!mounted) return;
      setState(() {
        _mode = existing != null ? _GateMode.claim : _GateMode.register;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _mode = _GateMode.error;
        _error = 'Could not check existing records: $e';
      });
    }
  }

  Future<void> _loadSections() async {
    final repo = _repo;
    final course = _course;
    final year = _yearLevel;
    if (repo == null || course == null || year == null) return;
    setState(() {
      _loadingSections = true;
      _sectionOptions = [];
      _sectionName = null;
    });
    try {
      final names =
          await repo.fetchSectionNames(program: course, yearLevel: year);
      if (!mounted) return;
      setState(() => _sectionOptions = names);
    } catch (e) {
      if (!mounted) return;
      _toast('Could not load sections: $e');
    } finally {
      if (mounted) setState(() => _loadingSections = false);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _submitRegistration() async {
    final repo = _repo;
    if (repo == null) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_course == null || _yearLevel == null || _sectionName == null) {
      _toast('Choose a course, year level, and section.');
      return;
    }

    setState(() => _submitting = true);
    try {
      await repo.completeSelfRegistration(
        firstName: _firstNameController.text,
        middleInitial: _middleInitialController.text,
        lastName: _lastNameController.text,
        course: _course!,
        yearLevel: _yearLevel!,
        sectionName: _sectionName!,
      );
      await widget.session.refreshAfterStudentSetup();
    } catch (e) {
      _toast('Could not complete registration: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _submitClaim() async {
    final repo = _repo;
    if (repo == null) return;
    setState(() => _submitting = true);
    try {
      await repo.claimPreregisteredStudent();
      await widget.session.refreshAfterStudentSetup();
    } catch (e) {
      _toast('Could not claim this record: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: _buildBody(),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (_mode) {
      case _GateMode.loading:
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 64),
          child: Center(child: CircularProgressIndicator()),
        );
      case _GateMode.error:
        return _ErrorCard(
          message: _error ?? 'Something went wrong.',
          onRetry: _checkExistingRecord,
          onSignOut: widget.session.signOut,
        );
      case _GateMode.claim:
        return _ClaimCard(
          studentNumber: _studentNumber ?? '',
          submitting: _submitting,
          onClaim: _submitClaim,
          onSignOut: widget.session.signOut,
        );
      case _GateMode.register:
        return _buildRegistrationForm();
    }
  }

  InputDecoration _decoration(String label, {String? helperText}) {
    return InputDecoration(
      labelText: label,
      helperText: helperText,
      border: const OutlineInputBorder(),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );
  }

  Widget _buildRegistrationForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.badge_outlined,
              size: 40, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          Text(
            'Complete your student profile',
            style:
                GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            'Signed in as ${_email ?? '—'}. Your student ID is fixed to '
            "${_studentNumber ?? '—'}, taken from your school email — it "
            "can't be changed here. Once this is saved, the RFID Office can "
            'assign a card to your profile.',
            style: GoogleFonts.poppins(
                fontSize: 13, color: const Color(0xFF64748B)),
          ),
          const SizedBox(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: TextFormField(
                  controller: _firstNameController,
                  decoration: _decoration('First name'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _middleInitialController,
                  decoration: _decoration('M.I.'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _lastNameController,
            decoration: _decoration('Last name'),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Required' : null,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _course,
            decoration: _decoration('Course'),
            items: _courseOptions
                .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                .toList(),
            onChanged: (value) {
              setState(() => _course = value);
              _loadSections();
            },
            validator: (v) => v == null ? 'Required' : null,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            value: _yearLevel,
            decoration: _decoration('Year level'),
            items: _yearLevels
                .map((y) => DropdownMenuItem(
                      value: y,
                      child: Text(StudentRecord.yearLevelToLabel(y)),
                    ))
                .toList(),
            onChanged: (value) {
              setState(() => _yearLevel = value);
              _loadSections();
            },
            validator: (v) => v == null ? 'Required' : null,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _sectionName,
            decoration: _decoration(
              'Section',
              helperText: _loadingSections
                  ? 'Loading sections...'
                  : (_course != null &&
                          _yearLevel != null &&
                          _sectionOptions.isEmpty)
                      ? 'No sections found for this course/year.'
                      : null,
            ),
            items: _sectionOptions
                .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                .toList(),
            onChanged: (value) => setState(() => _sectionName = value),
            validator: (v) => v == null ? 'Required' : null,
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: widget.session.signOut,
                child: const Text('Sign out'),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: _submitting ? null : _submitRegistration,
                child: _submitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Create my profile'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({
    required this.message,
    required this.onRetry,
    required this.onSignOut,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.error_outline_rounded, size: 40, color: Colors.red),
        const SizedBox(height: 16),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton(onPressed: onSignOut, child: const Text('Sign out')),
            const SizedBox(width: 12),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ],
    );
  }
}

class _ClaimCard extends StatelessWidget {
  const _ClaimCard({
    required this.studentNumber,
    required this.submitting,
    required this.onClaim,
    required this.onSignOut,
  });

  final String studentNumber;
  final bool submitting;
  final VoidCallback onClaim;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.credit_card_outlined,
            size: 40, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 16),
        Text(
          'This student ID is already on file',
          style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          'Student ID $studentNumber was already registered in our system — '
          'most likely by the RFID Office before you signed in with '
          'Microsoft. Claim it to link it to this account. Your name, '
          'course, section, and any RFID card already on file will carry '
          'over.',
          style: GoogleFonts.poppins(
              fontSize: 13, color: const Color(0xFF64748B)),
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(onPressed: onSignOut, child: const Text('Sign out')),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: submitting ? null : onClaim,
              icon: submitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.link_rounded),
              label: const Text('Claim my record'),
            ),
          ],
        ),
      ],
    );
  }
}
