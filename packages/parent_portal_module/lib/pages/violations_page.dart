import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/violation_models.dart';
import '../theme/parent_portal_colors.dart';
import '../theme/parent_portal_spacing.dart';
import '../widgets/folder_tabs.dart';
import '../widgets/violation_detail_sheet.dart';
import '../widgets/violation_row.dart';

/// The tabs of [ViolationsPage].
enum ViolationFilter { all, minor, major, pending, recorded }

/// Full violation history — reached from the dashboard's "View all".
class ViolationsPage extends StatefulWidget {
  const ViolationsPage({
    super.key,
    required this.violations,
    this.initialFilter = ViolationFilter.all,
  });

  final List<StudentViolationModel> violations;

  /// The tab selected on open — e.g. Pending when the dashboard's "cases still
  /// under review" banner was tapped.
  final ViolationFilter initialFilter;

  @override
  State<ViolationsPage> createState() => _ViolationsPageState();
}

class _ViolationsPageState extends State<ViolationsPage> {
  late ViolationFilter _filter = widget.initialFilter;

  static bool _matches(ViolationFilter f, StudentViolationModel v) =>
      switch (f) {
        ViolationFilter.all => true,
        ViolationFilter.minor => v.category == ViolationCategory.minor,
        ViolationFilter.major => v.category == ViolationCategory.major,
        ViolationFilter.pending => v.status == ViolationStatus.pending,
        ViolationFilter.recorded => v.status == ViolationStatus.recorded,
      };

  static String _label(ViolationFilter f) => switch (f) {
        ViolationFilter.all => 'All',
        ViolationFilter.minor => 'Minor',
        ViolationFilter.major => 'Major',
        ViolationFilter.pending => 'Pending',
        ViolationFilter.recorded => 'Recorded',
      };

  /// Shown on each tab, so the counts are visible before switching.
  int _countFor(ViolationFilter f) =>
      widget.violations.where((v) => _matches(f, v)).length;

  List<StudentViolationModel> get _filtered =>
      widget.violations.where((v) => _matches(_filter, v)).toList();

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
          child: FolderTabbedPanel(
            tabs: [
              for (final f in ViolationFilter.values)
                FolderTabSpec(_label(f), _countFor(f)),
            ],
            selectedIndex: ViolationFilter.values.indexOf(_filter),
            onSelected: (i) =>
                setState(() => _filter = ViolationFilter.values[i]),
            child: filtered.isEmpty
                ? Center(
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
                          style: GoogleFonts.poppins(
                            fontSize: 12.5,
                            color: ParentPortalColors.textSecondary(context),
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView(
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
      ),
    );
  }
}
