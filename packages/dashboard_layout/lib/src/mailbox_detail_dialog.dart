import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_popup.dart';

/// Opens [MailboxDetailDialog] as a Material dialog — the full, untruncated
/// view of a notification or email row tapped from either the header
/// popover or the full "View All" list page.
///
/// With [onReply] the dialog also offers a reply box (a message that came out
/// of a technical issue, where the person can answer IT right here).
Future<void> showMailboxDetailDialog(
  BuildContext context, {
  required String kicker,
  String? from,
  required String subject,
  required String body,
  required DateTime timestamp,
  bool isDarkMode = false,
  Future<void> Function(String message)? onReply,
}) {
  return showAppPopup<void>(
    context: context,
    builder: (_) => MailboxDetailDialog(
      kicker: kicker,
      from: from,
      subject: subject,
      body: body,
      timestamp: timestamp,
      isDarkMode: isDarkMode,
      onReply: onReply,
    ),
  );
}

/// Detail view for a [showMailboxDetailDialog] call — same popup as every
/// other dialog in this app: [AppPopup] with the subject as its title, the
/// message in a sunken well, and a Close button. When [onReply] is given it
/// adds a reply box and a "Send reply" button.
class MailboxDetailDialog extends StatefulWidget {
  const MailboxDetailDialog({
    super.key,
    required this.kicker,
    this.from,
    required this.subject,
    required this.body,
    required this.timestamp,
    this.isDarkMode = false,
    this.onReply,
  });

  final String kicker;
  final String? from;
  final String subject;
  final String body;
  final DateTime timestamp;

  /// Rendered through `showDialog`'s own root-navigator Overlay, which sits
  /// outside the dashboard page's local per-page Theme — so
  /// `context.isDarkMode` here would read the app's ambient theme, not the
  /// page's toggle. Threaded in explicitly instead (same pattern as
  /// `ReportTechnicalIssueDialog`).
  final bool isDarkMode;

  /// Sends a reply to this message; throws on failure. Null hides the reply
  /// box (every message that is not about a technical issue).
  final Future<void> Function(String message)? onReply;

  @override
  State<MailboxDetailDialog> createState() => _MailboxDetailDialogState();
}

class _MailboxDetailDialogState extends State<MailboxDetailDialog> {
  final _reply = TextEditingController();
  bool _sending = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  String get _formattedTimestamp {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final t = widget.timestamp;
    final hour12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final minute = t.minute.toString().padLeft(2, '0');
    final period = t.hour < 12 ? 'AM' : 'PM';
    return '${months[t.month - 1]} ${t.day}, ${t.year} '
        '· $hour12:$minute $period';
  }

  bool get _canSend => !_sending && _reply.text.trim().isNotEmpty;

  Future<void> _send() async {
    final reply = widget.onReply;
    final message = _reply.text.trim();
    if (reply == null || message.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _error = null;
      _sent = false;
    });
    try {
      await reply(message);
      if (!mounted) return;
      // Only cleared once the write really succeeded — a failed send must not
      // wipe what was typed.
      _reply.clear();
      setState(() => _sent = true);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not send the reply: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppPopupColors(widget.isDarkMode);
    final canReply = widget.onReply != null;
    return AppPopup(
      title: widget.subject,
      subtitle: [
        widget.kicker.toUpperCase(),
        if (widget.from != null) 'From: ${widget.from}',
      ].join('  ·  '),
      isDarkMode: widget.isDarkMode,
      closeEnabled: !_sending,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: c.fieldFill,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              widget.body,
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: c.text,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _formattedTimestamp,
            style: GoogleFonts.poppins(
              fontSize: 11,
              fontWeight: FontWeight.w400,
              color: c.muted,
            ),
          ),
          if (canReply) ...[
            const SizedBox(height: 18),
            AppPopupTextField(
              label: 'Reply',
              fieldKey: const Key('mailbox-reply-field'),
              controller: _reply,
              hint: 'Write a reply…',
              maxLines: 3,
              minLines: 3,
              enabled: !_sending,
              isDarkMode: widget.isDarkMode,
              onChanged: (_) => setState(() {
                _sent = false;
              }),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              AppPopupError(_error!),
            ],
            if (_sent) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.check_circle_rounded,
                      size: 16, color: AppPopupColors.accent),
                  const SizedBox(width: 6),
                  Text(
                    'Reply sent.',
                    key: const Key('mailbox-reply-sent'),
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: c.muted,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
      actions: [
        AppPopupSecondaryButton(
          label: 'Close',
          isDarkMode: widget.isDarkMode,
          onPressed: _sending ? null : () => Navigator.of(context).pop(),
        ),
        if (canReply)
          AppPopupPrimaryButton(
            key: const Key('mailbox-reply-send'),
            label: 'Send reply',
            icon: Icons.send_rounded,
            loading: _sending,
            onPressed: _canSend ? _send : null,
          ),
      ],
    );
  }
}
