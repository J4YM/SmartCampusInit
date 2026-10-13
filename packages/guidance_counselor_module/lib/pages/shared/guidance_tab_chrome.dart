import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';

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

/// The shared 34px search field, in the Guidance palette.
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
  Widget build(BuildContext context) => DashboardSearchField(
        controller: controller,
        onChanged: onChanged,
        hint: hint,
        fillColor: GuidanceTabColors.searchFill(context),
        textColor: GuidanceTabColors.primaryText(context),
        hintColor: GuidanceTabColors.mutedIcon(context),
      );
}

/// The shared titled table card, in the Guidance palette.
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
  final Widget subtitle;
  final Widget? toolbar;
  final List<DashboardTableColumn> columns;
  final List<Widget> rows;
  final Widget empty;
  final Widget? footer;

  /// The muted subtitle text style.
  static TextStyle subtitleStyle(BuildContext context) =>
      TitledTableCard.subtitleStyle(context,
          color: GuidanceTabColors.secondaryText(context));

  @override
  Widget build(BuildContext context) => TitledTableCard(
        title: title,
        subtitle: subtitle,
        toolbar: toolbar,
        columns: columns,
        rows: rows,
        empty: empty,
        footer: footer,
        backgroundColor: GuidanceTabColors.card(context),
        borderColor: GuidanceTabColors.cardBorder(context),
        titleColor: GuidanceTabColors.primaryText(context),
      );
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
  Widget build(BuildContext context) => DashboardRowIconButton(
        icon: icon,
        tooltip: tooltip,
        onPressed: onPressed,
        color: color,
      );
}
