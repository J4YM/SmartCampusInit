import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class SidebarHeader extends StatelessWidget {
  const SidebarHeader({
    super.key,
    this.onBackToHub,
    this.isCollapsed = false,
  });

  /// Shown as a back-arrow left of the logo when supplied — returns to the
  /// Admin Hub module grid without signing out (distinct from the sidebar
  /// footer's "Logout" action below).
  final VoidCallback? onBackToHub;

  /// True when the sidebar is collapsed to its icon-only rail — hides the
  /// title and secondary actions, leaving just the logo mark. Collapse is
  /// toggled from [AdminTopNavBar]'s hamburger button, not from here.
  final bool isCollapsed;

  @override
  Widget build(BuildContext context) {
    const logo = SchoolLogo();

    if (isCollapsed) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(0, 24, 0, 20),
        child: Center(child: logo),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
      child: Row(
        children: [
          if (onBackToHub != null) ...[
            InkWell(
              onTap: onBackToHub,
              borderRadius: BorderRadius.circular(8),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(
                  Icons.arrow_back_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
            const SizedBox(width: 10),
          ],
          logo,
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              'Dashboard',
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
