import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/student_risk_snapshot.dart';
import '../theme/student_portal_colors.dart';
import '../theme/student_portal_spacing.dart';
import 'portal_surface_card.dart';

/// "My Risk Factor" — the student's own latest saved risk assessment
/// (level, probability, contributing factors, suggested next steps).
/// Read-only; [snapshot] null means no assessment has been run for them yet.
class RiskFactorCard extends StatelessWidget {
  const RiskFactorCard({super.key, required this.snapshot});

  final StudentRiskSnapshot? snapshot;

  static Color _levelColor(String level) => switch (level.toLowerCase()) {
        'critical' => const Color(0xFFB91C1C),
        'high' => const Color(0xFFEA580C),
        'medium' => const Color(0xFFD97706),
        _ => const Color(0xFF15803D),
      };

  @override
  Widget build(BuildContext context) {
    final s = snapshot;
    final primary = StudentPortalColors.textPrimary(context);
    final secondary = StudentPortalColors.textSecondary(context);

    Widget bullets(String heading, List<String> items) => Padding(
          padding: const EdgeInsets.only(top: StudentPortalSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(heading,
                  style: GoogleFonts.poppins(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: primary)),
              const SizedBox(height: 4),
              for (final item in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text('• $item',
                      style:
                          GoogleFonts.poppins(fontSize: 12.5, color: secondary)),
                ),
            ],
          ),
        );

    return PortalSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('My Risk Factor',
              style: GoogleFonts.poppins(
                  fontSize: 15, fontWeight: FontWeight.w700, color: primary)),
          const SizedBox(height: StudentPortalSpacing.md),
          if (s == null)
            Text(
              'No risk assessment has been recorded for you yet.',
              style: GoogleFonts.poppins(fontSize: 12.5, color: secondary),
            )
          else ...[
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _levelColor(s.riskLevel).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    '${s.riskLevel} risk',
                    style: GoogleFonts.poppins(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: _levelColor(s.riskLevel)),
                  ),
                ),
                const SizedBox(width: StudentPortalSpacing.md),
                Text(
                  '${(s.dropoutProbability * 100).round()}% estimated',
                  style: GoogleFonts.poppins(fontSize: 12.5, color: secondary),
                ),
              ],
            ),
            if (s.keyFactors.isNotEmpty)
              bullets('Contributing factors', s.keyFactors)
            else if (s.riskReasoning != null && s.riskReasoning!.isNotEmpty)
              bullets('Why', [s.riskReasoning!]),
            if (s.recommendations.isNotEmpty)
              bullets('Suggested next steps', s.recommendations),
            const SizedBox(height: StudentPortalSpacing.md),
            Text(
              'Last assessed ${s.computedAt.year}-'
              '${s.computedAt.month.toString().padLeft(2, '0')}-'
              '${s.computedAt.day.toString().padLeft(2, '0')}. '
              'Talk to the Guidance Office if you have questions.',
              style: GoogleFonts.poppins(fontSize: 11.5, color: secondary),
            ),
          ],
        ],
      ),
    );
  }
}
