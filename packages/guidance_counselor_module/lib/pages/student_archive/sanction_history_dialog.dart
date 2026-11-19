import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../shared/guidance_tab_chrome.dart';
import 'sanction_history_item.dart';

export 'sanction_history_item.dart';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _date(DateTime d) => '${_months[d.month - 1]} ${d.day}, ${d.year}';

/// Opens [SanctionHistoryDialog] over the current page.
Future<void> showSanctionHistory(
  BuildContext context, {
  required String studentName,
  required List<SanctionHistoryItem> items,
}) =>
    showAppPopup<void>(
      context: context,
      builder: (_) =>
          SanctionHistoryDialog(studentName: studentName, items: items),
    );

/// Every sanction on one student's record, newest first, with the basis and
/// the override reason.
class SanctionHistoryDialog extends StatelessWidget {
  const SanctionHistoryDialog({
    super.key,
    required this.studentName,
    required this.items,
  });

  final String studentName;
  final List<SanctionHistoryItem> items;

  @override
  Widget build(BuildContext context) {
    final sorted = [...items]
      ..sort((a, b) => b.effectiveOn.compareTo(a.effectiveOn));
    final body = GuidanceTabColors.primaryText(context);
    final muted = GuidanceTabColors.secondaryText(context);

    return AppPopup(
      title: 'Sanction history',
      subtitle: studentName,
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
                for (final s in sorted)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.typeLabel,
                            style: GoogleFonts.poppins(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: body)),
                        Text(s.description,
                            style: GoogleFonts.poppins(
                                fontSize: 12.5, color: body)),
                        Text(
                          '${_date(s.effectiveOn)}'
                          '${s.endsOn == null ? ' · Open-ended' : ' – ${_date(s.endsOn!)}'}'
                          '${s.basisLabel.isEmpty ? '' : ' · ${s.basisLabel}'}'
                          '${s.affectsEnrollment ? ' · Affects enrollment' : ''}',
                          style: GoogleFonts.poppins(
                              fontSize: 11.5, color: muted),
                        ),
                        if ((s.overrideReason ?? '').isNotEmpty)
                          Text('Override reason: ${s.overrideReason}',
                              style: GoogleFonts.poppins(
                                  fontSize: 11.5, color: muted)),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}
