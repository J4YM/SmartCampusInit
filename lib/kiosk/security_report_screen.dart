import 'package:flutter/material.dart';
import 'package:student_kiosk_module/student_kiosk.dart';

/// One student result row shown while searching for who to report.
class SecurityReportStudentOption {
  const SecurityReportStudentOption({
    required this.id,
    required this.displayName,
    required this.studentNumber,
    required this.gradeSection,
  });

  final String id;
  final String displayName;
  final String studentNumber;
  final String gradeSection;
}

/// Everything needed to open the admission slip preview once the officer
/// taps Submit — nothing is written yet at this point (see
/// `CapstoneKioskScanHost._openSlipPreview`, which both this screen and the
/// student self-report flow share).
class SecurityReportSubmission {
  const SecurityReportSubmission({
    required this.studentId,
    required this.studentDisplayName,
    required this.studentNumber,
    required this.gradeSection,
    required this.incidentAt,
    required this.notes,
  });

  final String studentId;
  final String studentDisplayName;
  final String studentNumber;
  final String gradeSection;
  /// When the incident happened (not when it is being reported).
  final DateTime incidentAt;
  final String notes;
}

/// The Security Personnel kiosk-mode flow — opened when a staff RFID tap
/// resolves to a Security role (see `CapstoneKioskScanHost.onStaffIdentified`).
/// Unlike the student self-report flow (`ViolationKioskScreen`, limited to
/// whoever tapped), this lets the officer: search for and report on any
/// student, say when it happened and what happened — the Discipline Officer
/// classifies the violation later — and, since the report is attributed to their own resolved profile id, not the shared
/// kiosk system account — the case shows who actually filed it.
///
/// Built from the same `student_kiosk_module` kiosk blocks as
/// `ViolationKioskScreen` (header, card column, category cards, count card,
/// confirm button) so both kiosk menus share one big, touch-first layout.
class SecurityReportScreen extends StatefulWidget {
  const SecurityReportScreen({
    super.key,
    required this.officerName,
    required this.onSearchStudents,
    required this.onSubmit,
  });

  final String officerName;
  final Future<List<SecurityReportStudentOption>> Function(String query)
      onSearchStudents;

  /// Opens the admission slip preview — synchronous (no database write
  /// happens here), so this screen stays on the navigation stack
  /// underneath the preview, ready to be returned to if the officer taps
  /// Cancel there to adjust the offense selection or notes.
  final void Function(SecurityReportSubmission submission) onSubmit;

  @override
  State<SecurityReportScreen> createState() => _SecurityReportScreenState();
}

class _SecurityReportScreenState extends State<SecurityReportScreen> {
  final _studentSearchController = TextEditingController();
  final _notesController = TextEditingController();
  final _studentSearchFocus = FocusNode();
  final _notesFocus = FocusNode();

  /// The field the on-screen keyboard is currently typing into, or null when
  /// the keyboard is hidden. The kiosk is touch-only, so tapping the student
  /// search (or notes) must bring up its own keyboard.
  TextEditingController? _keyboardTarget;
  bool get _keyboardForNotes => identical(_keyboardTarget, _notesController);

  /// Space reserved under the page so the keyboard never covers the field
  /// being typed in or the controls beneath it.
  static const _keyboardClearance = 360.0;

  List<SecurityReportStudentOption> _studentResults = const [];
  SecurityReportStudentOption? _selectedStudent;
  bool _searching = false;

  /// The query the current [_studentResults] answer — non-empty with no
  /// results means "searched, nothing matched" rather than "not searched".
  String _lastQuery = '';

  /// Minutes before now the incident happened; 0 is "Just now".
  int _minutesAgo = 0;

  @override
  void initState() {
    super.initState();
    _notesController.addListener(() => setState(() {}));
    _studentSearchFocus.addListener(() {
      if (_studentSearchFocus.hasFocus) {
        _showKeyboard(_studentSearchController, _studentSearchFocus);
      }
    });
    _notesFocus.addListener(() {
      if (_notesFocus.hasFocus) _showKeyboard(_notesController, _notesFocus);
    });
  }

