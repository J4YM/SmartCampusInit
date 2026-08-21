import 'package:discipline_officer_module/discipline_officer_module.dart'
    show OffenseOption;
import 'package:flutter/material.dart';

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

/// Everything needed to write the report(s) once the officer taps Submit.
class SecurityReportSubmission {
  const SecurityReportSubmission({
    required this.studentId,
    required this.offenseIds,
    required this.notes,
    required this.escalateNow,
  });

  final String studentId;
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
  final Future<void> Function(SecurityReportSubmission submission) onSubmit;

  @override
  State<SecurityReportScreen> createState() => _SecurityReportScreenState();
}

class _SecurityReportScreenState extends State<SecurityReportScreen> {
  final _studentSearchController = TextEditingController();
  final _notesController = TextEditingController();

  List<SecurityReportStudentOption> _studentResults = const [];
  SecurityReportStudentOption? _selectedStudent;
  bool _searching = false;

  final _selectedOffenseIds = <String>{};
  bool _escalateNow = false;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _studentSearchController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() => _studentResults = const []);
      return;
    }
    setState(() => _searching = true);
    try {
      final results = await widget.onSearchStudents(trimmed);
      if (!mounted) return;
      setState(() {
        _studentResults = results;
        _searching = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _studentResults = const [];
        _searching = false;
      });
    }
  }

  void _selectStudent(SecurityReportStudentOption student) {
    setState(() {
      _selectedStudent = student;
      _studentResults = const [];
      _studentSearchController.clear();
    });
  }

  bool get _canSubmit =>
      _selectedStudent != null && _selectedOffenseIds.isNotEmpty && !_submitting;

  Future<void> _submit() async {
    final student = _selectedStudent;
    if (student == null || _selectedOffenseIds.isEmpty) return;

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.onSubmit(
        SecurityReportSubmission(
          studentId: student.id,
          offenseIds: _selectedOffenseIds.toList(),
          notes: _notesController.text.trim(),
          escalateNow: _escalateNow,
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = 'Could not submit report: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = _groupByCategory(widget.offenseOptions);

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        backgroundColor: const Color(0xFF15253F),
        foregroundColor: Colors.white,
        title: Text('Security Report — ${widget.officerName}'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(_error!,
                      style: const TextStyle(color: Color(0xFFB91C1C))),
                ),
              _StudentPicker(
                selected: _selectedStudent,
                controller: _studentSearchController,
                results: _studentResults,
                searching: _searching,
                onChanged: _search,
                onSelect: _selectStudent,
                onClear: () => setState(() => _selectedStudent = null),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Offense(s)',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      if (categories.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text('No offense list loaded.'),
                        )
                      else
                        for (final entry in categories.entries) ...[
                          Padding(
                            padding: const EdgeInsets.only(top: 8, bottom: 4),
                            child: Text(
                              entry.key,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 13),
                            ),
                          ),
                          for (final offense in entry.value)
                            CheckboxListTile(
                              dense: true,
                              controlAffinity:
                                  ListTileControlAffinity.leading,
                              title: Text(offense.label),
                              value: _selectedOffenseIds.contains(offense.id),
                              onChanged: (checked) => setState(() {
                                if (checked ?? false) {
                                  _selectedOffenseIds.add(offense.id);
                                } else {
                                  _selectedOffenseIds.remove(offense.id);
                                }
                              }),
                            ),
                        ],
                      const SizedBox(height: 12),
                      TextField(
                        controller: _notesController,
                        minLines: 3,
                        maxLines: 6,
                        decoration: const InputDecoration(
                          labelText: 'Notes',
                          hintText: 'What happened, where, who else was involved…',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Escalate immediately'),
                        subtitle: const Text(
                            'Skips the normal pending-review queue'),
                        value: _escalateNow,
                        onChanged: (v) => setState(() => _escalateNow = v),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _canSubmit ? _submit : null,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF15253F),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Submit Report'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Map<String, List<OffenseOption>> _groupByCategory(List<OffenseOption> options) {
  const order = ['Minor', 'Major_A', 'Major_B', 'Major_C', 'Major_D'];
  const labels = {
    'Minor': 'Minor Offense',
    'Major_A': 'Major Offense — Category A',
    'Major_B': 'Major Offense — Category B',
    'Major_C': 'Major Offense — Category C',
    'Major_D': 'Major Offense — Category D',
  };
  final byCategory = <String, List<OffenseOption>>{};
  for (final option in options) {
    final category = option.category ?? 'Minor';
    byCategory.putIfAbsent(category, () => []).add(option);
  }
  return {
    for (final key in order)
      if (byCategory[key] case final items? when items.isNotEmpty)
        (labels[key] ?? key): items,
  };
}

class _StudentPicker extends StatelessWidget {
  const _StudentPicker({
    required this.selected,
    required this.controller,
    required this.results,
    required this.searching,
    required this.onChanged,
    required this.onSelect,
    required this.onClear,
  });

  final SecurityReportStudentOption? selected;
  final TextEditingController controller;
  final List<SecurityReportStudentOption> results;
  final bool searching;
  final ValueChanged<String> onChanged;
  final ValueChanged<SecurityReportStudentOption> onSelect;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final student = selected;
    if (student != null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(student.displayName,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text('${student.studentNumber} · ${student.gradeSection}'),
                ],
              ),
            ),
            TextButton(onPressed: onClear, child: const Text('Change')),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: controller,
          onChanged: onChanged,
          decoration: InputDecoration(
            labelText: 'Reporting on which student?',
            hintText: 'Search by student number',
            border: const OutlineInputBorder(),
            suffixIcon: searching
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : const Icon(Icons.search),
          ),
        ),
        if (results.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            constraints: const BoxConstraints(maxHeight: 200),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: results.length,
              itemBuilder: (context, index) {
                final r = results[index];
                return ListTile(
                  dense: true,
                  title: Text(r.displayName),
                  subtitle: Text('${r.studentNumber} · ${r.gradeSection}'),
                  onTap: () => onSelect(r),
                );
              },
            ),
          ),
      ],
    );
  }
}
