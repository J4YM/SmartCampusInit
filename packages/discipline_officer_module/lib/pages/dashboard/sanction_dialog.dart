import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/discipline_case_model.dart';

/// What the Sanction form hands back. Plain strings that match the database
/// values (`sanctions.basis`, `sanctions.sanction_type`) so the host app can
/// pass them straight to its repository.
class SanctionFormResult {
  const SanctionFormResult({
    required this.basis,
    required this.sanctionType,
    required this.description,
    required this.affectsEnrollment,
    required this.effectiveOn,
    this.endsOn,
    this.handbookOffenseId,
    this.overrideReason,
  });

  /// `handbook` or `custom`.
  final String basis;
  final String sanctionType;
  final String description;
  final bool affectsEnrollment;
  final DateTime effectiveOn;

  /// Last day of a suspension / community service (null when open-ended).
  final DateTime? endsOn;
  final String? handbookOffenseId;

  /// Set only when the investigation is still open.
  final String? overrideReason;
}

const _sanctionTypes = <(String, String)>[
  ('warning', 'Warning'),
  ('community_service', 'Community service'),
  ('suspension', 'Suspension'),
  ('non_readmission', 'Non-readmission'),
  ('dismissal', 'Dismissal'),
  ('other', 'Other'),
];

bool _affectsEnrollment(String type) =>
    type == 'non_readmission' || type == 'dismissal';

/// The Discipline Officer records the sanction that ends a case. The text is
/// prefilled from the handbook's standard penalty; changing it makes the
/// sanction "custom". Sanctions that bar the student from re-enrolling need an
/// explicit confirmation, and a case still under investigation needs a written
/// reason to be sanctioned early.
class SanctionDialog extends StatefulWidget {
  const SanctionDialog({super.key, required this.caseItem});

  final DisciplineCaseModel caseItem;

  @override
  State<SanctionDialog> createState() => _SanctionDialogState();
}

class _SanctionDialogState extends State<SanctionDialog> {
  late final TextEditingController _description;
  final _overrideReason = TextEditingController();
  String _type = 'warning';
  bool _confirmedEnrollment = false;
  late DateTime _start;
  DateTime? _end;

  /// Suspension and community service run over a period, so they take a start
  /// and end date; a suspension must have an end date.
  bool get _hasPeriod => _type == 'suspension' || _type == 'community_service';

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  String get _handbookText => widget.caseItem.handbookPenalty?.trim() ?? '';

  @override
  void initState() {
    super.initState();
    _description = TextEditingController(text: _handbookText);
    _start = _today();
  }

  @override
  void dispose() {
    _description.dispose();
    _overrideReason.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool start}) async {
    final today = _today();
    final picked = await showDatePicker(
      context: context,
      initialDate: start ? _start : (_end ?? _start),
      firstDate: start ? today.subtract(const Duration(days: 30)) : _start,
      lastDate: today.add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        _start = picked;
        if (_end != null && _end!.isBefore(_start)) _end = _start;
      } else {
        _end = picked;
      }
    });
  }

  static String _fmt(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  bool get _needsOverride => widget.caseItem.canOverrideSanction;
  bool get _blocksEnrollment => _affectsEnrollment(_type);

  bool get _isHandbook =>
      _handbookText.isNotEmpty && _description.text.trim() == _handbookText;

  bool get _canSave =>
      _description.text.trim().isNotEmpty &&
      (!_needsOverride || _overrideReason.text.trim().isNotEmpty) &&
      (!_blocksEnrollment || _confirmedEnrollment) &&
      (_type != 'suspension' || (_end != null && !_end!.isBefore(_start)));

  void _save() {
    Navigator.of(context).pop(SanctionFormResult(
      basis: _isHandbook ? 'handbook' : 'custom',
      sanctionType: _type,
      description: _description.text.trim(),
      affectsEnrollment: _blocksEnrollment,
      effectiveOn: _start,
      endsOn: _hasPeriod ? _end : null,
      handbookOffenseId: _isHandbook ? widget.caseItem.offenseId : null,
      overrideReason: _needsOverride ? _overrideReason.text.trim() : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final c = AppPopupColors.of(context);
    final report = widget.caseItem;

    return AppPopup(
      title: 'Record Sanction',
      subtitle: '${report.studentName} · ${report.violationType}',
      width: 560,
      actions: [
        AppPopupSecondaryButton(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppPopupPrimaryButton(
          key: const Key('sanction-save'),
          label: 'Record sanction',
          onPressed: _canSave ? _save : null,
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_needsOverride) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppPopupColors.danger.withOpacity(0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'This case is still under investigation. Sanctioning it before '
                'findings are filed closes the investigation, so a reason is '
                'required. It is recorded with the sanction.',
                style: GoogleFonts.poppins(fontSize: 12, color: c.text),
              ),
            ),
            const SizedBox(height: 12),
            AppPopupTextField(
              label: 'Reason for sanctioning early',
              fieldKey: const Key('sanction-override-reason'),
              controller: _overrideReason,
              minLines: 2,
              maxLines: 3,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 14),
          ],
          const AppPopupSection('Sanction', icon: Icons.gavel_rounded),
          AppPopupDropdown<String>(
            key: const Key('sanction-type'),
            label: 'Type',
            value: _type,
            items: [
              for (final (value, label) in _sanctionTypes)
                DropdownMenuItem(value: value, child: Text(label)),
            ],
            onChanged: (v) => setState(() {
              _type = v ?? _type;
              _confirmedEnrollment = false;
            }),
          ),
          if (_hasPeriod) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('sanction-start-date'),
                    onPressed: () => _pickDate(start: true),
                    icon: const Icon(Icons.event_rounded, size: 18),
                    label: Text('Starts ${_fmt(_start)}'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('sanction-end-date'),
                    onPressed: () => _pickDate(start: false),
                    icon: const Icon(Icons.event_available_rounded, size: 18),
                    label: Text(_end == null
                        ? (_type == 'suspension' ? 'End date (required)' : 'End date')
                        : 'Ends ${_fmt(_end!)}'),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          AppPopupTextField(
            label: _handbookText.isEmpty
                ? 'Sanction (decided from the investigation)'
                : 'Sanction (handbook penalty, edit to customize)',
            fieldKey: const Key('sanction-description'),
            controller: _description,
            minLines: 3,
            maxLines: 5,
            onChanged: (_) => setState(() {}),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _isHandbook
                  ? 'Recorded as handbook-based.'
                  : 'Recorded as a custom sanction.',
              style: GoogleFonts.poppins(fontSize: 11.5, color: c.muted),
            ),
          ),
          if (_blocksEnrollment) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppPopupColors.danger.withOpacity(0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'This will block re-enrollment. The student is marked '
                '${_type == 'dismissal' ? 'dismissed' : 'not for readmission'} '
                'and the registrar cannot enroll them until an administrator '
                'lifts it.',
                style: GoogleFonts.poppins(fontSize: 12, color: c.text),
              ),
            ),
            const SizedBox(height: 8),
            AppPopupCheckboxTile(
              key: const Key('sanction-confirm-enrollment'),
              title: 'I understand this blocks the student\'s re-enrollment',
              value: _confirmedEnrollment,
              onChanged: (v) => setState(() => _confirmedEnrollment = v),
            ),
          ],
        ],
      ),
    );
  }
}
