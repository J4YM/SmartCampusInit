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
  });

  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  /// True for lone bottom-list items ("Audit & Privacy Logs", "Reports &
  /// Exports"), which use the lighter "standalone item" typography instead
  /// of the bold "section header" style used by "Overview".
  final bool isStandalone;

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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: isSelected ? AppColors.sidebarActive : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          hoverColor: AppColors.sidebarActive,
          splashColor: AppColors.sidebarDivider,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Icon(icon, size: 20, color: AppColors.sidebarText),
                const SizedBox(width: 14),
                Expanded(child: Text(label, style: textStyle)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
