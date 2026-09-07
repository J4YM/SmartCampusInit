import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/student_portal_colors.dart';

/// 40×40 header action icon — same size/shape/badge convention as every
/// staff dashboard's `HeaderIconButton`, but theme-aware instead of
/// hardcoded white-on-navy, since [PortalHeaderBar] can be white (light
/// mode) or navy (dark mode).
class PortalHeaderIconButton extends StatelessWidget {
  const PortalHeaderIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.badgeCount = 0,
  });

  final IconData icon;
  final VoidCallback onTap;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Material(
          color: StudentPortalColors.surfaceMuted(context),
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border:
                    Border.all(color: StudentPortalColors.cardBorder(context)),
              ),
              child: Icon(
                icon,
                size: 20,
                color: StudentPortalColors.textSecondary(context),
              ),
            ),
          ),
        ),
        if (badgeCount > 0)
          Positioned(
            right: -4,
            top: -4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0xFFDC2626),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: context.isDarkMode
                      ? const Color(0xFF15253F)
                      : StudentPortalColors.surface(context),
                  width: 2,
                ),
              ),
              child: Text(
                badgeCount > 99 ? '99+' : '$badgeCount',
                style: GoogleFonts.poppins(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
