import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Centered "Are you sure you want to logout?" confirmation modal. Shared
/// across every module's own logout trigger (header button, sidebar item,
/// account popover, …) so the confirm-before-sign-out UX and styling stay
/// identical everywhere it appears — callers own showing it (`showDialog`)
/// and what "confirm" actually does (typically `session.signOut()`).
class LogoutConfirmationDialog extends StatelessWidget {
  const LogoutConfirmationDialog({
    super.key,
    required this.onCancel,
    required this.onConfirm,
  });

  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        width: 360,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Logout Confirmation!',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF000000),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Are you sure you want to logout?',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF4A4A4A),
              ),
            ),
            const SizedBox(height: 28),
            Row(
              children: [
                Expanded(
                  child: _LogoutDialogButton(
                    label: 'Cancel',
                    backgroundColor: const Color(0xFFE6E6E6),
                    textColor: const Color(0xFF777777),
                    onTap: onCancel,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _LogoutDialogButton(
                    label: 'Confirm',
                    backgroundColor: const Color(0xFFCD4855),
                    textColor: Colors.white,
                    onTap: onConfirm,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LogoutDialogButton extends StatelessWidget {
  const _LogoutDialogButton({
    required this.label,
    required this.backgroundColor,
    required this.textColor,
    required this.onTap,
  });

  final String label;
  final Color backgroundColor;
  final Color textColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Center(
            child: Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: textColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
