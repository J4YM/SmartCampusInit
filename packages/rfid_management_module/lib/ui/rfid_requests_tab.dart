import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'it_technician_dashboard_page.dart' show ItTechnicianColors;

class RfidRequestRowModel {
  const RfidRequestRowModel({
    required this.id,
    required this.studentId,
    required this.studentName,
    required this.studentNumber,
    required this.section,
    required this.requestedByLabel,
    required this.requestedAtLabel,
    required this.isFulfilled,
  });

  final String id;

  /// `students.id` — needed by [RfidRequestsTab.onAssign] to actually
  /// attach a card to this student.
  final String studentId;

  final String studentName;
  final String studentNumber;
  final String section;
  final String requestedByLabel;
  final String requestedAtLabel;
  final bool isFulfilled;
}

/// Queue of Registrar's "students need RFID" requests. Each pending row
/// has its own "Assign" action — the whole point of this tab existing:
/// IT Technician supplies a card UID right here instead of having to find
/// the same student again in Student Records. A request clears itself
/// (badge flips to Fulfilled) once that assignment succeeds.
class RfidRequestsTab extends StatelessWidget {
  const RfidRequestsTab({super.key, required this.requests, this.onAssign});

  final List<RfidRequestRowModel> requests;

  /// Attaches [String rfidUid] to the student behind [String requestId]/
  /// [String studentId] and marks the request fulfilled. Rethrows on
  /// failure so the row can show the error inline. Null (the default)
  /// leaves every row's Assign button inert — matches this package's
  /// other "host wires the real backend" callbacks.
  final Future<void> Function(String requestId, String studentId, String rfidUid)?
      onAssign;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: BentoCard(
        backgroundColor: ItTechnicianColors.card(context),
        borderColor: ItTechnicianColors.cardBorder(context),
        padding: const EdgeInsets.all(20),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'RFID Requests',
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: ItTechnicianColors.rowText(context),
            ),
          ),
          const SizedBox(height: 16),
          if (requests.isEmpty)
            Text(
              'No RFID requests yet.',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: ItTechnicianColors.mutedText(context),
              ),
            )
          else
            for (final request in requests)
              _RfidRequestRow(request: request, onAssign: onAssign),
        ],
        ),
      ),
    );
  }
}

class _RfidRequestRow extends StatefulWidget {
  const _RfidRequestRow({required this.request, this.onAssign});

  final RfidRequestRowModel request;
  final Future<void> Function(String requestId, String studentId, String rfidUid)?
      onAssign;

  @override
  State<_RfidRequestRow> createState() => _RfidRequestRowState();
}

class _RfidRequestRowState extends State<_RfidRequestRow> {
  bool _assigning = false;

  Future<void> _handleAssign() async {
    final onAssign = widget.onAssign;
    if (onAssign == null) return;
    final uid = await _showAssignRfidDialog(context);
    if (uid == null || !mounted) return;

    setState(() => _assigning = true);
    try {
      await onAssign(widget.request.id, widget.request.studentId, uid);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not assign card: $e')));
      }
    } finally {
      if (mounted) setState(() => _assigning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${request.studentName} — ${request.studentNumber}',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: ItTechnicianColors.rowText(context),
                  ),
                ),
                Text(
                  '${request.section} · Requested by ${request.requestedByLabel} on ${request.requestedAtLabel}',
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    color: ItTechnicianColors.mutedText(context),
                  ),
                ),
              ],
            ),
          ),
          if (!request.isFulfilled && widget.onAssign != null) ...[
            if (_assigning)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              TextButton(
                onPressed: _handleAssign,
                style: TextButton.styleFrom(
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                ),
                child: Text(
                  'Assign',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: ItTechnicianColors.azureBlue,
                  ),
                ),
              ),
            const SizedBox(width: 8),
          ],
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: request.isFulfilled
                  ? const Color(0x33137333)
                  : const Color(0x33CD4855),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              request.isFulfilled ? 'Fulfilled' : 'Pending',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: request.isFulfilled
                    ? ItTechnicianColors.successGreen
                    : ItTechnicianColors.dangerRed,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Prompts for a card UID (scanned via hardware reader or typed), returning
/// it trimmed, or null if cancelled/left blank.
Future<String?> _showAssignRfidDialog(BuildContext context) async {
  final uid = await showDialog<String>(
    context: context,
    builder: (_) => const _AssignRfidDialogContent(),
  );
  return (uid == null || uid.isEmpty) ? null : uid;
}

/// Owns its own [TextEditingController] and disposes it in this widget's
/// own `dispose()` — tied to the framework's real removal of this widget
/// (after the dialog route's exit transition finishes), rather than a
/// bare controller disposed by the caller the instant `showDialog`'s
/// Future resolves. That would race the exit animation, which still
/// reads the same controller-bound TextField for a few more frames.
class _AssignRfidDialogContent extends StatefulWidget {
  const _AssignRfidDialogContent();

  @override
  State<_AssignRfidDialogContent> createState() =>
      _AssignRfidDialogContentState();
}

class _AssignRfidDialogContentState extends State<_AssignRfidDialogContent> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BentoFormDialog(
      title: 'Assign RFID Card',
      content: TextField(
        controller: _controller,
        autofocus: true,
        style: GoogleFonts.inter(fontSize: 13),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: ItTechnicianColors.fieldFill(context),
          hintText: 'Scan or type the card UID',
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      backgroundColor: ItTechnicianColors.card(context),
      borderColor: ItTechnicianColors.cardBorder(context),
      titleColor: ItTechnicianColors.rowText(context),
      cancelFillColor: ItTechnicianColors.fieldFill(context),
      confirmColor: ItTechnicianColors.azureBlue,
      cancelLabel: 'Cancel',
      onCancel: () => Navigator.of(context).pop(),
      confirmLabel: 'Assign',
      onConfirm: () => Navigator.of(context).pop(_controller.text.trim()),
    );
  }
}
