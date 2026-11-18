import 'package:dashboard_layout/dashboard_layout.dart'
    show validateMeetingTime;
import 'package:flutter/material.dart';

import '../models/availability_request.dart';
import '../theme/parent_portal_colors.dart';
import '../theme/parent_portal_spacing.dart';
import 'portal_surface_card.dart';
import 'section_header.dart';

const int kMaxAvailabilityTimes = 10;

/// Asks the parent when they are free for a guidance meeting. Hidden when
/// there is no open request; otherwise shows the first one.
class AvailabilityRequestCard extends StatelessWidget {
  const AvailabilityRequestCard({
    super.key,
    required this.requests,
    required this.onSubmit,
  });

  final List<AvailabilityRequest> requests;
  final Future<void> Function(String roundId, List<DateTime> slots) onSubmit;

  @override
  Widget build(BuildContext context) {
    if (requests.isEmpty) return const SizedBox.shrink();
    final request = requests.first;
    return _AvailabilityForm(
      key: ValueKey(request.roundId),
      request: request,
      onSubmit: onSubmit,
    );
  }
}

class _AvailabilityForm extends StatefulWidget {
  const _AvailabilityForm({
    super.key,
    required this.request,
    required this.onSubmit,
  });

  final AvailabilityRequest request;
  final Future<void> Function(String roundId, List<DateTime> slots) onSubmit;

  @override
  State<_AvailabilityForm> createState() => _AvailabilityFormState();
}

class _Row {
  DateTime? date;
  TimeOfDay? time;
  bool get complete => date != null && time != null;
  DateTime get when =>
      DateTime(date!.year, date!.month, date!.day, time!.hour, time!.minute);
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

class _AvailabilityFormState extends State<_AvailabilityForm> {
  final List<_Row> _rows = [_Row()];
  bool _showErrors = false;
  bool _busy = false;
  String? _submitError;

  Future<void> _pickDate(_Row row) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: row.date ?? now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 180)),
    );
    if (picked == null || !mounted) return;
    setState(() => row.date = picked);
  }

  Future<void> _pickTime(_Row row) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: row.time ?? TimeOfDay.now(),
    );
    if (picked == null || !mounted) return;
    setState(() => row.time = picked);
  }

  Future<void> _submit() async {
    final complete = _rows.where((r) => r.complete).toList();
    if (complete.isEmpty) return;
    final slots = [for (final r in complete) r.when];
    if (slots.any((s) => validateMeetingTime(s) != null)) {
      setState(() => _showErrors = true);
      return;
    }
    setState(() {
      _busy = true;
      _submitError = null;
      _showErrors = false;
    });
    try {
      await widget.onSubmit(widget.request.roundId, slots);
    } catch (e) {
      if (mounted) setState(() => _submitError = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _dateText(DateTime d) => '${_months[d.month - 1]} ${d.day}, ${d.year}';

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    final first = _rows.first;
    final textColor = ParentPortalColors.textPrimary(context);
    final secondary = ParentPortalColors.textSecondary(context);
    final error = ParentPortalColors.absentFg(context);

    Widget field(Key key, IconData icon, String text, bool placeholder,
        VoidCallback onTap) {
      return Material(
        color: ParentPortalColors.surfaceMuted(context),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          key: key,
          borderRadius: BorderRadius.circular(10),
          onTap: _busy ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Icon(icon, size: 16, color: secondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    text,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13,
                        color: placeholder ? secondary : textColor),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    Widget rowWidget(int i) {
      final row = _rows[i];
      final past =
          _showErrors && row.complete && validateMeetingTime(row.when) != null;
      return Padding(
        padding: const EdgeInsets.only(bottom: ParentPortalSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: field(
                    ValueKey('availability-date-$i'),
                    Icons.calendar_today_rounded,
                    row.date == null ? 'Pick a date' : _dateText(row.date!),
                    row.date == null,
                    () => _pickDate(row),
                  ),
                ),
                const SizedBox(width: ParentPortalSpacing.sm),
                Expanded(
                  flex: 2,
                  child: field(
                    ValueKey('availability-time-$i'),
                    Icons.schedule_rounded,
                    row.time == null
                        ? 'Pick a time'
                        : row.time!.format(context),
                    row.time == null,
                    () => _pickTime(row),
                  ),
                ),
                if (i > 0)
                  IconButton(
                    key: ValueKey('availability-remove-$i'),
                    tooltip: 'Remove',
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed:
                        _busy ? null : () => setState(() => _rows.removeAt(i)),
                  ),
              ],
            ),
            if (past)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Choose a time in the future.',
                    style: TextStyle(fontSize: 12, color: error)),
              ),
          ],
        ),
      );
    }

    return PortalSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: 'Guidance needs your availability'),
          Text(
            request.studentName == null
                ? 'Please offer the times you are free for a meeting with Guidance.'
                : 'Please offer the times you are free for a meeting with Guidance about ${request.studentName}.',
            style: TextStyle(fontSize: 13, color: secondary),
          ),
          if (request.roundNo > 1) ...[
            const SizedBox(height: ParentPortalSpacing.sm),
            Text(
              'Guidance could not make the previous times. Please pick other dates.',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: ParentPortalColors.pendingFg(context)),
            ),
          ],
          const SizedBox(height: ParentPortalSpacing.md),
          for (var i = 0; i < _rows.length; i++) rowWidget(i),
          if (_rows.length < kMaxAvailabilityTimes)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed:
                    _busy ? null : () => setState(() => _rows.add(_Row())),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add another time'),
              ),
            ),
          if (_submitError != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(_submitError!,
                  style: TextStyle(fontSize: 12, color: error)),
            ),
          const SizedBox(height: ParentPortalSpacing.sm),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              key: const ValueKey('availability-submit'),
              onPressed: first.complete && !_busy ? _submit : null,
              child: Text(_busy ? 'Sending...' : 'Submit'),
            ),
          ),
        ],
      ),
    );
  }
}
