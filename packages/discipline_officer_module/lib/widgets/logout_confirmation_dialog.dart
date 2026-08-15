import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Centered "Are you sure you want to logout?" confirmation modal (Figma
/// node 411:911). Shared across every module's own logout trigger (header
/// button, sidebar item, account popover, …) so the confirm-before-sign-out
/// UX and styling stay identical everywhere it appears — callers own
/// showing it (`showDialog`) and what "confirm" actually does (typically
/// `session.signOut()`).
class LogoutConfirmationDialog extends StatelessWidget {
  const LogoutConfirmationDialog({
    super.key,
    required this.onCancel,
    required this.onConfirm,
    this.isDarkMode = false,
  });

  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  /// Rendered through `showDialog`'s own root-navigator Overlay, which sits
  /// outside the dashboard page's local per-page Theme — so
  /// `context.isDarkMode` here would read the app's ambient theme, not the
  /// page's toggle. Threaded in explicitly instead (same pattern as
  /// `AccountProfileMenu`).
  final bool isDarkMode;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        width: 425,
        padding: const EdgeInsets.fromLTRB(40, 33, 40, 32),
        decoration: BoxDecoration(
          color: isDarkMode ? const Color(0xFF16191D) : Colors.white,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              size: 72,
              color: Color(0xFFCD4855),
            ),
            const SizedBox(height: 16),
            Text(
              'Logout Confirmation',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: context.isMobileWidth ? 22 : 24,
                fontWeight: FontWeight.w700,
                color: isDarkMode ? const Color(0xFFF1F5F9) : Colors.black,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Do you really want to exit the app?',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: context.isMobileWidth ? 11 : 13,
                fontWeight: FontWeight.w400,
                color: isDarkMode ? const Color(0xFF94A3B8) : Colors.black,
              ),
            ),
            const SizedBox(height: 26),
            Row(
              children: [
                Expanded(
                  child: _LogoutDialogButton(
                    label: 'Cancel',
                    backgroundColor: isDarkMode
                        ? const Color(0xFF334155)
                        : const Color(0xFFE6E6E6),
                    textColor:
                        isDarkMode ? const Color(0xFFF1F5F9) : Colors.black,
                    onTap: onCancel,
                  ),
                ),
                const SizedBox(width: 22),
                Expanded(
                  child: _LogoutDialogButton(
                    label: 'Yes, logout',
                    backgroundColor: const Color(0xFFCD4855),
                    textColor: const Color(0xFFE6E6E6),
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
    return SizedBox(
      height: 33,
      child: Material(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(5),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(5),
          child: Center(
            child: Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: context.isMobileWidth ? 11 : 13,
                fontWeight: FontWeight.w500,
                color: textColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
