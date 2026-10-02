import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'bento_card.dart';
import 'brightness_x.dart';
import 'responsive_x.dart';

/// The app-wide data table — header row, data rows, empty state and footer
/// — taken from the Admin Student Directory table so every dashboard's
/// tables look and behave identically. Each table keeps its own columns and
/// cell contents; only this shared chrome (spacing, type, colors, dividers,
/// hover) lives here.
///
/// Two ways to use it:
/// - [DashboardTableCard] when the table IS the card (Student Directory).
/// - [DashboardTableHeader] + [DashboardTableRow]s (+ [DashboardTableEmptyState],
///   [DashboardTableFooter]) placed inside an existing card under its own
///   title/toolbar — pass `topBorder: true` to the header there.

abstract final class DashboardTableColors {
  static Color card(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF191A1F) : const Color(0xFFFFFFFF);
  static Color border(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF22242B) : const Color(0x0DE2E8F0);
  static Color primaryText(BuildContext context) =>
      context.isDarkMode ? const Color(0xFFF5F5F5) : const Color(0xFF1E293B);
  static Color secondaryText(BuildContext context) =>
      context.isDarkMode ? const Color(0xFFA1A1AA) : const Color(0xFF64748B);
  /// Column header labels — darker than [secondaryText] (slate-700, ~10:1
  /// on white vs ~4.8:1) so headers read clearly above the rows; brighter
  /// in dark mode for the same reason.
  static Color headerText(BuildContext context) =>
      context.isDarkMode ? const Color(0xFFE4E4E7) : const Color(0xFF334155);

  /// Column header row fill, so the header band reads as distinct from the
  /// rows beneath it: slate-200 (darker than the white card) in light mode.
  /// In dark mode it is a step *lighter* than the card instead — a darker
  /// fill would be the page background's black and the card's top edge
  /// would disappear into it.
  static Color headerBackground(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF2A2C35) : const Color(0xFFE2E8F0);
  static Color rowHover(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF22242B) : const Color(0xFFF8FAFC);

  /// A selected row (master-detail tables) — one step stronger than hover.
  static Color rowSelected(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF2A2D36) : const Color(0xFFEFF4FA);
  static const emptyStateIcon = Color(0xFFCBD5E1);
}

abstract final class DashboardTableMetrics {
  static const horizontalPadding = 16.0;
  static const headerVerticalPadding = 14.0;
  static const columnGap = 8.0;
  static const rowVerticalPadding = 12.0;
  static const rowMinHeight = 64.0;
}

/// Column header label style (UPPERCASE labels).
TextStyle dashboardTableHeaderStyle(BuildContext context) => GoogleFonts.poppins(
      fontSize: context.isMobileWidth ? 9 : 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.5,
      color: DashboardTableColors.headerText(context),
    );

/// An identifier cell (student ID, record ID, row number).
TextStyle dashboardTableIdStyle(
  BuildContext context, {
  Color? color,
  FontWeight? weight,
}) =>
    GoogleFonts.poppins(
      fontSize: context.isMobileWidth ? 10 : 12,
      fontWeight: weight ?? FontWeight.w600,
      letterSpacing: 0.2,
      color: color ?? DashboardTableColors.primaryText(context),
    );

/// A row's main label (a person's name, a title).
TextStyle dashboardTablePrimaryStyle(BuildContext context, {Color? color}) =>
    GoogleFonts.poppins(
      fontSize: context.isMobileWidth ? 11 : 13,
      fontWeight: FontWeight.w600,
      color: color ?? DashboardTableColors.primaryText(context),
    );

/// The muted second line under a primary label (an email, a code).
TextStyle dashboardTableSubStyle(BuildContext context, {Color? color}) =>
    GoogleFonts.poppins(
      fontSize: context.isMobileWidth ? 9 : 11,
      fontWeight: FontWeight.w400,
      color: color ?? DashboardTableColors.secondaryText(context),
    );

/// Any other cell text.
TextStyle dashboardTableBodyStyle(BuildContext context, {Color? color}) =>
    GoogleFonts.poppins(
      fontSize: context.isMobileWidth ? 10 : 12,
      color: color ?? DashboardTableColors.secondaryText(context),
    );

