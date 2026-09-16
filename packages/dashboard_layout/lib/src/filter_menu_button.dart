import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'responsive_x.dart';

/// One selectable choice inside a [FilterMenuSection].
class FilterMenuOption {
  const FilterMenuOption({required this.label, required this.value});

  final String label;
  final String value;
}

/// One facet of a [FilterMenuButton]'s dropdown (e.g. "Category" or
/// "Status"), with its own independently-selected value. `null` in
/// [selectedValue] means "All" — no filter applied for this facet.
class FilterMenuSection {
  const FilterMenuSection({
    required this.title,
    required this.options,
    required this.selectedValue,
    required this.onChanged,
  });

  final String title;
  final List<FilterMenuOption> options;
  final String? selectedValue;
  final ValueChanged<String?> onChanged;
}

/// Shared "Filter" button + dropdown — replaces the decorative, non-wired
/// "Filter" pill that used to be copy-pasted per dashboard (same icon +
/// label, `onTap: () {}`, no menu at all). Same pill shape as before; now
/// opens a real dropdown listing each [FilterMenuSection] as an "All"
/// option plus its own choices, with a checkmark on whichever is active.
///
/// Colors are passed in explicitly rather than read via `context.isDarkMode`
/// internally: `PopupMenuButton`'s menu renders through the root
/// Navigator's Overlay, outside whatever local Theme the caller's dashboard
/// page builds around itself, so resolving colors from the *caller's*
/// context before construction (as every call site does) is what keeps the
/// menu themed correctly instead of falling back to the app's ambient
/// theme — the same pattern every other dialog/popover in this app follows.
class FilterMenuButton extends StatelessWidget {
  const FilterMenuButton({
    super.key,
    required this.sections,
    required this.backgroundColor,
    required this.menuColor,
    required this.borderColor,
    required this.iconColor,
    required this.textColor,
    required this.mutedTextColor,
    required this.accentColor,
    this.width = 107,
  });

  final List<FilterMenuSection> sections;

  /// The pill's own fill (matches the muted "field" background every other
  /// dashboard control already uses).
  final Color backgroundColor;

  /// The dropdown menu's own surface color.
  final Color menuColor;
  final Color borderColor;
  final Color iconColor;
  final Color textColor;
  final Color mutedTextColor;
  final Color accentColor;
  final double width;

  bool get _hasActiveFilter => sections.any((s) => s.selectedValue != null);

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<(int, String?)>(
      tooltip: 'Filter',
      color: menuColor,
      surfaceTintColor: Colors.transparent,
      elevation: 6,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderColor),
      ),
      offset: const Offset(0, 8),
      onSelected: (result) {
        final (sectionIndex, value) = result;
        sections[sectionIndex].onChanged(value);
      },
      itemBuilder: (itemContext) {
        final items = <PopupMenuEntry<(int, String?)>>[];
        for (var i = 0; i < sections.length; i++) {
          if (i > 0) items.add(const PopupMenuDivider(height: 1));
          final section = sections[i];
          items.add(
            PopupMenuItem<(int, String?)>(
              enabled: false,
              height: 28,
              child: Text(
                section.title.toUpperCase(),
                style: GoogleFonts.poppins(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  color: mutedTextColor,
                ),
              ),
            ),
          );
          items.add(_optionItem(
            sectionIndex: i,
            value: null,
            label: 'All',
            isSelected: section.selectedValue == null,
          ));
          for (final option in section.options) {
            items.add(_optionItem(
              sectionIndex: i,
              value: option.value,
              label: option.label,
              isSelected: section.selectedValue == option.value,
            ));
          }
        }
        return items;
      },
      child: Container(
        height: 32,
        width: width,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.filter_list_rounded, size: 16, color: iconColor),
                const SizedBox(width: 6),
                Text(
                  'Filter',
                  style: GoogleFonts.poppins(
                    fontSize: context.isMobileWidth ? 11 : 13,
                    fontWeight: FontWeight.w400,
                    color: iconColor,
                  ),
                ),
              ],
            ),
            if (_hasActiveFilter)
              Positioned(
                right: 8,
                top: 3,
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: accentColor,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<(int, String?)> _optionItem({
    required int sectionIndex,
    required String? value,
    required String label,
    required bool isSelected,
  }) {
    return PopupMenuItem<(int, String?)>(
      value: (sectionIndex, value),
      height: 36,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected ? accentColor : textColor,
              ),
            ),
          ),
          if (isSelected) ...[
            const SizedBox(width: 8),
            Icon(Icons.check_rounded, size: 16, color: accentColor),
          ],
        ],
      ),
    );
  }
}
