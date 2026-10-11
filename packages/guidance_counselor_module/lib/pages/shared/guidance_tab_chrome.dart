import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Palette of the Guidance dashboard's own tabs — the same values as the
/// dashboard page's private tokens, so a tab built here sits seamlessly beside
/// the Overview / Batch Analysis cards.
abstract final class GuidanceTabColors {
  static const primaryAction = Color(0xFF345892);

  static Color card(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF191A1F) : const Color(0xFFFFFFFF);
  static Color cardBorder(BuildContext context) => context.isDarkMode
      ? const Color(0xFF22242B)
      : const Color(0x0D000000);
  static Color primaryText(BuildContext context) =>
      context.isDarkMode ? const Color(0xFFF5F5F5) : const Color(0xFF1E293B);
  static Color secondaryText(BuildContext context) =>
      context.isDarkMode ? const Color(0xFFA1A1AA) : const Color(0xFF64748B);
  static Color mutedIcon(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF71717A) : const Color(0xFF94A3B8);
  static Color searchFill(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF0E0E0E) : const Color(0xFFF1F5F9);
  static Color surfaceBackground(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF0E0E0E) : const Color(0xFFF1F5F9);
}

/// The 34px search field every dashboard toolbar uses (borderless, pale fill,
/// search glyph), in the Guidance palette.
class GuidanceSearchField extends StatelessWidget {
  const GuidanceSearchField({
    super.key,
    required this.controller,
    required this.onChanged,
    this.hint = 'Search',
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide.none,
    );
    final size = context.isMobileWidth ? 11.0 : 13.0;
    return SizedBox(
      height: kDashboardControlHeight,
      child: TextField(
        expands: true,
        maxLines: null,
        minLines: null,
        textAlignVertical: TextAlignVertical.center,
        keyboardType: TextInputType.text,
        controller: controller,
        onChanged: onChanged,
        style: GoogleFonts.poppins(
            fontSize: size, color: GuidanceTabColors.primaryText(context)),
        decoration: InputDecoration(
          isDense: true,
          hintText: hint,
          hintStyle: GoogleFonts.poppins(
              fontSize: size, color: GuidanceTabColors.mutedIcon(context)),
          prefixIcon: Icon(Icons.search_rounded,
              size: 20, color: GuidanceTabColors.mutedIcon(context)),
          filled: true,
          fillColor: GuidanceTabColors.searchFill(context),
          contentPadding: EdgeInsets.zero,
          border: border,
          enabledBorder: border,
          focusedBorder: border,
        ),
      ),
    );
  }
}

/// One full-width table card in the app-wide layout: a title with a muted
/// subtitle, an optional toolbar (search / filter), the column header over
/// the rows (or [empty]), and the pagination [footer] inside the card.
///
/// Sizes to its rows on a page that scrolls as a whole, and fills + scrolls
/// internally when its parent hands it a bounded height — the same two modes
/// as the Student Affairs history card.
class GuidanceTableCard extends StatelessWidget {
  const GuidanceTableCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.columns,
    required this.rows,
    required this.empty,
    this.toolbar,
    this.footer,
  });

  final String title;

  /// The muted line under the title (a count, or an icon + notice).
  final Widget subtitle;
  final Widget? toolbar;
  final List<DashboardTableColumn> columns;

  /// Rows keyed by a stable id so new ones animate in (see
  /// [DashboardTableRows]).
  final List<Widget> rows;
  final Widget empty;

  /// A `CardPaginationFooter`; wrapped in the table footer divider here.
  final Widget? footer;

  /// The muted subtitle text style.
  static TextStyle subtitleStyle(BuildContext context) => GoogleFonts.poppins(
        fontSize: context.isMobileWidth ? 11 : 13,
        color: GuidanceTabColors.secondaryText(context),
      );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bounded = constraints.hasBoundedHeight;
        final body = DashboardTableRows(
          scrollable: true,
          shrinkWrap: !bounded,
          physics: bounded ? null : const NeverScrollableScrollPhysics(),
          empty: empty,
          rows: rows,
        );

        return BentoCard(
          backgroundColor: GuidanceTabColors.card(context),
          borderColor: GuidanceTabColors.cardBorder(context),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: bounded ? MainAxisSize.max : MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(29, 24, 29, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: dashboardCardTitleStyle(context,
                          color: GuidanceTabColors.primaryText(context)),
                    ),
                    const SizedBox(height: 4),
                    subtitle,
                  ],
                ),
              ),
              if (toolbar != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(25, 19, 25, 18),
                  child: toolbar,
                )
              else
                const SizedBox(height: 18),
              DashboardTableSection(
                columns: columns,
                expandBody: bounded,
                body: body,
              ),
              if (footer != null) DashboardTableFooter(child: footer!),
            ],
          ),
        );
      },
    );
  }
}

/// The icon-only action that ends a table row: 36px, 20px glyph, the brand
/// blue (light blue in dark mode) unless [color] is given, with a tooltip.
class GuidanceRowIconButton extends StatelessWidget {
  const GuidanceRowIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onPressed,
        padding: const EdgeInsets.all(8),
        constraints: const BoxConstraints.tightFor(width: 36, height: 36),
        style: IconButton.styleFrom(
          minimumSize: const Size(36, 36),
          fixedSize: const Size(36, 36),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        icon: Icon(
          icon,
          size: 20,
          color: color ??
              subNavActiveColor(context, GuidanceTabColors.primaryAction),
          semanticLabel: tooltip,
        ),
      ),
    );
  }
}

