import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// The frame every Admin page sits in: the page background, a 28px title with
/// a muted line under it, then the page's cards — the same header Register
/// Syncs, Staff Accounts and the other pages draw, so a page added later looks
/// like the rest without copying their markup.
///
/// Scrolls like those pages do: ONE scroll view spans the whole content pane
/// (title included, scrollbar at the pane's true edge) and only the content
/// inside it is capped at 1440px and centered. There is no inner scroll
/// region under a pinned heading.
class AdminPageFrame extends StatelessWidget {
  const AdminPageFrame({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = context.isDarkMode;
    return ColoredBox(
      color: dark ? const Color(0xFF0E0E0E) : const Color(0xFFF1F5F9),
      child: SafeArea(
        child: SingleChildScrollView(
          child: DashboardPageWrapper(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color:
                        dark ? const Color(0xFFF5F5F5) : const Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: GoogleFonts.poppins(
                    fontSize: context.isMobileWidth ? 12 : 14,
                    fontWeight: FontWeight.w400,
                    color:
                        dark ? const Color(0xFFA1A1AA) : const Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 24),
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
