import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// The one accent every filter heading uses, whatever dashboard it is on.
const Color _bandAccent = Color(0xFF345892);
const Color _bandAccentOnDark = Color(0xFFA9C6FD);

bool _isDarkSurface(Color surface) => surface.computeLuminance() < 0.4;

/// Fill of a filter category / group heading ("Status", "Program",
/// "BS Information Technology", ...): a blue tint laid over the surface it sits on, deeper in
/// the dark theme so it still reads as a distinct strip.
Color filterLabelBandColor(Color surface) => Color.alphaBlend(
      _bandAccent.withOpacity(_isDarkSurface(surface) ? 0.35 : 0.22),
      surface,
    );

/// Text color of a filter heading on [surface] — also for anything placed in
/// its `trailing` slot (counts, "Clear all").
Color filterLabelTextColor(Color surface) =>
    _isDarkSurface(surface) ? _bandAccentOnDark : _bandAccent;

/// The single filter category / group heading used by every filter in the
/// app — Filter button popups and sheets, the section dropdown's year
/// headings, and Registrar's section pickers: a rounded blue-tinted strip
/// with a bold label and an optional [trailing] widget at its right edge.
///
/// [surface] is the color of the menu / card it sits on (the dark variant is
/// picked from it, so it is correct even inside a popup whose route sits
/// outside the page's own Theme).
class FilterLabelBand extends StatelessWidget {
  const FilterLabelBand({
    super.key,
    required this.label,
    required this.surface,
    this.trailing,
  }) : _menuItem = false;

  /// For a `DropdownMenuItem`'s child (non-selectable group heading): the
  /// strip extends out through the item's built-in 16px side padding to sit
  /// 4px from the menu's edges, vertically centred in the 48px row.
  const FilterLabelBand.menuItem({
    super.key,
    required this.label,
    required this.surface,
  })  : trailing = null,
        _menuItem = true;

  final String label;
  final Color surface;
  final Widget? trailing;
  final bool _menuItem;

  static const double _radius = 8;
  static const double _height = 34;
  static const EdgeInsets _padding = EdgeInsets.symmetric(horizontal: 12);

  @override
  Widget build(BuildContext context) {
    final textColor = filterLabelTextColor(surface);
    final text = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: GoogleFonts.poppins(
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
        color: textColor,
      ),
    );
    final decoration = BoxDecoration(
      color: filterLabelBandColor(surface),
      borderRadius: BorderRadius.circular(_radius),
    );

    if (_menuItem) {
      // Item content starts 16px in; the strip starts 4px in, so the label
      // keeps the same 12px inset it has everywhere else.
      return SizedBox(
        width: double.infinity,
        height: kMinInteractiveDimension,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: AlignmentDirectional.centerStart,
          children: [
            Positioned(
              left: -12,
              right: -12,
              top: (kMinInteractiveDimension - _height) / 2,
              height: _height,
              child: DecoratedBox(decoration: decoration),
            ),
            text,
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      height: _height,
      padding: _padding,
      alignment: AlignmentDirectional.centerStart,
      decoration: decoration,
      child: trailing == null
          ? text
          : Row(
              children: [
                Expanded(child: text),
                DefaultTextStyle.merge(
                  style: TextStyle(color: textColor),
                  child: trailing!,
                ),
              ],
            ),
    );
  }
}
