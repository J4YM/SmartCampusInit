import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// 40×40 translucent icon button used inside [AppHeaderNavBar]'s action
/// row (notifications bell, settings gear, sign-out, …) — extracted from the
/// near-identical private copies every dashboard module used to keep, so
/// badge styling and hover behavior stay pixel-identical across modules.
class HeaderIconButton extends StatelessWidget {
  const HeaderIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.badgeCount = 0,
    this.backgroundColor = const Color(0x14FFFFFF),
    this.borderColor = const Color(0x1AFFFFFF),
    this.badgeColor = const Color(0xFFDC2626),
    this.badgeBorderColor = const Color(0xFF15253F),
  });

  final IconData icon;
  final VoidCallback onTap;
  final int badgeCount;
  final Color backgroundColor;
  final Color borderColor;
  final Color badgeColor;

  /// Matches the navy card behind the button so the badge's outline reads as
  /// a notch cut out of the header rather than a hard-edged circle.
  final Color badgeBorderColor;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Material(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            hoverColor: Colors.white.withValues(alpha: 0.08),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: borderColor),
              ),
              child: Icon(icon, color: Colors.white, size: 20),
            ),
          ),
        ),
        if (badgeCount > 0)
          Positioned(
            right: -4,
            top: -4,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: badgeColor,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: badgeBorderColor, width: 2),
                ),
                child: Text(
                  badgeCount > 99 ? '99+' : '$badgeCount',
                  style: GoogleFonts.poppins(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Circular white avatar button used as the header's profile trigger.
class ProfileAvatarButton extends StatelessWidget {
  const ProfileAvatarButton({
    super.key,
    required this.onTap,
    this.foregroundColor = const Color(0xFF15253F),
  });

  final VoidCallback onTap;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        hoverColor: foregroundColor.withValues(alpha: 0.08),
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(Icons.person, color: foregroundColor, size: 22),
        ),
      ),
    );
  }
}
