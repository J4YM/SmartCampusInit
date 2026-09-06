import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/violation_models.dart';
import '../theme/student_portal_colors.dart';
import '../theme/student_portal_spacing.dart';
import 'portal_surface_card.dart';
import 'section_header.dart';
import 'violation_row.dart';

/// Dashboard tile previewing the most recent violations — full history
/// lives behind "View all".
class ViolationsPreviewCard extends StatelessWidget {
  const ViolationsPreviewCard({
    super.key,
    required this.violations,
    required this.onSeeAll,
    required this.onOpenViolation,
    this.previewCount = 3,
  });

  final List<StudentViolationModel> violations;
  final VoidCallback onSeeAll;
  final ValueChanged<StudentViolationModel> onOpenViolation;
  final int previewCount;

  @override
  Widget build(BuildContext context) {
    final preview = violations.take(previewCount).toList();

    return PortalSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: 'Violations & Offenses',
            onSeeAll: violations.isEmpty ? null : onSeeAll,
          ),
          if (preview.isEmpty)
            Padding(
              padding:
                  const EdgeInsets.symmetric(vertical: StudentPortalSpacing.lg),
              child: Row(
                children: [
                  Icon(Icons.verified_outlined,
                      size: 20, color: StudentPortalColors.presentFg(context)),
                  const SizedBox(width: StudentPortalSpacing.sm),
                  Expanded(
                    child: Text(
                      'No violations on file. Keep it up!',
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        color: StudentPortalColors.textSecondary(context),
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            for (final v in preview)
              ViolationRow(violation: v, onTap: () => onOpenViolation(v)),
        ],
      ),
    );
  }
}