  @override
  void dispose() {
    _studentSearchFocus.dispose();
    _notesFocus.dispose();
    _studentSearchController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _showKeyboard(TextEditingController controller, FocusNode focus) {
    if (!identical(_keyboardTarget, controller)) {
      setState(() => _keyboardTarget = controller);
    }
    // Scroll the field above the keyboard once the clearance spacer is laid
    // out.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = focus.context;
      if (ctx != null && ctx.mounted) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.1,
          duration: const Duration(milliseconds: 200),
        );
      }
    });
  }

  void _hideKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
    if (_keyboardTarget != null) setState(() => _keyboardTarget = null);
  }

  Future<void> _search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _studentResults = const [];
        _lastQuery = '';
      });
      return;
    }
    setState(() => _searching = true);
    try {
      final results = await widget.onSearchStudents(trimmed);
      if (!mounted) return;
      setState(() {
        _studentResults = results;
        _lastQuery = trimmed;
        _searching = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _studentResults = const [];
        _lastQuery = trimmed;
        _searching = false;
      });
    }
  }

  void _selectStudent(SecurityReportStudentOption student) {
    setState(() {
      _selectedStudent = student;
      _studentResults = const [];
      _lastQuery = '';
      _studentSearchController.clear();
      // The search field is replaced by the selected student's summary.
      if (!_keyboardForNotes) _keyboardTarget = null;
    });
  }

  bool get _canSubmit =>
      _selectedStudent != null && _notesController.text.trim().isNotEmpty;

  void _submit() {
    final student = _selectedStudent;
    if (student == null || !_canSubmit) return;

    widget.onSubmit(
      SecurityReportSubmission(
        studentId: student.id,
        studentDisplayName: student.displayName,
        studentNumber: student.studentNumber,
        gradeSection: student.gradeSection,
        incidentAt: DateTime.now().subtract(Duration(minutes: _minutesAgo)),
        notes: _notesController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final page = KioskPage(
      headerSubtitle: 'Security Report',
      children: [
        _OfficerCard(officerName: widget.officerName),
        const SizedBox(height: 20),
        _StudentPickerCard(
          selected: _selectedStudent,
          controller: _studentSearchController,
          results: _studentResults,
          searching: _searching,
          focusNode: _studentSearchFocus,
          onActivate: () =>
              _showKeyboard(_studentSearchController, _studentSearchFocus),
          noMatches: !_searching &&
              _lastQuery.isNotEmpty &&
              _studentResults.isEmpty,
          onChanged: _search,
          onSelect: _selectStudent,
          onClear: () => setState(() => _selectedStudent = null),
        ),
        const SizedBox(height: 20),
        _WhenCard(
          minutesAgo: _minutesAgo,
          onChanged: (m) => setState(() => _minutesAgo = m),
        ),
        const SizedBox(height: 20),
        _NotesCard(
          controller: _notesController,
          focusNode: _notesFocus,
          onActivate: () => _showKeyboard(_notesController, _notesFocus),
        ),
        const SizedBox(height: 20),
        KioskInstructionAlert(
          title: 'Describe the incident',
          body: _selectedStudent == null
              ? 'Choose the student above, say when it happened and what '
                  'happened.'
              : 'Student Affairs will classify the violation after reviewing '
                  'your report.',
        ),
        const SizedBox(height: 16),
        KioskConfirmButton(
          label: 'Review & Submit',
          enabled: _canSubmit,
          busy: false,
          onPressed: _canSubmit ? _submit : null,
        ),
        if (_keyboardTarget != null) const SizedBox(height: _keyboardClearance),
      ],
    );

    final target = _keyboardTarget;
    if (target == null) return page;
    return Stack(
      children: [
        page,
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: KioskOnScreenKeyboard(
            controller: target,
            multiline: _keyboardForNotes,
            // The search field is driven programmatically by the keyboard, so
            // its own onChanged never fires — search from here instead.
            onChanged: identical(target, _studentSearchController)
                ? _search
                : null,
            onDone: _hideKeyboard,
          ),
        ),
      ],
    );
  }
}

/// Mirrors the student kiosk's student card: who is using the kiosk, plus
/// the Back action.
class _OfficerCard extends StatelessWidget {
  const _OfficerCard({required this.officerName});

  final String officerName;

  @override
  Widget build(BuildContext context) {
    final name = officerName.trim();
    return KioskCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.isEmpty ? '—' : name,
                  style: kioskPoppins(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: name.isEmpty
                        ? KioskColors.textMuted
                        : KioskColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Security Personnel',
                  style: kioskPoppins(
                    fontSize: 24,
                    fontWeight: FontWeight.w500,
                    color: KioskColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const KioskBackButton(),
        ],
      ),
    );
  }
}

