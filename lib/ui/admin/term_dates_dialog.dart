import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../data/academic_term_repository.dart' show formatTermDate;

/// Null when [start] and [end] make a valid academic year; otherwise the
/// message to show.
String? validateTermDates(DateTime? start, DateTime? end) {
  if (start == null || end == null) {
    return 'Choose both the start and the end date.';
  }
  final s = DateTime(start.year, start.month, start.day);
  final e = DateTime(end.year, end.month, end.day);
  return e.isAfter(s) ? null : 'The end date must be after the start date.';
}

/// Pick when the academic year / semester begins and ends. Pops with
/// `(start:, end:)`.
class TermDatesDialog extends StatefulWidget {
  const TermDatesDialog({
    super.key,
    required this.termLabel,
    this.initialStart,
    this.initialEnd,
  });

  final String termLabel;
  final DateTime? initialStart;
  final DateTime? initialEnd;

  @override
  State<TermDatesDialog> createState() => _TermDatesDialogState();
}

class _TermDatesDialogState extends State<TermDatesDialog> {
  late DateTime? _start = widget.initialStart;
  late DateTime? _end = widget.initialEnd;

  Future<DateTime?> _pick(DateTime? current, DateTime fallback) {
    final now = DateTime.now();
    return showDatePicker(
      context: context,
      initialDate: current ?? fallback,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 5),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppPopupColors.of(context);
    // Don't nag before both are chosen; do flag a clearly wrong order.
    final error = (_start != null && _end != null)
        ? validateTermDates(_start, _end)
        : null;
    final valid = validateTermDates(_start, _end) == null;

    Widget field(Key key, String label, DateTime? value, VoidCallback onTap) =>
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppPopupFieldLabel(label),
            Material(
              color: c.fieldFill,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                key: key,
                borderRadius: BorderRadius.circular(10),
                onTap: onTap,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  child: Row(children: [
                    Icon(Icons.calendar_today_outlined, size: 18, color: c.muted),
                    const SizedBox(width: 10),
                    Text(
                      value == null ? 'Choose a date' : formatTermDate(value),
                      style: appPopupFieldStyle(context),
                    ),
                  ]),
                ),
              ),
            ),
          ],
        );

    return AppPopup(
      title: 'Academic Year Dates',
      subtitle: widget.termLabel,
      width: 480,
      actions: [
        AppPopupSecondaryButton(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppPopupPrimaryButton(
          key: const Key('term-dates-save'),
          label: 'Save dates',
          onPressed: valid
              ? () => Navigator.of(context).pop((start: _start!, end: _end!))
              : null,
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          field(const Key('term-start-date'), 'Starts on', _start, () async {
            final d = await _pick(_start, DateTime.now());
            if (d != null) setState(() => _start = d);
          }),
          const SizedBox(height: 14),
          field(const Key('term-end-date'), 'Ends on', _end, () async {
            final d = await _pick(
                _end, (_start ?? DateTime.now()).add(const Duration(days: 150)));
            if (d != null) setState(() => _end = d);
          }),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                error,
                style: GoogleFonts.poppins(
                    fontSize: 11.5, color: AppPopupColors.danger),
              ),
            ),
        ],
      ),
    );
  }
}
