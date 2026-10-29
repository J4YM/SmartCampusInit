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
    this.collapsed = false,
    this.onToggleCollapsed,
    this.headerKey,
  });

  final String title;

  /// Makes the card collapsible: a chevron joins the title and tapping the
  /// header calls this. While [collapsed] only the header shows (no toolbar,
  /// table or footer). Null (the default) is a card that never collapses.
  final VoidCallback? onToggleCollapsed;
  final bool collapsed;

  /// The key of the tappable header, for tests.
  final Key? headerKey;

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

        // A card that fills a bounded height is never collapsible (its body
        // is what scrolls); collapsing is for cards stacked on a page.
        final toggle = bounded ? null : onToggleCollapsed;
        final isCollapsed = toggle != null && collapsed;
        final titleBlock = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: dashboardCardTitleStyle(
                context,
                color: titleColor ?? DashboardTableColors.primaryText(context),
              ),
            ),
            const SizedBox(height: 4),
            subtitle,
          ],
        );
        Widget header = AnimatedPadding(
          duration: kTitledTableCardCollapseDuration,
          curve: Curves.easeInOutCubic,
          padding: EdgeInsets.fromLTRB(29, 24, 29, isCollapsed ? 24 : 0),
          child: toggle == null
              ? titleBlock
              : Row(
                  children: [
                    Expanded(child: titleBlock),
                    const SizedBox(width: 12),
                    AnimatedRotation(
                      turns: isCollapsed ? 0 : 0.5,
                      duration: kTitledTableCardCollapseDuration,
                      curve: Curves.easeInOutCubic,
                      child: Icon(
                        Icons.expand_more_rounded,
                        size: 26,
                        color: DashboardTableColors.secondaryText(context),
                      ),
                    ),
                  ],
                ),
        );
        if (toggle != null) {
          header = Semantics(
            button: true,
            expanded: !isCollapsed,
            child: Tooltip(
              message: isCollapsed ? 'Expand' : 'Collapse',
              child: InkWell(
                key: headerKey,
                onTap: toggle,
                child: header,
              ),
            ),
          );
        }

        // Everything under the header: toolbar, column header + rows, footer.
        final content = <Widget>[
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
        ];

        return BentoCard(
          backgroundColor: backgroundColor ?? DashboardTableColors.card(context),
          borderColor: borderColor ?? DashboardTableColors.border(context),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: bounded ? MainAxisSize.max : MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              if (toggle != null)
                // Slides the table up under the header (and back down),
                // fading as it goes; fully folded it is not built at all.
                _CollapsibleSection(
                  open: !isCollapsed,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: content,
                  ),
                )
              else
                ...content,
            ],
          ),
        );
      },
    );
  }
}

/// How long a collapsible card takes to fold or open.
const Duration kTitledTableCardCollapseDuration = Duration(milliseconds: 260);

/// Animates [child] open and shut: its height eases between 0 and its natural
/// height while it fades, then, once fully shut, it is removed from the tree
/// so a folded card costs nothing. Starts in the state [open] says.
class _CollapsibleSection extends StatefulWidget {
  const _CollapsibleSection({required this.open, required this.child});

  final bool open;
  final Widget child;

  @override
  State<_CollapsibleSection> createState() => _CollapsibleSectionState();
}

class _CollapsibleSectionState extends State<_CollapsibleSection>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: kTitledTableCardCollapseDuration,
    value: widget.open ? 1 : 0,
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOutCubic,
  );

  @override
  void didUpdateWidget(_CollapsibleSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.open != oldWidget.open) {
      widget.open ? _controller.forward() : _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        if (_controller.isDismissed) return const SizedBox.shrink();
        return ClipRect(
          child: SizeTransition(
            sizeFactor: _curve,
            axisAlignment: -1,
            child: FadeTransition(opacity: _curve, child: child),
          ),
        );
      },
      child: widget.child,
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
