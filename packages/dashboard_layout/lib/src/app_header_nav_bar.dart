import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Full-bleed navy top header shared by every dashboard module (Discipline
/// Officer, Guidance Counselor, …). The outer bar always fills 100% of the
/// viewport width and sticks flush to the top — it is not capped or
/// centered. Only the header's *contents* (leading icon/back button, title,
/// action icons) are centered and capped at [maxWidth], so they line up with
/// the 1440px-capped card grid below (see `DashboardPageWrapper`) without the
/// navy background itself ever leaving a gap on ultra-wide monitors.
class AppHeaderNavBar extends StatelessWidget {
  const AppHeaderNavBar({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.actions = const [],
    this.maxWidth = 1440,
    this.backgroundColor = const Color(0xFF15253F),
    this.contentPadding = const EdgeInsets.symmetric(
      horizontal: 24,
      vertical: 12,
    ),
  });

  final String title;
  final String? subtitle;

  /// Rendered before the title/subtitle block — e.g. a back button plus a
  /// module icon avatar.
  final Widget? leading;

  /// Right-aligned action row — e.g. notifications, settings, profile,
  /// sign-out. Each entry gets its own listener preserved from the caller;
  /// this widget only supplies the full-width bar chrome around them.
  final List<Widget> actions;

  final double maxWidth;
  final Color backgroundColor;
  final EdgeInsets contentPadding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: backgroundColor,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Padding(
            padding: contentPadding,
            child: Row(
              children: [
                if (leading != null) ...[leading!, const SizedBox(width: 12)],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                            color: const Color(0xB3E6E6E6),
                          ),
                        ),
                    ],
                  ),
                ),
                for (final action in actions) ...[
                  const SizedBox(width: 10),
                  action,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
