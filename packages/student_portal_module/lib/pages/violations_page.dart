import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/violation_models.dart';
import '../theme/student_portal_colors.dart';
import '../theme/student_portal_spacing.dart';
import '../widgets/portal_surface_card.dart';
import '../widgets/violation_detail_sheet.dart';
import '../widgets/violation_row.dart';

enum _ViolationFilter { all, minor, major, pending, recorded }

/// Full violation history — reached from the dashboard's "View all".
class ViolationsPage extends StatefulWidget {
  const ViolationsPage({super.key, required this.violations});

  final List<StudentViolationModel> violations;

  @override
  State<ViolationsPage> createState() => _ViolationsPageState();
}

class _ViolationsPageState extends State<ViolationsPage> {
  _ViolationFilter _filter = _ViolationFilter.all;

  List<StudentViolationModel> get _filtered {
    switch (_filter) {
      case _ViolationFilter.all:
        return widget.violations;
      case _ViolationFilter.minor:
        return widget.violations
            .where((v) => v.category == ViolationCategory.minor)
            .toList();
      case _ViolationFilter.major:
        return widget.violations
            .where((v) => v.category == ViolationCategory.major)
            .toList();
      case _ViolationFilter.pending:
        return widget.violations
            .where((v) => v.status == ViolationStatus.pending)
            .toList();
      case _ViolationFilter.recorded:
        return widget.violations
            .where((v) => v.status == ViolationStatus.recorded)
            .toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;

    return Scaffold(
      backgroundColor: StudentPortalColors.pageBackground(context),
      appBar: AppBar(
        backgroundColor: StudentPortalColors.surface(context),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: StudentPortalColors.textPrimary(context),
        title: Text(
          'Violations & Offenses',
          style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: DashboardPageWrapper(
          maxWidth: StudentPortalSpacing.maxContentWidth,
          padding: EdgeInsets.symmetric(
            horizontal: StudentPortalSpacing.pageHorizontal(context),
            vertical: StudentPortalSpacing.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 36,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final f in _ViolationFilter.values) ...[
                      _FilterChip(
                        label: switch (f) {
                          _ViolationFilter.all => 'All',
                          _ViolationFilter.minor => 'Minor',
                          _ViolationFilter.major => 'Major',
                          _ViolationFilter.pending => 'Pending',
                          _ViolationFilter.recorded => 'Recorded',
                        },
                        selected: _filter == f,
                        onTap: () => setState(() => _filter = f),
                      ),
                      const SizedBox(width: StudentPortalSpacing.sm),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: StudentPortalSpacing.lg),
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: PortalSurfaceCard(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.verified_outlined,
                                size: 34,
                                color: StudentPortalColors.textMuted(context),
                              ),
                              const SizedBox(height: StudentPortalSpacing.sm),
                              Text(
                                'No violations match this filter.',
                                style: GoogleFonts.inter(
                                  fontSize: 12.5,
                                  color: StudentPortalColors.textSecondary(
                                      context),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView(
                        children: [
                          for (final v in filtered)
                            ViolationRow(
                              violation: v,
                              onTap: () => showViolationDetailSheet(context, v),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? StudentPortalColors.accent(context)
              : StudentPortalColors.surfaceMuted(context),
          borderRadius: BorderRadius.circular(999),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: selected
                ? Colors.white
                : StudentPortalColors.textSecondary(context),
          ),
        ),
      ),
    );
  }
}
