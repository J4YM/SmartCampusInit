import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/student_portal_colors.dart';
import '../theme/student_portal_spacing.dart';

/// Full-bleed top header — same shape and 1440px-capped, centered content
/// as every staff dashboard's `AppHeaderNavBar`, but themed rather than
/// hardcoded navy: white in light mode (so the student system reads as its
/// own surface, not a copy of the staff navy bar) and the same dark blue
/// (`#15253F`) every dashboard uses once dark mode is on.
class PortalHeaderBar extends StatelessWidget {
  const PortalHeaderBar({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.actions = const [],
    this.maxWidth = StudentPortalSpacing.maxContentWidth,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget> actions;
  final double maxWidth;

  static const Color _darkBackground = Color(0xFF15253F);

  @override
  Widget build(BuildContext context) {
    final background = context.isDarkMode
        ? _darkBackground
        : StudentPortalColors.surface(context);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: background,
        border: Border(
          bottom: BorderSide(color: StudentPortalColors.cardBorder(context)),
        ),
      ),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: StudentPortalSpacing.pageHorizontal(context),
              vertical: 12,
            ),
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
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                          fontSize: context.isMobileWidth ? 16 : 18,
                          fontWeight: FontWeight.w700,
                          color: StudentPortalColors.textPrimary(context),
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: context.isMobileWidth ? 10 : 12,
                            fontWeight: FontWeight.w400,
                            color: StudentPortalColors.textSecondary(context),
                          ),
                        ),
                    ],
                  ),
                ),
                for (final action in actions) ...[
                  SizedBox(width: context.isMobileWidth ? 6 : 10),
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
