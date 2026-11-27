import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/sanction_history_entry.dart';
import '../theme/student_portal_colors.dart';
import '../theme/student_portal_spacing.dart';
import 'portal_surface_card.dart';
import 'section_header.dart';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _date(DateTime d) => '${_months[d.month - 1]} ${d.day}, ${d.year}';

/// The student's sanction history. Hidden when there is nothing to show.
class SanctionHistoryCard extends StatelessWidget {
  const SanctionHistoryCard({super.key, required this.entries});

  final List<SanctionHistoryEntry> entries;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();
    return PortalSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: 'Sanction history'),
          for (var i = 0; i < entries.length; i++) ...[
            if (i > 0) const SizedBox(height: StudentPortalSpacing.md),
            _SanctionRow(entry: entries[i]),
          ],
        ],
      ),
    );
  }
}

class _SanctionRow extends StatelessWidget {
  const _SanctionRow({required this.entry});

  final SanctionHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final range = entry.endsOn == null
        ? '${_date(entry.effectiveOn)} · Open-ended'
        : '${_date(entry.effectiveOn)} – ${_date(entry.endsOn!)}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                entry.typeLabel,
                style: GoogleFonts.poppins(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: StudentPortalColors.textPrimary(context),
                ),
              ),
            ),
            if (entry.affectsEnrollment)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: StudentPortalColors.absentBg(context),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Affects enrollment',
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: StudentPortalColors.absentFg(context),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          entry.description,
          style: GoogleFonts.poppins(
            fontSize: 12.5,
            color: StudentPortalColors.textSecondary(context),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          entry.isSuspension ? 'Suspension: $range · ${entry.status}' : '$range · ${entry.status}',
          style: GoogleFonts.poppins(
            fontSize: 11.5,
            color: StudentPortalColors.textMuted(context),
          ),
        ),
      ],
    );
  }
}
