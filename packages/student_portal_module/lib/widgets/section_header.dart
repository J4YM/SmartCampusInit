import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/student_portal_colors.dart';
import '../theme/student_portal_spacing.dart';

/// Card-header row shared by every bento card: a title, optional trailing
/// control (subject dropdown, mini-tabs), and an optional "View all" link.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.trailing,
    this.onSeeAll,
  });

  final String title;
  final Widget? trailing;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: StudentPortalSpacing.md),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: StudentPortalColors.textPrimary(context),
              ),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: StudentPortalSpacing.sm),
            // Not Flexible: wrapping it there gave `trailing` an equal
            // flex share of the row alongside the title's Expanded above,
            // splitting the row 50/50 and leaving `trailing` stranded near
            // the row's midpoint instead of flush against the card's right
            // edge. A plain (non-flex) child keeps its own intrinsic width
            // and lets the title's Expanded absorb all the leftover space,
            // pinning `trailing` to the far right — same as `onSeeAll`
            // below already does.
            trailing!,
          ],
          if (onSeeAll != null) ...[
            const SizedBox(width: StudentPortalSpacing.sm),
            TextButton(
              onPressed: onSeeAll,
              style: TextButton.styleFrom(
                foregroundColor: StudentPortalColors.accent(context),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                'View all',
                style: GoogleFonts.inter(
                    fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
