import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/schedule_models.dart';
import '../theme/student_portal_colors.dart';
import 'portal_surface_card.dart';
import 'section_header.dart';

/// A compact list of the student's active class offerings — subject,
/// professor, days, time, room. Not a calendar/timetable redesign; each
/// student typically has 4-8 entries, so a plain list fits without needing
/// pagination or a separate full-page view (unlike Violations' "See All").
class MyScheduleCard extends StatelessWidget {
  const MyScheduleCard({super.key, required this.entries});

  final List<StudentScheduleEntryModel> entries;

  @override
  Widget build(BuildContext context) {
    return PortalSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(title: 'My Schedule'),
          if (entries.isEmpty)
            Text(
              'No classes enrolled yet.',
              style: GoogleFonts.inter(
                fontSize: 12.5,
                color: StudentPortalColors.textSecondary(context),
              ),
            )
          else
            for (final entry in entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.subjectTitle,
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: StudentPortalColors.textPrimary(context),
                            ),
                          ),
                          Text(
                            entry.professorName,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: StudentPortalColors.textSecondary(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          entry.daysLabel,
                          style: GoogleFonts.inter(fontSize: 12),
                        ),
                        Text(
                          '${entry.timeLabel} · ${entry.room}',
                          style: GoogleFonts.inter(
                            fontSize: 11.5,
                            color: StudentPortalColors.textSecondary(context),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}
