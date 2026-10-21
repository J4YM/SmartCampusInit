import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_popup.dart';
import 'bento_card.dart';
import 'brightness_x.dart';

/// One guidance meeting a student or parent is invited to
/// (`guidance_meetings`, see supabase/add_guidance_investigations.sql).
class GuidanceMeetingInvite {
  const GuidanceMeetingInvite({
    required this.id,
    required this.scheduledAt,
    required this.status,
    this.location,
    this.responseNote,
  });

  final String id;
  final DateTime scheduledAt;

  /// `Proposed`, `Confirmed`, `Declined`, `Reschedule_Requested`,
  /// `Completed`, `Missed` or `Cancelled`.
  final String status;
  final String? location;
  final String? responseNote;

  /// The invitee may still answer (matches the database rule).
  bool get canRespond =>
      scheduledAt.isAfter(DateTime.now()) &&
      (status == 'Proposed' ||
          status == 'Confirmed' ||
          status == 'Declined' ||
          status == 'Reschedule_Requested');

  String get statusLabel =>
      status == 'Reschedule_Requested' ? 'Reschedule requested' : status;
}

/// Who is looking at the card; only changes the wording.
enum GuidanceMeetingAudience { student, parent }

/// The guidance counselor's meeting invitations, with Confirm / Can't attend
/// for each upcoming one. Hides itself when there are none. Read-only when
/// [onRespond] is null. A failed answer is shown and the buttons stay.
class GuidanceMeetingsCard extends StatefulWidget {
  const GuidanceMeetingsCard({
    super.key,
    required this.meetings,
    this.audience = GuidanceMeetingAudience.student,
    this.onRespond,
  });

  final List<GuidanceMeetingInvite> meetings;
  final GuidanceMeetingAudience audience;

  /// Sends the answer: confirm (`accept` true) or decline with an optional
  /// note. Throwing shows the message to the person.
  final Future<void> Function(
    GuidanceMeetingInvite meeting,
    bool accept,
    String? note,
  )? onRespond;

  @override
  State<GuidanceMeetingsCard> createState() => _GuidanceMeetingsCardState();
}

class _GuidanceMeetingsCardState extends State<GuidanceMeetingsCard> {
  String? _busyId;

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String _format(DateTime d) {
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final m = d.minute.toString().padLeft(2, '0');
    return '${_months[d.month - 1]} ${d.day}, ${d.year} · $h:$m '
        '${d.hour < 12 ? 'AM' : 'PM'}';
  }

  Future<void> _respond(
    GuidanceMeetingInvite meeting, {
    required bool accept,
  }) async {
    final onRespond = widget.onRespond;
    if (onRespond == null || _busyId != null) return;
    String? note;
    if (!accept) {
      final result = await showAppPopup<({String? note})>(
        context: context,
        builder: (_) => const _DeclineDialog(),
      );
      if (result == null || !mounted) return;
      note = result.note;
    }
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busyId = meeting.id);
    try {
      await onRespond(meeting, accept, note);
      messenger.showSnackBar(SnackBar(
        content: Text(accept
            ? 'Thank you. The counselor knows you will attend.'
            : 'Your reply was sent to the counselor.'),
      ));
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Color _statusColor(String status) => switch (status) {
        'Confirmed' || 'Completed' => const Color(0xFF2E9E6A),
        'Declined' || 'Missed' || 'Cancelled' => const Color(0xFFCD4855),
        _ => const Color(0xFFE0A100),
      };

  @override
  Widget build(BuildContext context) {
    if (widget.meetings.isEmpty) return const SizedBox.shrink();
    final dark = context.isDarkMode;
    final primary = dark ? const Color(0xFFF5F5F5) : const Color(0xFF1E293B);
    final secondary = dark ? const Color(0xFFA1A1AA) : const Color(0xFF64748B);
    final parent = widget.audience == GuidanceMeetingAudience.parent;
    final sorted = [...widget.meetings]
      ..sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt));

    return BentoCard(
      backgroundColor: dark ? const Color(0xFF191A1F) : Colors.white,
      borderColor: dark ? const Color(0xFF22242B) : const Color(0x0D000000),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Guidance Meetings',
            style: GoogleFonts.poppins(
                fontSize: 15, fontWeight: FontWeight.w600, color: primary),
          ),
          const SizedBox(height: 4),
          Text(
            parent
                ? 'The Guidance Office invited you to meet about your child.'
                : 'The Guidance Office invited you to a meeting.',
            style: GoogleFonts.poppins(fontSize: 12, color: secondary),
          ),
          const SizedBox(height: 12),
          for (final m in sorted)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: dark ? const Color(0xFF0E0E0E) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _format(m.scheduledAt),
                          style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: primary),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _statusColor(m.status).withOpacity(0.14),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          m.statusLabel,
                          style: GoogleFonts.poppins(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: _statusColor(m.status)),
                        ),
                      ),
                    ],
                  ),
                  if ((m.location ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text('At ${m.location}',
                          style: GoogleFonts.poppins(
                              fontSize: 12, color: secondary)),
                    ),
                  if ((m.responseNote ?? '').trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text('Your note: ${m.responseNote}',
                          style: GoogleFonts.poppins(
                              fontSize: 12, color: secondary)),
                    ),
                  if (widget.onRespond != null && m.canRespond) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (m.status != 'Confirmed')
                          FilledButton(
                            key: Key('meeting-confirm-${m.id}'),
                            onPressed: _busyId == null
                                ? () => _respond(m, accept: true)
                                : null,
                            child: Text(m.status == 'Declined'
                                ? 'Confirm instead'
                                : 'Confirm'),
                          ),
                        if (m.status != 'Declined')
                          OutlinedButton(
                            key: Key('meeting-decline-${m.id}'),
                            onPressed: _busyId == null
                                ? () => _respond(m, accept: false)
                                : null,
                            child: const Text("Can't attend"),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _DeclineDialog extends StatefulWidget {
  const _DeclineDialog();

  @override
  State<_DeclineDialog> createState() => _DeclineDialogState();
}

class _DeclineDialogState extends State<_DeclineDialog> {
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppPopup(
      title: "Can't attend",
      subtitle: 'Let the counselor know, and suggest another time if you can.',
      width: 480,
      actions: [
        AppPopupSecondaryButton(
          label: 'Back',
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppPopupPrimaryButton(
          key: const Key('meeting-decline-send'),
          label: 'Send reply',
          onPressed: () {
            final text = _note.text.trim();
            Navigator.of(context).pop((note: text.isEmpty ? null : text));
          },
        ),
      ],
      body: AppPopupTextField(
        label: 'Note (optional)',
        fieldKey: const Key('meeting-note'),
        controller: _note,
        minLines: 3,
        maxLines: 5,
        hint: 'e.g. I am out of town. Can we do Friday?',
      ),
    );
  }
}
