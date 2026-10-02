import 'package:flutter/material.dart';

import 'control_metrics.dart';

/// A filter/select dropdown that draws its own box at exactly
/// [kDashboardControlHeight], so it always lines up with the buttons beside
/// it (primary and secondary alike).
///
/// It deliberately does NOT use `DropdownButtonFormField`: that paints its
/// fill at the *natural* height of its content (font metrics + padding) and
/// only reserves the rest as empty space, so in some environments the visible
/// box came out ~8px shorter than the 34px it occupied. Here the fill, border
/// and label are laid out inside a fixed-height box, whatever the font.
class DashboardDropdown<T> extends StatelessWidget {
  const DashboardDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    required this.fillColor,
    required this.textStyle,
    this.hint,
    this.borderColor,
    this.iconColor,
    this.menuColor,
    this.borderRadius = 10,
    this.horizontalPadding = 12,
  });

  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;

  /// Pale fill of the box.
  final Color fillColor;

  /// Optional 1px border; none when null.
  final Color? borderColor;

  /// Style of the selected value (and of menu items, unless they set their own).
  final TextStyle textStyle;

  /// Shown while [value] is null.
  final Widget? hint;

  /// The arrow's color; defaults to the text color.
  final Color? iconColor;

  /// Background of the open menu; defaults to the surrounding theme's card.
  final Color? menuColor;

  final double borderRadius;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: kDashboardControlHeight,
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: fillColor,
        borderRadius: BorderRadius.circular(borderRadius),
        border: borderColor == null ? null : Border.all(color: borderColor!),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          isDense: true,
          iconSize: 18,
          icon: Icon(Icons.arrow_drop_down_rounded,
              size: 20, color: iconColor ?? textStyle.color),
          style: textStyle,
          dropdownColor: menuColor,
          borderRadius: BorderRadius.circular(borderRadius),
          hint: hint,
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }
}
