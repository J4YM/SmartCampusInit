import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/parent_portal_colors.dart';
import '../theme/parent_portal_spacing.dart';

/// One tab of a [FolderTabbedPanel]: its label and the count shown beside it.
class FolderTabSpec {
  const FolderTabSpec(this.label, this.count);

  final String label;
  final int count;
}

/// The Parent Portal's folder-style filter: tabs sitting on the top edge of
/// the content panel, the active one sharing the panel's surface (and
/// covering its top border) so the two read as one folder. Shared by the
/// Violations and Interventions pages. Needs a bounded height (fills it).
class FolderTabbedPanel extends StatefulWidget {
  const FolderTabbedPanel({
    super.key,
    required this.tabs,
    required this.selectedIndex,
    required this.onSelected,
    required this.child,
  });

  final List<FolderTabSpec> tabs;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  /// The panel's content.
  final Widget child;

  @override
  State<FolderTabbedPanel> createState() => _FolderTabbedPanelState();
}

class _FolderTabbedPanelState extends State<FolderTabbedPanel> {
  bool _tabsOverflow = false;

  @override
  Widget build(BuildContext context) {
    final tabs = widget.tabs;
    return Stack(
      children: [
        Positioned.fill(
          top: _tabHeight - 1,
          child: _FolderPanel(
            squareTopRight: _tabsOverflow,
            child: widget.child,
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
                for (var i = 0; i < tabs.length; i++) ...[
                  _FolderTab(
                    label: tabs[i].label,
                    count: tabs[i].count,
                    selected: i == widget.selectedIndex,
                    onTap: () => widget.onSelected(i),
                  ),
                  if (i != tabs.length - 1)
                    const SizedBox(width: ParentPortalSpacing.xs),
                ],
              ],
            ),
          ),
        ),
      ],
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
      padding: const EdgeInsets.all(ParentPortalSpacing.lg),
      decoration: BoxDecoration(
        color: ParentPortalColors.surface(context),
        borderRadius: BorderRadius.only(
          // Top-left is square: the first tab always starts at the panel's
          // left edge. Top-right is square once the tabs overflow to it.
          topRight: squareTopRight ? Radius.zero : r,
          bottomLeft: r,
          bottomRight: r,
        ),
        border: Border.all(color: ParentPortalColors.cardBorder(context)),
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
        selected ? activeText : ParentPortalColors.textSecondary(context);
    return Material(
      color: selected
          ? ParentPortalColors.surface(context)
          : ParentPortalColors.surfaceMuted(context),
      shape: RoundedRectangleBorder(
        borderRadius: _radius,
        side: BorderSide(color: ParentPortalColors.cardBorder(context)),
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
                      : ParentPortalColors.surface(context),
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