/// Small metadata text (timestamps, card numbers).
TextStyle dashboardTableMetaStyle(BuildContext context, {Color? color}) =>
    GoogleFonts.poppins(
      fontSize: context.isMobileWidth ? 9 : 11,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.15,
      color: color ?? DashboardTableColors.secondaryText(context),
    );

/// One column: a [flex] share of the row (default), or a fixed [width].
/// [compact] lets a narrow badge column stretch its cell instead of
/// shrink-wrapping.
class DashboardTableColumn {
  const DashboardTableColumn(
    this.label, {
    this.flex = 1,
    this.width,
    this.compact = false,
  });

  final String label;
  final int flex;
  final double? width;
  final bool compact;
}

/// Lays out [children] (one per column) with the table's column widths and
/// gaps — shared by the header and every row so they always line up.
class DashboardTableCells extends StatelessWidget {
  const DashboardTableCells({
    super.key,
    required this.columns,
    required this.children,
  });

  final List<DashboardTableColumn> columns;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    assert(columns.length == children.length,
        'DashboardTable: ${columns.length} columns but ${children.length} cells');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (var i = 0; i < columns.length; i++)
          _cell(columns[i], children[i], isLast: i == columns.length - 1),
      ],
    );
  }

  Widget _cell(DashboardTableColumn column, Widget child,
      {required bool isLast}) {
    final aligned = Padding(
      padding: EdgeInsets.only(
        right: isLast ? 0 : DashboardTableMetrics.columnGap,
      ),
      child: column.compact
          ? Align(alignment: Alignment.centerLeft, child: child)
          : Align(
              alignment: Alignment.centerLeft,
              widthFactor: 1,
              child: child,
            ),
    );
    final width = column.width;
    if (width != null) {
      return SizedBox(
        width: width + (isLast ? 0 : DashboardTableMetrics.columnGap),
        child: aligned,
      );
    }
    return Expanded(flex: column.flex, child: aligned);
  }
}

/// The column header row: card-colored, UPPERCASE muted labels, a divider
/// underneath (and above, with [topBorder], when it sits under a toolbar).
class DashboardTableHeader extends StatelessWidget {
  const DashboardTableHeader({
    super.key,
    required this.columns,
    this.topBorder = false,
    this.leading,
  });

  final List<DashboardTableColumn> columns;
  final bool topBorder;

