import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_colors.dart';

class SidebarAccordion extends StatelessWidget {
  const SidebarAccordion({
    super.key,
    required this.title,
    required this.icon,
    required this.isExpanded,
    required this.onToggle,
    required this.children,
    this.isCollapsed = false,
    this.onExpandRequested,
  });

  final String title;
  final IconData icon;
  final bool isExpanded;
  final VoidCallback onToggle;
  final List<Widget> children;

  /// True when the sidebar is the icon-only rail — hides the title, expand
  /// caret, and sub-items entirely (shown instead as a hover [Tooltip]).
  final bool isCollapsed;

  /// Invoked instead of [onToggle] when tapped while [isCollapsed] — expands
  /// the sidebar back out (and this group along with it) rather than trying
  /// to expand a group with no room to show its children.
  final VoidCallback? onExpandRequested;

  @override
  Widget build(BuildContext context) {
    final headerIcon = Icon(icon, size: 20, color: AppColors.sidebarText);

    final headerContent = isCollapsed
        ? Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(child: headerIcon),
          )
        : Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                headerIcon,
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    title,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
                AnimatedRotation(
                  turns: isExpanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 20,
                    color: AppColors.sidebarText,
                  ),
                ),
              ],
            ),
          );

    final header = Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: isCollapsed ? (onExpandRequested ?? onToggle) : onToggle,
        borderRadius: BorderRadius.circular(8),
        hoverColor: AppColors.sidebarActive,
        splashColor: AppColors.sidebarDivider,
        child: headerContent,
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          isCollapsed ? Tooltip(message: title, child: header) : header,
          if (!isCollapsed)
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: Padding(
                padding: const EdgeInsets.only(left: 22, top: 4, bottom: 4),
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    border: Border(
                      left:
                          BorderSide(color: AppColors.sidebarDivider, width: 1),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: children,
                  ),
                ),
              ),
              crossFadeState: isExpanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 200),
              sizeCurve: Curves.easeInOut,
            ),
        ],
      ),
    );
  }
}

class SidebarSubItem extends StatelessWidget {
  const SidebarSubItem({
    super.key,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 12, right: 4, bottom: 2),
      child: Material(
        color: isSelected ? AppColors.sidebarActive : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          hoverColor: AppColors.sidebarActive,
          splashColor: AppColors.sidebarDivider,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: AppColors.sidebarSubText,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
