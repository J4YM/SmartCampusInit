import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_popup.dart';

/// Opens [MailboxDetailDialog] as a Material dialog — the full, untruncated
/// view of a notification or email row tapped from either the header
/// popover or the full "View All" list page.
Future<void> showMailboxDetailDialog(
  BuildContext context, {
  required String kicker,
  String? from,
  required String subject,
  required String body,
  required DateTime timestamp,
  bool isDarkMode = false,
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
    ),
  );
}

/// Read-only detail view for a [showMailboxDetailDialog] call — same
/// popup as every other dialog in this app: [AppPopup] with the subject as its
/// title, the message in a sunken well, and a Close button.
class MailboxDetailDialog extends StatelessWidget {
  const MailboxDetailDialog({
    super.key,
    required this.kicker,
    this.from,
    required this.subject,
    required this.body,
    required this.timestamp,
    this.isDarkMode = false,
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
    final hour12 = timestamp.hour % 12 == 0 ? 12 : timestamp.hour % 12;
    final minute = timestamp.minute.toString().padLeft(2, '0');
    final period = timestamp.hour < 12 ? 'AM' : 'PM';
    return '${months[timestamp.month - 1]} ${timestamp.day}, ${timestamp.year} '
        '· $hour12:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    final c = AppPopupColors(isDarkMode);
    return AppPopup(
      title: subject,
      subtitle: [
        kicker.toUpperCase(),
        if (from != null) 'From: $from',
      ].join('  ·  '),
      isDarkMode: isDarkMode,
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
              body,
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
        ],
      ),
      actions: [
        AppPopupSecondaryButton(
          label: 'Close',
          isDarkMode: isDarkMode,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
