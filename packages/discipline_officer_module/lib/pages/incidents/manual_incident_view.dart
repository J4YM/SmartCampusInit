import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/discipline_officer_colors.dart';

/// A student the officer can pick in the incident form.
class IncidentStudentOption {
  const IncidentStudentOption({
    required this.id,
    required this.name,
    required this.studentNumber,
    this.section = '',
  });

  final String id;
  final String name;
  final String studentNumber;
  final String section;
}

/// A handbook offense the officer can classify the incident as.
class IncidentOffenseOption {
  const IncidentOffenseOption({
    required this.id,
    required this.label,
    this.category,
  });

  final String id;
  final String label;
  final String? category;
}

/// What the incident form hands back. [studentId] and [offenseId] are always
/// set on a submitted draft; on a [ManualIncidentView.prefill] they may be
/// empty.
class IncidentDraft {
  const IncidentDraft({
    this.studentId,
    this.offenseId,
    this.description = '',
    this.occurredAt,
    this.location,
    this.notifyParent = false,
    this.concernId,
  });

  final String? studentId;
  final String? offenseId;
  final String description;
  final DateTime? occurredAt;
  final String? location;

  /// Off unless the officer turns it on: an incident is recorded quietly.
  final bool notifyParent;

  /// Set when the incident comes from a student's concern report.
  final String? concernId;
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Student Affairs' manual incident report: record an incident or violation for
/// a specific student. Saving does not notify the parent; the officer turns on
/// "Notify parent" if they want the parent told.
class ManualIncidentView extends StatefulWidget {
  const ManualIncidentView({
    super.key,
    required this.onSubmit,
    required this.onSearchStudents,
    required this.offenses,
    this.prefill,
  });

  /// Saves the incident. Throwing shows the message on the form.
  final Future<void> Function(IncidentDraft draft) onSubmit;
  final Future<List<IncidentStudentOption>> Function(String query)
      onSearchStudents;
  final List<IncidentOffenseOption> offenses;

  /// Starting values, e.g. from a concern report.
  final IncidentDraft? prefill;

  @override
  State<ManualIncidentView> createState() => _ManualIncidentViewState();
}

class _ManualIncidentViewState extends State<ManualIncidentView> {
  final _search = TextEditingController();
  late final TextEditingController _description;
  late final TextEditingController _location;
  Timer? _debounce;

  List<IncidentStudentOption> _results = const [];
  IncidentStudentOption? _student;
  String? _offenseId;
  late DateTime _occurredAt;
  bool _notifyParent = false;
  bool _showErrors = false;
  bool _busy = false;
  String? _submitError;
  String? _saved;

  @override
  void initState() {
    super.initState();
    final p = widget.prefill;
    _description = TextEditingController(text: p?.description ?? '');
    _location = TextEditingController(text: p?.location ?? '');
    _occurredAt = p?.occurredAt ?? DateTime.now();
    _notifyParent = p?.notifyParent ?? false;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _description.dispose();
    _location.dispose();
    super.dispose();
  }

