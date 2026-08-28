import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Shared surface palette for [MailboxDetailDialog] — same tokens every
/// other custom dialog in this app uses (card/border/text/brand-accent).
abstract final class _MailboxDialogColors {
  static Color card(bool isDarkMode) =>
      isDarkMode ? const Color(0xFF16191D) : Colors.white;
  static Color border(bool isDarkMode) =>
      isDarkMode ? const Color(0x0D334155) : const Color(0x0DE2E8F0);
  static Color primaryText(bool isDarkMode) =>
      isDarkMode ? const Color(0xFFF1F5F9) : const Color(0xFF1E293B);
  static Color secondaryText(bool isDarkMode) =>
      isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
  static Color fieldFill(bool isDarkMode) =>
      isDarkMode ? const Color(0xFF111111) : const Color(0xFFF1F5F9);
}

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
  return showDialog<void>(
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
/// rounded-16 card shell (Poppins title + close-X header, pale/solid pill
/// actions) as every other custom dialog in this app (e.g.
/// `ReportTechnicalIssueDialog`).
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
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final hour12 = timestamp.hour % 12 == 0 ? 12 : timestamp.hour % 12;
    final minute = timestamp.minute.toString().padLeft(2, '0');
    final period = timestamp.hour < 12 ? 'AM' : 'PM';
    return '${months[timestamp.month - 1]} ${timestamp.day}, ${timestamp.year} '
        '· $hour12:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        width: 440,
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
        decoration: BoxDecoration(
          color: _MailboxDialogColors.card(isDarkMode),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _MailboxDialogColors.border(isDarkMode)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    kicker.toUpperCase(),
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.6,
                      color: _MailboxDialogColors.secondaryText(isDarkMode),
                    ),
                  ),
                ),
                InkWell(
                  onTap: () => Navigator.of(context).pop(),
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.close_rounded,
                      size: 22,
                      color: _MailboxDialogColors.primaryText(isDarkMode),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              subject,
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: _MailboxDialogColors.primaryText(isDarkMode),
              ),
            ),
            if (from != null) ...[
              const SizedBox(height: 4),
              Text(
                'From: $from',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: _MailboxDialogColors.secondaryText(isDarkMode),
                ),
              ),
            ],
            const SizedBox(height: 14),
            Flexible(
              child: SingleChildScrollView(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _MailboxDialogColors.fieldFill(isDarkMode),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    body,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      color: _MailboxDialogColors.primaryText(isDarkMode),
                      height: 1.5,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formattedTimestamp,
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                    color: _MailboxDialogColors.secondaryText(isDarkMode),
                  ),
                ),
                Material(
                  color: _MailboxDialogColors.fieldFill(isDarkMode),
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    onTap: () => Navigator.of(context).pop(),
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: Text(
                        'Close',
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _MailboxDialogColors.primaryText(isDarkMode),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
