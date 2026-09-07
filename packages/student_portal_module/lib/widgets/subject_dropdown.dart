import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/attendance_models.dart';
import '../theme/student_portal_colors.dart';

/// Pill-shaped subject filter — the calendar's one control, kept to a
/// single dropdown rather than a row of chips so the week card stays
/// compact.
class SubjectDropdown extends StatelessWidget {
  const SubjectDropdown({
    super.key,
    required this.subjects,
    required this.selectedSubjectId,
    required this.onChanged,
  });

  final List<SubjectModel> subjects;
  final String? selectedSubjectId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      // Was 220 — wide enough that, combined with isExpanded below, this
      // control stretched to fill nearly all of SectionHeader's remaining
      // row space and ended up sitting in the card's far top-right corner
      // instead of reading as a compact filter next to the title. isExpanded
      // has to stay true (dropping it sizes the closed button to the widest
      // *item* across the whole subject list, which can overflow the row
      // for a long subject name) — capping the width tighter is what keeps
      // this proportionate to its own "All Subjects ▾" content.
      constraints: const BoxConstraints(maxWidth: 150),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: StudentPortalColors.borderStrong(context)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String?>(
            value: selectedSubjectId,
            isDense: true,
            isExpanded: true,
            icon: Icon(
              Icons.expand_more_rounded,
              size: 18,
              color: StudentPortalColors.textSecondary(context),
            ),
            style: GoogleFonts.inter(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: StudentPortalColors.textPrimary(context),
            ),
            dropdownColor: StudentPortalColors.surface(context),
            borderRadius: BorderRadius.circular(12),
            onChanged: onChanged,
            items: [
              const DropdownMenuItem(value: null, child: Text('All Subjects')),
              for (final subject in subjects)
                DropdownMenuItem(
                  value: subject.id,
                  child: Text(subject.name, overflow: TextOverflow.ellipsis),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