class _StudentPickerCard extends StatelessWidget {
  const _StudentPickerCard({
    required this.selected,
    required this.controller,
    required this.results,
    required this.searching,
    required this.noMatches,
    required this.onChanged,
    required this.onSelect,
    required this.onClear,
    required this.focusNode,
    required this.onActivate,
  });

  final FocusNode focusNode;

  /// Brings up the on-screen keyboard (also on a re-tap after it was hidden
  /// with Done, when the field is still focused and no focus event fires).
  final VoidCallback onActivate;

  final SecurityReportStudentOption? selected;
  final TextEditingController controller;
  final List<SecurityReportStudentOption> results;
  final bool searching;
  final bool noMatches;
  final ValueChanged<String> onChanged;
  final ValueChanged<SecurityReportStudentOption> onSelect;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final student = selected;
    return KioskCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const KioskFieldLabel('Reporting on which student?'),
          const SizedBox(height: 8),
          if (student != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: KioskColors.gradientTop,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: KioskColors.itemBorder),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _StudentSummary(student: student, emphasize: true),
                  ),
                  TextButton(
                    onPressed: onClear,
                    style: TextButton.styleFrom(
                      foregroundColor: KioskColors.alertTitle,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                    ),
                    child: Text(
                      'Change',
                      style: kioskPoppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: KioskColors.alertTitle,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else ...[
            TextField(
              controller: controller,
              focusNode: focusNode,
              // Typed with the kiosk's own on-screen keyboard; suppresses the
              // OS soft keyboard (a physical keyboard still works).
              keyboardType: TextInputType.none,
              onTap: onActivate,
              onChanged: onChanged,
              style: kioskPoppins(fontSize: 24, fontWeight: FontWeight.w500),
              decoration: kioskInputDecoration(
                hintText: 'Search by name or student number',
                suffixIcon: searching
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : const Icon(
                        Icons.search_rounded,
                        size: 28,
                        color: KioskColors.textSecondary,
                      ),
              ),
            ),
            if (noMatches) ...[
              const SizedBox(height: 12),
              Text(
                'No student matches that name or number.',
                style: kioskPoppins(
                  fontSize: 16,
                  color: KioskColors.textSecondary,
                ),
              ),
            ],
            for (final r in results) ...[
              const SizedBox(height: 12),
              KioskSelectableRow(
                onTap: () => onSelect(r),
                child: _StudentSummary(student: r),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _StudentSummary extends StatelessWidget {
  const _StudentSummary({required this.student, this.emphasize = false});

  final SecurityReportStudentOption student;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          student.displayName,
          style: kioskPoppins(
            fontSize: 24,
            fontWeight: emphasize ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        Text(
          'Student No: ${student.studentNumber} · ${student.gradeSection}',
          style: kioskPoppins(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: KioskColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _NotesCard extends StatelessWidget {
  const _NotesCard({
    required this.controller,
    required this.focusNode,
    required this.onActivate,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onActivate;

  @override
  Widget build(BuildContext context) {
    return KioskCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const KioskFieldLabel('What happened?'),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            focusNode: focusNode,
            keyboardType: TextInputType.none,
            onTap: onActivate,
            minLines: 3,
            maxLines: 6,
            style: kioskPoppins(fontSize: 20),
            decoration: kioskInputDecoration(
              hintText: 'What happened, where, who else was involved…',
            ).copyWith(
              hintMaxLines: 2,
              hintStyle: kioskPoppins(
                fontSize: 20,
                color: KioskColors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "When did it happen?" — touch-friendly choices rather than a clock picker.
class _WhenCard extends StatelessWidget {
  const _WhenCard({required this.minutesAgo, required this.onChanged});

  final int minutesAgo;
  final ValueChanged<int> onChanged;

  static const _choices = <(String, int)>[
    ('Just now', 0),
    ('15 minutes ago', 15),
    ('30 minutes ago', 30),
    ('1 hour ago', 60),
    ('2 hours ago', 120),
    ('3 hours ago', 180),
  ];

  @override
  Widget build(BuildContext context) {
    return KioskCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const KioskFieldLabel('When did it happen?'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final (label, minutes) in _choices)
                SizedBox(
                  width: 260,
                  child: KioskSelectableRow(
                    selected: minutesAgo == minutes,
                    onTap: () => onChanged(minutes),
                    child: Text(
                      label,
                      style: kioskPoppins(
                          fontSize: 22, fontWeight: FontWeight.w500),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
