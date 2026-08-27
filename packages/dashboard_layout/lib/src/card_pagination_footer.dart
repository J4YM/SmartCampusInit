import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'responsive_x.dart';

/// Compact Previous/Next control for the bottom of a card that caps its own
/// list at a page size — e.g. a queue or roster card that paginates
/// client-side over an already-fully-fetched list, as opposed to a
/// page-level footer driving server-side pagination.
class CardPaginationFooter extends StatelessWidget {
  const CardPaginationFooter({
    super.key,
    required this.currentPage,
    required this.totalPages,
    required this.totalCount,
    required this.textColor,
    this.isLoading = false,
    required this.onPrevious,
    required this.onNext,
  });

  final int currentPage;
  final int totalPages;
  final int totalCount;
  final Color textColor;
  final bool isLoading;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(
            'Page $currentPage of $totalPages · $totalCount total',
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.poppins(
              fontSize: context.isMobileWidth ? 9 : 11,
              color: textColor,
            ),
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: (isLoading || currentPage <= 1) ? null : onPrevious,
              icon: const Icon(Icons.chevron_left_rounded),
              iconSize: 20,
              visualDensity: VisualDensity.compact,
              tooltip: 'Previous page',
            ),
            IconButton(
              onPressed:
                  (isLoading || currentPage >= totalPages) ? null : onNext,
              icon: const Icon(Icons.chevron_right_rounded),
              iconSize: 20,
              visualDensity: VisualDensity.compact,
              tooltip: 'Next page',
            ),
          ],
        ),
      ],
    );
  }
}
