import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/discipline_case_model.dart';
import '../theme/discipline_officer_colors.dart';

/// Where a violation case stands, in the words the officer reads: waiting for
/// the officer, under investigation, investigation complete, or sanctioned.
({String label, Color color}) caseProgress(DisciplineCaseModel c) =>
    switch (c.stage) {
      CaseStage.underInvestigation => (
          label: 'Under investigation',
          color: const Color(0xFFD97706),
        ),
      CaseStage.investigationComplete => (
          label: 'Investigation complete',
          color: DisciplineOfficerColors.azureBlue,
        ),
      CaseStage.sanctioned => (
          label: 'Sanctioned',
          color: DisciplineOfficerColors.validateGreen,
        ),
      CaseStage.classified || CaseStage.reported => (
          label: 'Awaiting action',
          color: DisciplineOfficerColors.denyRed,
        ),
    };

/// The pill that shows [caseProgress].
class CaseProgressBadge extends StatelessWidget {
  const CaseProgressBadge({super.key, required this.label, required this.color});

  CaseProgressBadge.forCase(DisciplineCaseModel c, {Key? key})
      : this(
          key: key,
          label: caseProgress(c).label,
          color: caseProgress(c).color,
        );

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.poppins(
            fontSize: 11, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}