  void _onSearchChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      final query = text.trim();
      if (query.isEmpty) {
        if (mounted) setState(() => _results = const []);
        return;
      }
      try {
        final found = await widget.onSearchStudents(query);
        if (mounted) setState(() => _results = found);
      } catch (_) {
        if (mounted) setState(() => _results = const []);
      }
    });
  }

  Future<void> _pickWhen() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _occurredAt,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_occurredAt),
    );
    if (time == null || !mounted) return;
    setState(() => _occurredAt =
        DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _submit() async {
    setState(() {
      _showErrors = true;
      _submitError = null;
      _saved = null;
    });
    final student = _student;
    final offenseId = _offenseId;
    final description = _description.text.trim();
    if (student == null || offenseId == null || description.isEmpty) return;

    setState(() => _busy = true);
    try {
      await widget.onSubmit(IncidentDraft(
        studentId: student.id,
        offenseId: offenseId,
        description: description,
        occurredAt: _occurredAt,
        location: _location.text.trim().isEmpty ? null : _location.text.trim(),
        notifyParent: _notifyParent,
        concernId: widget.prefill?.concernId,
      ));
      if (!mounted) return;
      setState(() {
        _busy = false;
        _saved = 'Incident recorded for ${student.name}.';
        _showErrors = false;
        _student = null;
        _offenseId = null;
        _results = const [];
        _search.clear();
        _description.clear();
        _location.clear();
        _notifyParent = false;
        _occurredAt = DateTime.now();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _submitError = '$e';
      });
    }
  }

  String _when(DateTime d) {
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final m = d.minute.toString().padLeft(2, '0');
    return '${_months[d.month - 1]} ${d.day}, ${d.year} · $h:$m ${d.hour < 12 ? 'AM' : 'PM'}';
  }

  @override
  Widget build(BuildContext context) {
    final text = DisciplineOfficerColors.rowText(context);
    final muted = DisciplineOfficerColors.mutedText(context);
    final error = DisciplineOfficerColors.denyRed;

    Widget label(String s) => Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 6),
          child: Text(s,
              style: GoogleFonts.poppins(
                  fontSize: 12, fontWeight: FontWeight.w500, color: muted)),
        );
    Widget errorText(String s) => Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(s, style: GoogleFonts.poppins(fontSize: 11.5, color: error)),
        );

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: DisciplineOfficerColors.card(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DisciplineOfficerColors.cardBorder(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Report an incident',
              style: GoogleFonts.poppins(
                  fontSize: 16, fontWeight: FontWeight.w600, color: text)),
          const SizedBox(height: 2),
          Text(
              'Recorded quietly: the parent is only told if you turn on '
              '"Notify parent".',
              style: GoogleFonts.poppins(fontSize: 12, color: muted)),
          label('Student'),
          if (_student != null)
            Row(children: [
              Expanded(
                child: Text('${_student!.name} · ${_student!.studentNumber}',
                    style: GoogleFonts.poppins(fontSize: 13.5, color: text)),
              ),
              TextButton(
                onPressed: () => setState(() => _student = null),
                child: const Text('Change'),
              ),
            ])
          else ...[
            TextField(
              key: const Key('incident-student-search'),
              controller: _search,
              onChanged: _onSearchChanged,
              decoration: const InputDecoration(
                  hintText: 'Search by name or student number',
                  isDense: true,
                  border: OutlineInputBorder()),
            ),
            for (final s in _results)
              ListTile(
                dense: true,
                title: Text(s.name),
                subtitle: Text(
                    [s.studentNumber, s.section].where((e) => e.isNotEmpty).join(' · ')),
                onTap: () => setState(() {
                  _student = s;
                  _results = const [];
                  _search.clear();
                }),
              ),
            if (_showErrors) errorText('Choose a student.'),
          ],
          label('Offense'),
          DropdownButtonFormField<String>(
            key: const Key('incident-offense'),
            initialValue: _offenseId,
            isExpanded: true,
            decoration: const InputDecoration(
                isDense: true, border: OutlineInputBorder()),
            hint: const Text('Choose an offense'),
            items: [
              for (final o in widget.offenses)
                DropdownMenuItem(
                  value: o.id,
                  child: Text(
                      o.category == null ? o.label : '${o.label} (${o.category})',
                      overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (v) => setState(() => _offenseId = v),
          ),
          if (_showErrors && _offenseId == null) errorText('Choose an offense.'),
          label('What happened'),
          TextField(
            key: const Key('incident-description'),
            controller: _description,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
          if (_showErrors && _description.text.trim().isEmpty)
            errorText('Describe the incident.'),
          label('When and where'),
          Row(children: [
            Expanded(
              child: Text(_when(_occurredAt),
                  style: GoogleFonts.poppins(fontSize: 13, color: text)),
            ),
            TextButton(onPressed: _pickWhen, child: const Text('Change time')),
          ]),
          TextField(
            key: const Key('incident-location'),
            controller: _location,
            decoration: const InputDecoration(
                hintText: 'Place (optional)',
                isDense: true,
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            key: const Key('incident-notify'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Notify parent'),
            subtitle: const Text('Off by default. Nothing is sent unless you turn this on.'),
            value: _notifyParent,
            onChanged: (v) => setState(() => _notifyParent = v),
          ),
          if (_submitError != null) errorText(_submitError!),
          if (_saved != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_saved!,
                  style: GoogleFonts.poppins(
                      fontSize: 12.5, color: DisciplineOfficerColors.azureBlue)),
            ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              key: const Key('incident-submit'),
              onPressed: _busy ? null : _submit,
              child: Text(_busy ? 'Saving…' : 'Record incident'),
            ),
          ),
        ],
      ),
    );
  }
}
