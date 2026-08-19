import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class SidebarHeader extends StatelessWidget {
  const SidebarHeader({
    super.key,
    this.onBackToHub,
    this.unreadNotificationCount = 0,
    this.onNotificationsTap,
  });

  /// Shown as a back-arrow left of the logo when supplied — returns to the
  /// Admin Hub module grid without signing out (distinct from the sidebar
  /// footer's "Logout" action below).
  final VoidCallback? onBackToHub;

  /// Admin's own notification bell — Admin both sends notifications (from
  /// the Notifications page) and receives some itself (e.g. "RFID Gateway
  /// Offline"), unlike the other dashboards which only receive.
  final int unreadNotificationCount;
  final VoidCallback? onNotificationsTap;

  @override
  Widget build(BuildContext context) {
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
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: const Color(0xFF1E3354),
            ),
            child: Center(
              child: Container(
                width: 22,
                height: 22,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF8B5CF6), Color(0xFF3B82F6)],
                  ),
                ),
              ),
            ),
          ),
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
          if (onNotificationsTap != null)
            InkWell(
              onTap: onNotificationsTap,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(
                      Icons.notifications_none_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                    if (unreadNotificationCount > 0)
                      Positioned(
                        right: -2,
                        top: -2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFFCD4855),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          constraints:
                              const BoxConstraints(minWidth: 15, minHeight: 15),
                          child: Text(
                            '$unreadNotificationCount',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.poppins(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
