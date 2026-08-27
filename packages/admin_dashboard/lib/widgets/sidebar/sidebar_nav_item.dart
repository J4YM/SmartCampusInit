import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_colors.dart';

class SidebarNavItem extends StatelessWidget {
  const SidebarNavItem({
    super.key,
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
    this.isStandalone = false,
    this.isCollapsed = false,
  });

  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  /// True for lone bottom-list items ("Audit & Privacy Logs", "Reports &
  /// Exports"), which use the lighter "standalone item" typography instead
  /// of the bold "section header" style used by "Overview".
  final bool isStandalone;

  /// True when the sidebar is the icon-only rail — hides the label (shown
  /// instead as a hover [Tooltip]) and centers the icon.
  final bool isCollapsed;

  @override
  Widget build(BuildContext context) {
    final textStyle = isStandalone
        ? GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppColors.sidebarStandaloneText,
          )
        : GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          );

    final iconWidget = Icon(icon, size: 20, color: AppColors.sidebarText);

    final content = isCollapsed
        ? Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(child: iconWidget),
          )
        : Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                iconWidget,
                const SizedBox(width: 14),
                Expanded(child: Text(label, style: textStyle)),
              ],
            ),
          );

    final item = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: isSelected ? AppColors.sidebarActive : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          hoverColor: AppColors.sidebarActive,
          splashColor: AppColors.sidebarDivider,
          child: content,
        ),
      ),
    );

    return isCollapsed ? Tooltip(message: label, child: item) : item;
  }
}
