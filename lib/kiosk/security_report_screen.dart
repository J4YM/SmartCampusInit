import 'package:discipline_officer_module/discipline_officer_module.dart'
    show OffenseOption;
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
    required this.offenseIds,
    required this.notes,
    required this.escalateNow,
  });

  final String studentId;
  final String studentDisplayName;
  final String studentNumber;
  final String gradeSection;
  final List<String> offenseIds;
  final String notes;
  final bool escalateNow;
}

/// The Security Personnel kiosk-mode flow — opened when a staff RFID tap
/// resolves to a Security role (see `CapstoneKioskScanHost.onStaffIdentified`).
/// Unlike the student self-report flow (`ViolationKioskScreen`, limited to
/// whoever tapped), this lets the officer: search for and report on any
/// student, attach free-text notes, escalate immediately, and — since the
/// report is attributed to their own resolved profile id, not the shared
/// kiosk system account — the case shows who actually filed it.
///
/// Built from the same `student_kiosk_module` kiosk blocks as
/// `ViolationKioskScreen` (header, card column, category cards, count card,
/// confirm button) so both kiosk menus share one big, touch-first layout.
class SecurityReportScreen extends StatefulWidget {
  const SecurityReportScreen({
    super.key,
    required this.officerName,
    required this.offenseOptions,
    required this.onSearchStudents,
    required this.onSubmit,
  });

  final String officerName;
  final List<OffenseOption> offenseOptions;
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

  List<SecurityReportStudentOption> _studentResults = const [];
  SecurityReportStudentOption? _selectedStudent;
  bool _searching = false;

  /// The query the current [_studentResults] answer — non-empty with no
  /// results means "searched, nothing matched" rather than "not searched".
  String _lastQuery = '';

  final _selectedOffenseIds = <String>{};
  bool _escalateNow = false;

  @override
  void dispose() {
    _studentSearchController.dispose();
    _notesController.dispose();
    super.dispose();
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
    });
  }

  void _toggleOffense(String id) {
    setState(() {
      if (!_selectedOffenseIds.remove(id)) _selectedOffenseIds.add(id);
    });
  }

  bool get _canSubmit =>
      _selectedStudent != null && _selectedOffenseIds.isNotEmpty;

  void _submit() {
    final student = _selectedStudent;
    if (student == null || _selectedOffenseIds.isEmpty) return;

    widget.onSubmit(
      SecurityReportSubmission(
        studentId: student.id,
        studentDisplayName: student.displayName,
        studentNumber: student.studentNumber,
        gradeSection: student.gradeSection,
        offenseIds: _selectedOffenseIds.toList(),
        notes: _notesController.text.trim(),
        escalateNow: _escalateNow,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final categories = _groupByCategory(widget.offenseOptions);

    return KioskPage(
      headerSubtitle: 'Security Report',
      children: [
        _OfficerCard(officerName: widget.officerName),
        const SizedBox(height: 20),
        _StudentPickerCard(
          selected: _selectedStudent,
          controller: _studentSearchController,
          results: _studentResults,
          searching: _searching,
          noMatches: !_searching &&
              _lastQuery.isNotEmpty &&
              _studentResults.isEmpty,
          onChanged: _search,
          onSelect: _selectStudent,
          onClear: () => setState(() => _selectedStudent = null),
        ),
        const SizedBox(height: 20),
        const KioskInstructionAlert(
          title: 'Select the violation(s)',
          body: 'Select all violations that apply to the student you are '
              'reporting.',
        ),
        const SizedBox(height: 20),
        if (categories.isEmpty) ...[
          KioskCard(
            child: Text(
              'No offense list loaded.',
              style: kioskPoppins(
                fontSize: 24,
                fontWeight: FontWeight.w500,
                color: KioskColors.textMuted,
              ),
            ),
          ),
          const SizedBox(height: 20),
        ] else
          for (final category in categories) ...[
            KioskViolationCategoryCard(
              category: category,
              selectedCodes: _selectedOffenseIds,
              onToggle: _toggleOffense,
            ),
            const SizedBox(height: 20),
          ],
        _NotesCard(controller: _notesController),
        const SizedBox(height: 20),
        KioskCard(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
          child: KioskSelectableRow(
            selected: _escalateNow,
            onTap: () => setState(() => _escalateNow = !_escalateNow),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Escalate immediately',
                  style: kioskPoppins(
                    fontSize: 24,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  'Skips the normal pending-review queue',
                  style: kioskPoppins(
                    fontSize: 13,
                    color: KioskColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        KioskSelectedCountCard(
          selectedCount: _selectedOffenseIds.length,
          caption: _selectedStudent == null
              ? 'Choose the student above, then select their violation(s)'
              : 'Review your selection, then continue to preview the '
                  'admission slip',
        ),
        const SizedBox(height: 16),
        KioskConfirmButton(
          label: 'Review & Submit',
          enabled: _canSubmit,
          busy: false,
          onPressed: _canSubmit ? _submit : null,
        ),
      ],
    );
  }
}

List<ViolationCategoryData> _groupByCategory(List<OffenseOption> options) {
  final byCategory = <String, List<OffenseOption>>{};
  for (final option in options) {
    final category = option.category ?? 'Minor';
    byCategory.putIfAbsent(category, () => []).add(option);
  }
  return [
    for (final category in ViolationCategoryData.handbookCategoryOrder)
      if (byCategory[category] case final items? when items.isNotEmpty)
        ViolationCategoryData.handbook(category, [
          for (final option in items)
            ViolationItemData(title: option.label, code: option.id),
        ]),
  ];
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
  });

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
              onChanged: onChanged,
              style: kioskPoppins(fontSize: 24, fontWeight: FontWeight.w500),
              decoration: kioskInputDecoration(
                hintText: 'Search by student number',
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
                'No student matches that number.',
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
  const _NotesCard({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return KioskCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const KioskFieldLabel('Notes'),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
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
