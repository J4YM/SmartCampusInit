import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'bento_card.dart';
import 'brightness_x.dart';
import 'card_title_style.dart';
import 'control_metrics.dart';
import 'dashboard_table.dart';
import 'dashboard_table_rows.dart';
import 'responsive_x.dart';

/// One full-width table card in the app-wide layout: a title with a muted
/// subtitle, an optional toolbar (search / filter / actions), the column
/// header over the rows (or [empty]), and the pagination [footer] inside the
/// card — the shape every dashboard's list uses.
///
/// Sizes to its rows on a page that scrolls as a whole, and fills + scrolls
/// internally when its parent hands it a bounded height.
class TitledTableCard extends StatelessWidget {
  const TitledTableCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.columns,
    required this.rows,
    required this.empty,
    this.toolbar,
    this.footer,
    this.backgroundColor,
    this.borderColor,
    this.titleColor,
  });

  final String title;

  /// The muted line under the title (a count, or an icon + notice). See
  /// [subtitleStyle].
  final Widget subtitle;
  final Widget? toolbar;
  final List<DashboardTableColumn> columns;

  /// Rows keyed by a stable id so new ones animate in (see
  /// [DashboardTableRows]).
  final List<Widget> rows;
  final Widget empty;

  /// A `CardPaginationFooter`; wrapped in the table footer divider here.
  final Widget? footer;

  /// Default to the shared table card colors.
  final Color? backgroundColor;
  final Color? borderColor;
  final Color? titleColor;

  /// The muted subtitle text style.
  static TextStyle subtitleStyle(BuildContext context, {Color? color}) =>
      GoogleFonts.poppins(
        fontSize: context.isMobileWidth ? 11 : 13,
        color: color ?? DashboardTableColors.secondaryText(context),
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
          backgroundColor: backgroundColor ?? DashboardTableColors.card(context),
          borderColor: borderColor ?? DashboardTableColors.border(context),
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
                      style: dashboardCardTitleStyle(
                        context,
                        color: titleColor ??
                            DashboardTableColors.primaryText(context),
                      ),
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

/// The 34px search field every dashboard toolbar uses: borderless, pale fill,
/// search glyph. Colors default to the shared palette; pass them to match a
/// dashboard's own tokens.
class DashboardSearchField extends StatelessWidget {
  const DashboardSearchField({
    super.key,
    required this.controller,
    required this.onChanged,
    this.hint = 'Search',
    this.fillColor,
    this.textColor,
    this.hintColor,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String hint;
  final Color? fillColor;
  final Color? textColor;
  final Color? hintColor;

  /// The default field fill — the page background of each theme.
  static Color defaultFill(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF0E0E0E) : const Color(0xFFF1F5F9);

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide.none,
    );
    final size = context.isMobileWidth ? 11.0 : 13.0;
    final hintTone = hintColor ??
        (context.isDarkMode ? const Color(0xFF71717A) : const Color(0xFF94A3B8));
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
          fontSize: size,
          color: textColor ?? DashboardTableColors.primaryText(context),
        ),
        decoration: InputDecoration(
          isDense: true,
          hintText: hint,
          hintStyle: GoogleFonts.poppins(fontSize: size, color: hintTone),
          prefixIcon: Icon(Icons.search_rounded, size: 20, color: hintTone),
          filled: true,
          fillColor: fillColor ?? defaultFill(context),
          contentPadding: EdgeInsets.zero,
          border: border,
          enabledBorder: border,
          focusedBorder: border,
        ),
      ),
    );
  }
}

/// The icon-only action that ends a table row: a 36px button with a 20px
/// glyph in the brand blue (light blue in dark mode) unless [color] is given,
/// always with a tooltip. Use it in a table's sticky action column.
class DashboardRowIconButton extends StatelessWidget {
  const DashboardRowIconButton({
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

  static const Color _brandBlue = Color(0xFF345892);

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
              (context.isDarkMode ? const Color(0xFFA9C6FD) : _brandBlue),
          semanticLabel: tooltip,
        ),
      ),
    );
  }
}
