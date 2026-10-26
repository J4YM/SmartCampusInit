import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_popup.dart';

/// Null when [when] is acceptable for a meeting; otherwise the message.
String? validateMeetingTime(DateTime when, {DateTime? now}) =>
    when.isAfter(now ?? DateTime.now()) ? null : 'Choose a time in the future.';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

// ---------------------------------------------------------------------------
// Dialogs
// ---------------------------------------------------------------------------

/// What the schedule dialog hands back.
class MeetingFormResult {
  const MeetingFormResult({
    required this.scheduledAt,
    required this.invitee,
    this.location,
  });

  final DateTime scheduledAt;

  /// `student`, `parent` or `both`.
  final String invitee;
  final String? location;
}

/// Pick when, where and who to invite. Defaults to tomorrow 9:00 AM with both
/// student and parent invited.
class ScheduleMeetingDialog extends StatefulWidget {
  const ScheduleMeetingDialog({super.key});

  @override
  State<ScheduleMeetingDialog> createState() => _ScheduleMeetingDialogState();
}

class _ScheduleMeetingDialogState extends State<ScheduleMeetingDialog> {
  late DateTime _when = () {
    final t = DateTime.now().add(const Duration(days: 1));
    return DateTime(t.year, t.month, t.day, 9);
  }();
  final _location = TextEditingController();
  String _invitee = 'both';

  @override
  void dispose() {
    _location.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _when.isBefore(now) ? now : _when,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 180)),
    );
    if (picked == null || !mounted) return;
    setState(() => _when =
        DateTime(picked.year, picked.month, picked.day, _when.hour, _when.minute));
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_when),
    );
    if (picked == null || !mounted) return;
    setState(() => _when =
        DateTime(_when.year, _when.month, _when.day, picked.hour, picked.minute));
  }

  @override
  Widget build(BuildContext context) {
    final c = AppPopupColors.of(context);
    final error = validateMeetingTime(_when);
    final style = appPopupFieldStyle(context);

    // A field-styled button that opens a picker; the label above it comes from
    // the AppPopupFormCell around it.
    Widget pickerField(Key key, IconData icon, String text, VoidCallback onTap) =>
        Material(
          color: c.fieldFill,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            key: key,
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(children: [
                Icon(icon, size: 18, color: c.muted),
                const SizedBox(width: 10),
                Expanded(child: Text(text, style: style)),
              ]),
            ),
          ),
        );

    return AppPopup(
      title: 'Schedule Meeting',
      subtitle: 'The invitee confirms or declines in their own dashboard.',
      width: 520,
      actions: [
        AppPopupSecondaryButton(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppPopupPrimaryButton(
          key: const Key('meeting-save'),
          label: 'Send invitation',
          onPressed: error != null
              ? null
              : () => Navigator.of(context).pop(MeetingFormResult(
                    scheduledAt: _when,
                    invitee: _invitee,
                    location: _location.text.trim().isEmpty
                        ? null
                        : _location.text.trim(),
                  )),
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const AppPopupSection('When', icon: Icons.event_outlined),
          AppPopupFormRow(
            children: [
              AppPopupFormCell(
                label: 'Date',
                flex: 3,
                child: pickerField(const Key('meeting-date'),
                    Icons.calendar_today_outlined, _formatDate(_when), _pickDate),
              ),
              AppPopupFormCell(
                label: 'Time',
                flex: 2,
                child: pickerField(const Key('meeting-time'),
                    Icons.schedule_rounded, _formatTime(_when), _pickTime),
              ),
            ],
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(error,
                  key: const Key('meeting-time-error'),
                  style: GoogleFonts.poppins(
                      fontSize: 11.5, color: AppPopupColors.danger)),
            ),
          AppPopupTextField(
            label: 'Where (optional)',
            fieldKey: const Key('meeting-location'),
            controller: _location,
            hint: 'e.g. Guidance Office',
          ),
          const SizedBox(height: 14),
          const AppPopupSection('Who is invited',
              icon: Icons.people_outline_rounded),
          AppPopupDropdown<String>(
            key: const Key('meeting-invitee'),
            label: 'Invite',
            value: _invitee,
            items: const [
              DropdownMenuItem(value: 'student', child: Text('Student')),
              DropdownMenuItem(value: 'parent', child: Text('Parent')),
              DropdownMenuItem(value: 'both', child: Text('Student & parent')),
            ],
            onChanged: (v) => setState(() => _invitee = v ?? _invitee),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime d) => '${_months[d.month - 1]} ${d.day}, ${d.year}';

  String _formatTime(DateTime d) {
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return '$h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'AM' : 'PM'}';
  }
}

