import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/sanction_history_item.dart';
import '../../theme/discipline_officer_colors.dart';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _date(DateTime d) => '${_months[d.month - 1]} ${d.day}, ${d.year}';

/// Opens [SanctionHistoryDialog] over the current page.
///
/// [onSetStatus] lets the officer move a sanction between Pending, Serving
/// and Completed; [onPrintNotice] opens the printable parent acknowledgment
/// notice for a sanction. Either is left null to hide its control.
Future<void> showSanctionHistory(
  BuildContext context, {
  required String studentName,
  required List<SanctionHistoryItem> items,
  Future<void> Function(SanctionHistoryItem item, String status)? onSetStatus,
  Future<void> Function(SanctionHistoryItem item)? onPrintNotice,
}) =>
    showAppPopup<void>(
      context: context,
      builder: (_) => SanctionHistoryDialog(
        studentName: studentName,
        items: items,
        onSetStatus: onSetStatus,
        onPrintNotice: onPrintNotice,
      ),
    );

/// Every sanction on one student's record, newest first, with the basis, the
/// override reason, its tracking status and, for a suspension, its dates.
class SanctionHistoryDialog extends StatefulWidget {
  const SanctionHistoryDialog({
    super.key,
    required this.studentName,
    required this.items,
    this.onSetStatus,
    this.onPrintNotice,
  });

  final String studentName;
  final List<SanctionHistoryItem> items;
  final Future<void> Function(SanctionHistoryItem item, String status)?
      onSetStatus;
  final Future<void> Function(SanctionHistoryItem item)? onPrintNotice;

  @override
  State<SanctionHistoryDialog> createState() => _SanctionHistoryDialogState();
}

class _SanctionHistoryDialogState extends State<SanctionHistoryDialog> {
  late List<SanctionHistoryItem> _items = [...widget.items];
  String? _busyId;

  Future<void> _setStatus(SanctionHistoryItem item, String status) async {
    final onSetStatus = widget.onSetStatus;
    if (onSetStatus == null || _busyId != null) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _busyId = item.id);
    try {
      await onSetStatus(item, status);
      if (!mounted) return;
      setState(() {
        _items = [
          for (final i in _items) i.id == item.id ? i.withStatus(status) : i,
        ];
      });
    } catch (e) {
      messenger?.showSnackBar(
          SnackBar(content: Text('Could not update the sanction: $e')));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'Completed':
        return const Color(0xFF2E9E6A);
      case 'Serving':
        return const Color(0xFFE08A00);
      default:
        return const Color(0xFF64748B);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sorted = [..._items]
      ..sort((a, b) => b.effectiveOn.compareTo(a.effectiveOn));
    final body = DisciplineOfficerColors.rowText(context);
    final muted = DisciplineOfficerColors.mutedText(context);
    final ongoing = [for (final s in sorted) if (s.isOngoingSuspension) s];

    return AppPopup(
      title: 'Sanction history',
      subtitle: widget.studentName,
      width: 520,
      actions: [
        AppPopupSecondaryButton(
          label: 'Close',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
      body: sorted.isEmpty
          ? Text('No sanctions on record.',
              style: GoogleFonts.poppins(fontSize: 13, color: muted))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final s in ongoing)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Container(
                      key: const Key('ongoing-suspension-banner'),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0x1AE08A00),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        'Ongoing suspension: ${_date(s.effectiveOn)}'
                        '${s.endsOn == null ? '' : ' – ${_date(s.endsOn!)}'}',
                        style: GoogleFonts.poppins(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: body),
                      ),
                    ),
                  ),
                for (final s in sorted)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(s.typeLabel,
                                  style: GoogleFonts.poppins(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w600,
                                      color: body)),
                            ),
                            Container(
                              key: Key('sanction-status-${s.id}'),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color:
                                    _statusColor(s.status).withOpacity(0.14),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(s.status,
                                  style: GoogleFonts.poppins(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: _statusColor(s.status))),
                            ),
                          ],
                        ),
                        Text(s.description,
                            style: GoogleFonts.poppins(
                                fontSize: 12.5, color: body)),
                        Text(
                          '${_date(s.effectiveOn)}'
                          '${s.endsOn == null ? ' · Open-ended' : ' – ${_date(s.endsOn!)}'}'
                          ' · ${s.basisLabel}'
                          '${s.affectsEnrollment ? ' · Affects enrollment' : ''}',
                          style: GoogleFonts.poppins(
                              fontSize: 11.5, color: muted),
                        ),
                        if ((s.overrideReason ?? '').isNotEmpty)
                          Text('Override reason: ${s.overrideReason}',
                              style: GoogleFonts.poppins(
                                  fontSize: 11.5, color: muted)),
                        if (s.parentAckAt != null)
                          Text('Parent acknowledged ${_date(s.parentAckAt!)}',
                              style: GoogleFonts.poppins(
                                  fontSize: 11.5, color: muted)),
                        if (widget.onSetStatus != null ||
                            widget.onPrintNotice != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                if (widget.onSetStatus != null &&
                                    s.status == 'Pending')
                                  OutlinedButton(
                                    key: Key('sanction-serving-${s.id}'),
                                    onPressed: _busyId == null
                                        ? () => _setStatus(s, 'Serving')
                                        : null,
                                    child: const Text('Mark serving'),
                                  ),
                                if (widget.onSetStatus != null &&
                                    s.status != 'Completed')
                                  OutlinedButton(
                                    key: Key('sanction-complete-${s.id}'),
                                    onPressed: _busyId == null
                                        ? () => _setStatus(s, 'Completed')
                                        : null,
                                    child: const Text('Mark completed'),
                                  ),
                                if (widget.onPrintNotice != null)
                                  OutlinedButton.icon(
                                    key: Key('sanction-notice-${s.id}'),
                                    onPressed: () => widget.onPrintNotice!(s),
                                    icon: const Icon(Icons.print_rounded,
                                        size: 16),
                                    label: const Text('Parent notice'),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}
