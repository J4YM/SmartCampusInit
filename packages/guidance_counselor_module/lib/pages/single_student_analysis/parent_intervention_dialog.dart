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
Future<String?> showParentInterventionDialog(
  BuildContext context, {
  required String studentName,
  required String suggestedMessage,
  String? smsWarning,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => ParentInterventionDialog(
      studentName: studentName,
      suggestedMessage: suggestedMessage,
      smsWarning: smsWarning,
    ),
  );
}

class ParentInterventionDialog extends StatefulWidget {
  const ParentInterventionDialog({
    super.key,
    required this.studentName,
    required this.suggestedMessage,
    this.smsWarning,
  });

  final String studentName;
  final String suggestedMessage;
  final String? smsWarning;

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
    final length = _message.length;
    final segments = length == 0 ? 0 : (length / _smsSegmentLength).ceil();

    return AlertDialog(
      title: Text(
        'Request Parent Intervention',
        style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600),
      ),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "This sends an SMS to ${widget.studentName}'s guardian and adds "
                "a message to the Parent Portal. You can edit the text first.",
                style: GoogleFonts.poppins(fontSize: 12),
              ),
              if (widget.smsWarning != null) ...[
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        size: 18, color: Color(0xFFB45309)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.smsWarning!,
                        key: const Key('parent-intervention-sms-warning'),
                        style: GoogleFonts.poppins(
                            fontSize: 12, color: const Color(0xFFB45309)),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              TextField(
                key: const Key('parent-intervention-message'),
                controller: _controller,
                minLines: 4,
                maxLines: 8,
                decoration: const InputDecoration(
                  labelText: 'Message to parent / guardian',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                segments > 1
                    ? '$length characters - sent as $segments SMS segments'
                    : '$length / $_smsSegmentLength characters',
                style: GoogleFonts.poppins(fontSize: 11),
              ),
              if (_edited)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    key: const Key('parent-intervention-reset'),
                    onPressed: () => _controller.text = widget.suggestedMessage,
                    child: const Text('Reset to suggested message'),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('parent-intervention-send'),
          onPressed:
              _message.isEmpty ? null : () => Navigator.of(context).pop(_message),
          child: const Text('Send'),
        ),
      ],
    );
  }
}
