import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'control_metrics.dart';
import 'responsive_x.dart';
import 'secondary_pill_button.dart';

/// Compact Previous/Next control for the bottom of a card that caps its own
/// list at a page size — e.g. a queue or roster card that paginates
/// client-side over an already-fully-fetched list, as opposed to a
/// page-level footer driving server-side pagination.
///
/// Renders as a pair of pill buttons — "Previous" on a muted background,
/// "Next" solid in the dashboard's accent color — matching the Registrar
/// Dashboard's Student List table, the reference style every dashboard's
/// card-level pagination now shares.
class CardPaginationFooter extends StatelessWidget {
  const CardPaginationFooter({
    super.key,
    required this.currentPage,
    required this.totalPages,
    required this.totalCount,
    required this.textColor,
    required this.accentColor,
    required this.mutedBackground,
    this.isLoading = false,
    required this.onPrevious,
    required this.onNext,
  });

  final int currentPage;
  final int totalPages;

  /// Null when the total isn't known (e.g. a server-paged list whose count
  /// hasn't come back yet) — the label then omits it.
  final int? totalCount;
  final Color textColor;

  /// This dashboard's brand accent — "Next"'s background (the "Previous"
  /// pill is the shared [SecondaryPillButton] and ignores it).
  final Color accentColor;

  /// Unused since "Previous" became a [SecondaryPillButton]; kept so callers compile.
  final Color mutedBackground;

  final bool isLoading;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final canGoPrevious = !isLoading && currentPage > 1;
    final canGoNext = !isLoading && currentPage < totalPages;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(
            totalCount == null
                ? 'Page $currentPage of $totalPages'
                : 'Page $currentPage of $totalPages · $totalCount total',
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.poppins(
              fontSize: context.isMobileWidth ? 9 : 11,
              color: textColor,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // "Previous" is a secondary button — the app-wide tinted pill.
            SecondaryPillButton(
              label: 'Previous',
              onTap: canGoPrevious ? onPrevious : null,
            ),
            const SizedBox(width: 8),
            PaginationPillButton(
              label: 'Next',
              background: accentColor,
              foreground: Colors.white,
              onTap: canGoNext ? onNext : null,
            ),
          ],
        ),
      ],
    );
  }
}

/// The "Previous"/"Next" pill used by [CardPaginationFooter] — exported
/// standalone so a card with its own bespoke pagination footer text (e.g. a
/// "Showing X of Y <noun>" label instead of "Page X of Y") can still reuse
/// the exact same button styling instead of hand-rolling it.
class PaginationPillButton extends StatelessWidget {
  const PaginationPillButton({
    super.key,
    required this.label,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        // Same minimum height as "Previous" (a SecondaryPillButton).
        child: ConstrainedBox(
          constraints:
              const BoxConstraints(minHeight: kDashboardControlHeight),
          child: Align(
            widthFactor: 1,
            heightFactor: 1,
            child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: onTap == null ? foreground.withOpacity(0.4) : foreground,
            ),
          ),
        ),
          ),
        ),
      ),
    );
  }
}
