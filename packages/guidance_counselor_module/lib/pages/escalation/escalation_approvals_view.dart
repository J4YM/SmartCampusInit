import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:discipline_officer_module/discipline_officer_module.dart'
    show EscalationReportModel, EscalationStatusBadge;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Guidance Counselor's "Escalation Approvals" tab: reports from Student
/// Affairs (and the automatic 3-violations / major-offense flag) waiting for
/// sign-off. Approving sends the parent notification by the channels the
/// officer chose (SMS and/or email); the counselor may edit the message
/// first. Rejecting needs a reason, which goes back to Student Affairs.
class EscalationApprovalsView extends StatelessWidget {
  const EscalationApprovalsView({
    super.key,
    required this.reports,
    this.onDecide,
  });

  final List<EscalationReportModel> reports;

  /// Persists the decision. [message] is the (possibly edited) parent
  /// message for an approval; [note] is the reason for a rejection / optional
  /// remark for an approval. Null hides the buttons (demo).
  final Future<void> Function(
    EscalationReportModel report, {
    required bool approve,
    String? note,
    String? message,
  })? onDecide;

  Future<void> _approve(BuildContext context, EscalationReportModel r) async {
    final theme = Theme.of(context);
    final result = await showDialog<({String message, String note})>(
      context: context,
      builder: (_) => Theme(data: theme, child: _ApproveDialog(report: r)),
    );
    if (result == null || !context.mounted) return;
    await _decide(context, r, approve: true, note: result.note, message: result.message);
  }

  Future<void> _reject(BuildContext context, EscalationReportModel r) async {
    final theme = Theme.of(context);
    final note = await showDialog<String>(
      context: context,
      builder: (_) => Theme(data: theme, child: _RejectDialog(report: r)),
    );
    if (note == null || !context.mounted) return;
    await _decide(context, r, approve: false, note: note);
  }

  Future<void> _decide(
    BuildContext context,
    EscalationReportModel r, {
    required bool approve,
    String? note,
    String? message,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await onDecide!(r, approve: approve, note: note, message: message);
      messenger.showSnackBar(SnackBar(
        content: Text(approve
            ? 'Approved. The parent is being notified.'
            : 'Report rejected.'),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not save the decision: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pending = reports.where((r) => r.isPending).toList();
    final decided = reports.where((r) => !r.isPending).toList();

    Widget section(String title, List<EscalationReportModel> items, String empty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 10, top: 6),
            child: Text(title,
                style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700)),
          ),
          if (items.isEmpty)
            Text(empty, style: GoogleFonts.poppins(fontSize: 12.5, color: Colors.grey))
          else
            for (final r in items)
              _ReportCard(
                report: r,
                onApprove: r.isPending && onDecide != null
                    ? () => _approve(context, r)
                    : null,
                onReject: r.isPending && onDecide != null
                    ? () => _reject(context, r)
                    : null,
              ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        section('Awaiting your approval', pending,
            'Nothing is waiting for approval.'),
        const SizedBox(height: 20),
        section('Decided', decided, 'No decided reports yet.'),
      ],
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.report, this.onApprove, this.onReject});

  final EscalationReportModel report;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).hintColor;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('${report.studentName} · ${report.studentNumber}',
                      style: GoogleFonts.poppins(
                          fontSize: 13.5, fontWeight: FontWeight.w600)),
                ),
                EscalationStatusBadge(report: report),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${report.isAuto ? 'Automatic flag' : 'From ${report.createdByName ?? 'Student Affairs'}'}'
              ' · ${report.violationCount} violation(s) · ${report.channelsLabel}'
              ' · ${formatDateTime12h(report.createdAt)}',
              style: GoogleFonts.poppins(fontSize: 11.5, color: muted),
            ),
            if (report.summary.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(report.summary, style: GoogleFonts.poppins(fontSize: 12.5)),
            ],
            const SizedBox(height: 8),
            Text('Message to parent:',
                style: GoogleFonts.poppins(fontSize: 11.5, color: muted)),
            Text(report.message, style: GoogleFonts.poppins(fontSize: 12.5)),
            if (report.decisionNote != null && report.decisionNote!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('Note: ${report.decisionNote}',
                  style: GoogleFonts.poppins(fontSize: 12, color: muted)),
            ],
            if (onApprove != null || onReject != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  if (onApprove != null)
                    FilledButton.icon(
                      onPressed: onApprove,
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: const Text('Approve & notify parent'),
                    ),
                  const SizedBox(width: 8),
                  if (onReject != null)
                    OutlinedButton(onPressed: onReject, child: const Text('Reject')),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ApproveDialog extends StatefulWidget {
  const _ApproveDialog({required this.report});

  final EscalationReportModel report;

  @override
  State<_ApproveDialog> createState() => _ApproveDialogState();
}

class _ApproveDialogState extends State<_ApproveDialog> {
  late final _message = TextEditingController(text: widget.report.message);
  final _note = TextEditingController();

  @override
  void dispose() {
    _message.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BentoFormDialog(
      title: 'Approve & notify parent',
      width: 440,
      cancelLabel: 'Cancel',
      onCancel: () => Navigator.of(context).pop(),
      confirmLabel: 'Approve',
      confirmEnabled: _message.text.trim().isNotEmpty,
      onConfirm: () => Navigator.of(context)
          .pop((message: _message.text.trim(), note: _note.text.trim())),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Sent by ${widget.report.channelsLabel} to the guardian of '
              '${widget.report.studentName}.'),
          const SizedBox(height: 12),
          TextField(
            controller: _message,
            maxLines: 4,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Message to the parent'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            decoration: const InputDecoration(labelText: 'Note (optional)'),
          ),
        ],
      ),
    );
  }
}

class _RejectDialog extends StatefulWidget {
  const _RejectDialog({required this.report});

  final EscalationReportModel report;

  @override
  State<_RejectDialog> createState() => _RejectDialogState();
}

class _RejectDialogState extends State<_RejectDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BentoFormDialog(
      title: 'Reject report',
      width: 420,
      cancelLabel: 'Cancel',
      onCancel: () => Navigator.of(context).pop(),
      confirmLabel: 'Reject',
      confirmEnabled: _reason.text.trim().isNotEmpty,
      onConfirm: () => Navigator.of(context).pop(_reason.text.trim()),
      content: TextField(
        controller: _reason,
        maxLines: 3,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(
          labelText: 'Reason (sent back to Student Affairs)',
        ),
      ),
    );
  }
}
