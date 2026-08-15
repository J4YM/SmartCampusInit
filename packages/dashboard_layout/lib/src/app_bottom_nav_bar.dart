import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Fixed bottom navigation bar shown on mobile-width viewports (below
/// [kDashboardMobileBreakpoint]) in place of the desktop header's inline
/// email/notification/profile icons — Figma node 498:1602. Meant to be
/// passed as a `Scaffold.bottomNavigationBar`, which Flutter always pins to
/// the bottom of the screen regardless of body scroll position.
///
/// Takes an explicit [isDarkMode] flag rather than reading
/// `context.isDarkMode` — same convention as the header's popovers
/// (`NotificationsPopover`, `EmailPopover`, …), which live in per-module
/// packages that can't share this package's dark-mode-aware color tokens.
class AppBottomNavBar extends StatelessWidget {
  const AppBottomNavBar({
    super.key,
    required this.onEmailTap,
    required this.onNotificationTap,
    required this.onProfileTap,
    this.notificationBadgeCount = 0,
    this.isDarkMode = false,
  });

  final VoidCallback onEmailTap;
  final VoidCallback onNotificationTap;
  final VoidCallback onProfileTap;
  final int notificationBadgeCount;
  final bool isDarkMode;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF16191D) : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDarkMode ? const Color(0xFF334155) : const Color(0x1A000000),
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 65,
          child: Row(
            children: [
              Expanded(
                child: _BottomNavItem(
                  icon: Icons.mail_outline_rounded,
                  label: 'Email',
                  onTap: onEmailTap,
                  isDarkMode: isDarkMode,
                ),
              ),
              Expanded(
                child: _BottomNavItem(
                  icon: Icons.notifications_none_rounded,
                  label: 'Notification',
                  onTap: onNotificationTap,
                  isDarkMode: isDarkMode,
                  badgeCount: notificationBadgeCount,
                ),
              ),
              Expanded(
                child: _BottomNavItem(
                  icon: Icons.person_outline_rounded,
                  label: 'Profile',
                  onTap: onProfileTap,
                  isDarkMode: isDarkMode,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomNavItem extends StatelessWidget {
  const _BottomNavItem({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.isDarkMode,
    this.badgeCount = 0,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDarkMode;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final color = isDarkMode ? const Color(0xFFF1F5F9) : const Color(0xFF343A40);

    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(icon, color: color, size: 24),
              if (badgeCount > 0)
                Positioned(
                  right: -6,
                  top: -4,
                  child: IgnorePointer(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDC2626),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: isDarkMode ? const Color(0xFF16191D) : Colors.white,
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
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
