import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/violation_models.dart';
import '../theme/parent_portal_colors.dart';
import '../theme/parent_portal_spacing.dart';
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
      backgroundColor: ParentPortalColors.pageBackground(context),
      appBar: AppBar(
        backgroundColor: ParentPortalColors.surface(context),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: ParentPortalColors.textPrimary(context),
        title: Text(
          'Violations & Offenses',
          style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: DashboardPageWrapper(
          maxWidth: ParentPortalSpacing.maxContentWidth,
          padding: EdgeInsets.symmetric(
            horizontal: ParentPortalSpacing.pageHorizontal(context),
            vertical: ParentPortalSpacing.lg,
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
                      const SizedBox(width: ParentPortalSpacing.sm),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: ParentPortalSpacing.lg),
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
                                color: ParentPortalColors.textMuted(context),
                              ),
                              const SizedBox(height: ParentPortalSpacing.sm),
                              Text(
                                'No violations match this filter.',
                                style: GoogleFonts.inter(
                                  fontSize: 12.5,
                                  color: ParentPortalColors.textSecondary(
                                      context),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    // Grouped into one card, matching the dashboard's own
                    // ViolationsPreviewCard (and every other list/queue card
                    // in the app) instead of floating rows directly on the
                    // page background.
                    : PortalSurfaceCard(
                        child: ListView(
                          children: [
                            for (final v in filtered)
                              ViolationRow(
                                violation: v,
                                onTap: () => showViolationDetailSheet(
                                  context,
                                  v,
                                  isDarkMode: context.isDarkMode,
                                ),
                              ),
                          ],
                        ),
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
          // App-wide primary CTA blue (matches every other dashboard's
          // "active" pill/button) instead of the portal's own brand accent.
          color: selected
              ? const Color(0xFF345892)
              : ParentPortalColors.surfaceMuted(context),
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
                : ParentPortalColors.textSecondary(context),
          ),
        ),
      ),
    );
  }
}