  /// Optional widget before the first column (e.g. a select-all checkbox).
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final border = BorderSide(color: DashboardTableColors.border(context));
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: DashboardTableMetrics.horizontalPadding,
        vertical: DashboardTableMetrics.headerVerticalPadding,
      ),
      decoration: BoxDecoration(
        color: DashboardTableColors.headerBackground(context),
        border: Border(top: topBorder ? border : BorderSide.none, bottom: border),
      ),
      child: Row(
        children: [
          if (leading != null) leading!,
          Expanded(
            child: DashboardTableCells(
              columns: columns,
              children: [
                for (final column in columns)
                  Text(
                    column.label.toUpperCase(),
                    softWrap: false,
                    maxLines: 1,
                    overflow: TextOverflow.visible,
                    style: dashboardTableHeaderStyle(context),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One data row: 64px minimum height, a divider under it, and a hover
/// highlight. [onTap] makes the whole row clickable; [selected] marks the
/// row a detail panel is showing.
class DashboardTableRow extends StatefulWidget {
  const DashboardTableRow({
    super.key,
    required this.columns,
    required this.cells,
    this.showDivider = true,
    this.onTap,
    this.selected = false,
    this.leading,
  });

  final List<DashboardTableColumn> columns;
  final List<Widget> cells;
  final bool showDivider;
  final VoidCallback? onTap;
  final bool selected;

  /// Optional widget before the first column (e.g. a row checkbox); keep
  /// it the same width as the header's `leading`.
  final Widget? leading;

  @override
  State<DashboardTableRow> createState() => _DashboardTableRowState();
}

class _DashboardTableRowState extends State<DashboardTableRow> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    // The resting state is the hover color at zero alpha, NOT
    // Colors.transparent: that is transparent *black*, so the fade between
    // it and a near-white hover color passed through translucent grey and
    // flashed dark for ~120ms (on two rows at once when moving between
    // them). Same hue, alpha only, fades cleanly.
    final hover = DashboardTableColors.rowHover(context);
    final background = widget.selected
        ? DashboardTableColors.rowSelected(context)
        : _hovering
            ? hover
            : hover.withOpacity(0);

    Widget row = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: double.infinity,
      decoration: BoxDecoration(
        color: background,
        border: widget.showDivider
            ? Border(
                bottom: BorderSide(color: DashboardTableColors.border(context)),
              )
            : null,
      ),
      // The 64px minimum sits inside the divider (a row is 64 + 1).
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: DashboardTableMetrics.rowMinHeight,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: DashboardTableMetrics.horizontalPadding,
            vertical: DashboardTableMetrics.rowVerticalPadding,
          ),
          child: Row(
            children: [
              if (widget.leading != null) widget.leading!,
              Expanded(
                child: DashboardTableCells(
                  columns: widget.columns,
                  children: widget.cells,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (widget.onTap != null) {
      row = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: row,
      );
    }

    return MouseRegion(
      cursor: widget.onTap != null
          ? SystemMouseCursors.click
          : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: row,
    );
  }
}

/// Icon + message shown in place of rows when there are none.
class DashboardTableEmptyState extends StatelessWidget {
  const DashboardTableEmptyState({
    super.key,
    required this.message,
    this.icon = Icons.search_off_rounded,
  });

  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: DashboardTableColors.emptyStateIcon),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: context.isMobileWidth ? 12 : 14,
                fontWeight: FontWeight.w500,
                color: DashboardTableColors.secondaryText(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A divider then [child] (usually a `CardPaginationFooter`), pinned under
/// the rows inside the card.
class DashboardTableFooter extends StatelessWidget {
  const DashboardTableFooter({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Divider(height: 1, color: DashboardTableColors.border(context)),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: child,
        ),
      ],
    );
  }
}

/// For tables wider than their card: below [minWidth] the header and rows
/// scroll sideways together (with a visible scrollbar for mouse users)
/// instead of squeezing their columns.
class DashboardTableHorizontalScroll extends StatefulWidget {
  const DashboardTableHorizontalScroll({
    super.key,
    required this.minWidth,
    required this.child,
  });

  final double minWidth;
  final Widget child;

  @override
  State<DashboardTableHorizontalScroll> createState() =>
      _DashboardTableHorizontalScrollState();
}

class _DashboardTableHorizontalScrollState
    extends State<DashboardTableHorizontalScroll> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedWidth ||
            constraints.maxWidth >= widget.minWidth) {
          return widget.child;
        }
        return Scrollbar(
          controller: _controller,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _controller,
            scrollDirection: Axis.horizontal,
            child: SizedBox(width: widget.minWidth, child: widget.child),
          ),
        );
      },
    );
  }
}

/// A whole table as its own card: header, rows (or [empty] when there are
/// none), optional [footer]. Rows size to their content; with
/// [expandBody] the row list fills the card's bounded height and scrolls.
class DashboardTableCard extends StatelessWidget {
  const DashboardTableCard({
    super.key,
    required this.columns,
    required this.rows,
    this.empty,
    this.footer,
    this.expandBody = false,
    this.backgroundColor,
    this.borderColor,
  });

  final List<DashboardTableColumn> columns;
  final List<Widget> rows;
  final Widget? empty;
  final Widget? footer;
  final bool expandBody;
  final Color? backgroundColor;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final Widget body = rows.isEmpty
        ? (empty ?? const SizedBox.shrink())
        : ListView(
            shrinkWrap: !expandBody,
            physics:
                expandBody ? null : const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            children: rows,
          );
    return SizedBox(
      width: double.infinity,
      child: BentoCard(
        backgroundColor: backgroundColor ?? DashboardTableColors.card(context),
        borderColor: borderColor ?? DashboardTableColors.border(context),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DashboardTableHeader(columns: columns),
            expandBody ? Expanded(child: body) : body,
            if (footer != null) DashboardTableFooter(child: footer!),
          ],
        ),
      ),
    );
  }
}
