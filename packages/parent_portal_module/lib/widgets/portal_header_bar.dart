import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/parent_portal_spacing.dart';

/// Full-bleed top header — same shape, 1440px-capped centered content, and
/// fixed navy (`#15253F`) background as every staff dashboard's
/// `AppHeaderNavBar`, regardless of light/dark mode.
class PortalHeaderBar extends StatelessWidget {
  const PortalHeaderBar({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.actions = const [],
    this.maxWidth = ParentPortalSpacing.maxContentWidth,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget> actions;
  final double maxWidth;

  static const Color _background = Color(0xFF15253F);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: _background,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: ParentPortalSpacing.pageHorizontal(context),
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
                          color: Colors.white,
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: context.isMobileWidth ? 10 : 12,
                            fontWeight: FontWeight.w400,
                            color: const Color(0xB3E6E6E6),
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
