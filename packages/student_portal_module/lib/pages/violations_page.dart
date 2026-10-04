import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/violation_models.dart';
import '../theme/student_portal_colors.dart';
import '../theme/student_portal_spacing.dart';
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

  /// True once the tab strip is wider than the screen: its last visible tab
  /// then meets the panel's top-right corner, which is squared to match.
  bool _tabsOverflow = false;

  static bool _matches(_ViolationFilter f, StudentViolationModel v) =>
      switch (f) {
        _ViolationFilter.all => true,
        _ViolationFilter.minor => v.category == ViolationCategory.minor,
        _ViolationFilter.major => v.category == ViolationCategory.major,
        _ViolationFilter.pending => v.status == ViolationStatus.pending,
        _ViolationFilter.recorded => v.status == ViolationStatus.recorded,
      };

  /// Shown on each tab, so the counts are visible before switching.
  int _countFor(_ViolationFilter f) =>
      widget.violations.where((v) => _matches(f, v)).length;

  List<StudentViolationModel> get _filtered =>
      widget.violations.where((v) => _matches(_filter, v)).toList();

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
          // Folder-tab layout: the tabs sit on the panel's top edge, and the
          // active one shares the panel's surface (and covers its top
          // border) so the two read as one folder.
          child: Stack(
            children: [
              Positioned.fill(
                top: _tabHeight - 1,
                child: _FolderPanel(
                  squareTopRight: _tabsOverflow,
                  child: filtered.isEmpty
                      ? Center(
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
                                style: GoogleFonts.poppins(
                                  fontSize: 12.5,
                                  color: StudentPortalColors.textSecondary(
                                      context),
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
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: _tabHeight,
                child: HorizontalTabScroller(
                  onOverflowChanged: (v) => setState(() => _tabsOverflow = v),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final f in _ViolationFilter.values) ...[
                        _FolderTab(
                          label: switch (f) {
                            _ViolationFilter.all => 'All',
                            _ViolationFilter.minor => 'Minor',
                            _ViolationFilter.major => 'Major',
                            _ViolationFilter.pending => 'Pending',
                            _ViolationFilter.recorded => 'Recorded',
                          },
                          count: _countFor(f),
                          selected: _filter == f,
                          onTap: () => setState(() => _filter = f),
                        ),
                        if (f != _ViolationFilter.values.last)
                          const SizedBox(width: StudentPortalSpacing.xs),
                      ],
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

/// Height of the active tab (inactive ones are 6px shorter, so they look
/// tucked behind the panel).
const double _tabHeight = 44;

class _FolderPanel extends StatelessWidget {
  const _FolderPanel({required this.child, this.squareTopRight = false});

  final Widget child;

  /// True when a tab runs to the panel's right edge (the tab strip is
  /// scrolling), so a rounded corner there would be cut into the tab.
  final bool squareTopRight;

  @override
  Widget build(BuildContext context) {
    const r = Radius.circular(20);
    return Container(
      padding: const EdgeInsets.all(StudentPortalSpacing.lg),
      decoration: BoxDecoration(
        color: StudentPortalColors.surface(context),
        borderRadius: BorderRadius.only(
          // Top-left is square: the first tab always starts at the panel's
          // left edge. Top-right is square once the tabs overflow to it.
          topRight: squareTopRight ? Radius.zero : r,
          bottomLeft: r,
          bottomRight: r,
        ),
        border: Border.all(color: StudentPortalColors.cardBorder(context)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(context.isDarkMode ? 0.25 : 0.04),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _FolderTab extends StatelessWidget {
  const _FolderTab({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  // App-wide primary CTA blue, as on every other dashboard's active control.
  static const _accent = Color(0xFF345892);
  static const _radius = BorderRadius.vertical(top: Radius.circular(14));

  @override
  Widget build(BuildContext context) {
    final activeText = context.isDarkMode ? const Color(0xFFA9C6FD) : _accent;
    final textColor =
        selected ? activeText : StudentPortalColors.textSecondary(context);
    return Material(
      color: selected
          ? StudentPortalColors.surface(context)
          : StudentPortalColors.surfaceMuted(context),
      shape: RoundedRectangleBorder(
        borderRadius: _radius,
        side: BorderSide(color: StudentPortalColors.cardBorder(context)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: selected ? _tabHeight : _tabHeight - 6,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          alignment: Alignment.center,
          // The active tab's accent strip along its top edge.
          decoration: selected
              ? BoxDecoration(
                  border: Border(top: BorderSide(color: activeText, width: 3)),
                )
              : null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 12.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  color: textColor,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                decoration: BoxDecoration(
                  color: selected
                      ? _accent.withOpacity(context.isDarkMode ? 0.35 : 0.14)
                      : StudentPortalColors.surface(context),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$count',
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: textColor,
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
