import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Suggested SMS body for a conduct-based Parent Intervention. Mirrors
/// `build_conduct_intervention_message` in `supabase/add_sms_alerts_schema.sql`
/// (what an *auto*-requested intervention sends), so a counselor who accepts
/// the suggestion sends the same text the system would have. Plain ASCII on
/// purpose — it is delivered as an SMS.
String defaultParentInterventionMessage({
  required String studentName,
  required int violationCount,
  required bool hasMajorViolation,
  int windowDays = 30,
}) {
  if (hasMajorViolation) {
    return '$studentName was reported for a major conduct violation. '
        'Please visit the Guidance Office to discuss. Thank you.';
  }
  final noun = violationCount == 1 ? 'conduct violation' : 'conduct violations';
  return '$studentName has $violationCount $noun in the last $windowDays days. '
      'Please visit the Guidance Office to discuss. Thank you.';
}

/// One SMS segment holds 160 GSM characters; longer messages are split (and
/// billed) per ~153-character segment.
const int _smsSegmentLength = 160;

/// Shows the editable-message confirmation for a Parent Intervention request.
///
/// Resolves to the message to send (the suggestion, or the counselor's
/// override), or null if cancelled. [smsWarning], when set, is shown above the
/// field — e.g. when the student has no guardian number, so the intervention
/// will reach the Parent Portal but no SMS will go out.
///
/// The dialog renders through the root navigator's overlay, outside the
/// dashboard's own theme, so [isDarkMode] (default: the calling [context]'s
/// theme) is read here and passed down explicitly.
Future<String?> showParentInterventionDialog(
  BuildContext context, {
  required String studentName,
  required String suggestedMessage,
  String? smsWarning,
  bool? isDarkMode,
}) {
  final dark = isDarkMode ?? context.isDarkMode;
  return showDialog<String>(
    context: context,
    builder: (_) => ParentInterventionDialog(
      studentName: studentName,
      suggestedMessage: suggestedMessage,
      smsWarning: smsWarning,
      isDarkMode: dark,
    ),
  );
}

/// This dialog's palette — the same near-black dark palette and light tokens
/// as the rest of the Guidance dashboard.
class _DialogColors {
  const _DialogColors(this.dark);

  final bool dark;

  Color get primaryText =>
      dark ? const Color(0xFFF5F5F5) : const Color(0xFF1E293B);
  Color get secondaryText =>
      dark ? const Color(0xFFA1A1AA) : const Color(0xFF64748B);
  Color get accent =>
      dark ? const Color(0xFFA9C6FD) : const Color(0xFF345892);
  Color get noticeFill =>
      dark ? const Color(0x33F59E0B) : const Color(0xFFFEF3C7);
  Color get noticeText =>
      dark ? const Color(0xFFFCD34D) : const Color(0xFFB45309);
}

class ParentInterventionDialog extends StatefulWidget {
  const ParentInterventionDialog({
    super.key,
    required this.studentName,
    required this.suggestedMessage,
    this.smsWarning,
    this.isDarkMode = false,
  });

  final String studentName;
  final String suggestedMessage;
  final String? smsWarning;
  final bool isDarkMode;

  @override
  State<ParentInterventionDialog> createState() =>
      _ParentInterventionDialogState();
}

class _ParentInterventionDialogState extends State<ParentInterventionDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.suggestedMessage);

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _message => _controller.text.trim();
  bool get _edited => _message != widget.suggestedMessage.trim();

  @override
  Widget build(BuildContext context) {
    final c = _DialogColors(widget.isDarkMode);
    final length = _message.length;
    final segments = length == 0 ? 0 : (length / _smsSegmentLength).ceil();

    return BentoFormDialog(
      title: 'Request Parent Intervention',
      width: 460,
      isDarkMode: widget.isDarkMode,
      cancelLabel: 'Cancel',
      cancelKey: const Key('parent-intervention-cancel'),
      onCancel: () => Navigator.of(context).pop(),
      confirmLabel: 'Send',
      confirmKey: const Key('parent-intervention-send'),
      confirmEnabled: _message.isNotEmpty,
      onConfirm: () => Navigator.of(context).pop(_message),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "This sends an SMS to ${widget.studentName}'s guardian and "
            'adds a message to the Parent Portal. You can edit the text '
            'first.',
            style: GoogleFonts.poppins(
              fontSize: 12,
              height: 1.5,
              color: c.secondaryText,
            ),
          ),
          if (widget.smsWarning != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: c.noticeFill,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded,
                      size: 18, color: c.noticeText),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.smsWarning!,
                      key: const Key('parent-intervention-sms-warning'),
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        height: 1.4,
                        color: c.noticeText,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          Text(
            'Message to parent / guardian',
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: c.primaryText,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            key: const Key('parent-intervention-message'),
            controller: _controller,
            minLines: 4,
            maxLines: 8,
            style: GoogleFonts.poppins(
              fontSize: 13,
              height: 1.5,
              color: c.primaryText,
            ),
            cursorColor: c.accent,
            decoration: appPopupInputDecoration(
              context,
              isDarkMode: widget.isDarkMode,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  segments > 1
                      ? '$length characters - sent as $segments SMS segments'
                      : '$length / $_smsSegmentLength characters',
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    color: c.secondaryText,
                  ),
                ),
              ),
              if (_edited)
                InkWell(
                  key: const Key('parent-intervention-reset'),
                  borderRadius: BorderRadius.circular(6),
                  onTap: () => _controller.text = widget.suggestedMessage,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 4),
                    child: Text(
                      'Reset to suggested message',
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: c.accent,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
