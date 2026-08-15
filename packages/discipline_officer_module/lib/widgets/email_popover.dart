import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Email dropdown anchored below a header's mail icon via
/// [showHeaderPopover] (Figma node 491:1122) — same 400px/10px-radius
/// bordered card chrome as [NotificationsPopover], so every module's mail
/// icon renders pixel-identical to the design. No inbox data source exists
/// yet, so this always renders the "No Email" empty state from the design.
class EmailPopover extends StatelessWidget {
  const EmailPopover({
    super.key,
    required this.onViewAll,
    this.isDarkMode = false,
  });

  final VoidCallback onViewAll;

  /// Rendered through `showMenu`'s own Overlay/route (see
  /// `showHeaderPopover`), which sits outside the dashboard page's local
  /// per-page Theme — so `context.isDarkMode` here would read the app's
  /// ambient theme, not the page's toggle. Threaded in explicitly instead
  /// (same pattern as `AccountProfileMenu`).
  final bool isDarkMode;

  @override
  Widget build(BuildContext context) {
    final cardColor = isDarkMode ? const Color(0xFF16191D) : Colors.white;
    final borderColor =
        isDarkMode ? const Color(0xFF334155) : const Color(0x26000000);
    final primaryText = isDarkMode ? const Color(0xFFF1F5F9) : Colors.black;

    return Material(
      color: Colors.transparent,
      child: Container(
        width: 400,
        height: 270,
        clipBehavior: Clip.antiAlias,
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: borderColor),
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: borderColor)),
              ),
              child: Text(
                'Email',
                style: GoogleFonts.poppins(
                  fontSize: context.isMobileWidth ? 14 : 16,
                  fontWeight: FontWeight.w500,
                  color: primaryText,
                ),
              ),
            ),
            Expanded(
              child: Center(
                child: Text(
                  'No Email',
                  style: GoogleFonts.poppins(
                    fontSize: context.isMobileWidth ? 14 : 16,
                    fontWeight: FontWeight.w500,
                    color: primaryText,
                  ),
                ),
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.only(top: 10),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: borderColor)),
              ),
              child: Center(
                child: InkWell(
                  onTap: onViewAll,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      'View all emails',
                      style: GoogleFonts.poppins(
                        fontSize: context.isMobileWidth ? 11 : 13,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF345892),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
