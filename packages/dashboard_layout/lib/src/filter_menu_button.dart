import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'responsive_sheet.dart';
import 'responsive_x.dart';

/// One selectable choice inside a [FilterMenuSection] or
/// [FilterMenuCheckboxSection].
class FilterMenuOption {
  const FilterMenuOption({required this.label, required this.value});

  final String label;
  final String value;
}

/// One single-select facet of a [FilterMenuButton]'s dropdown (e.g.
/// "Category" or "Status"), with its own independently-selected value.
/// `null` in [selectedValue] means "All" — no filter applied for this
/// facet.
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

/// One checkbox (multi-select) facet of a [FilterMenuButton]'s dropdown —
/// e.g. "Program" or "Section": any number of [options] can be checked at
/// once, and a row matches the facet if it matches *any* checked value (an
/// empty [selectedValues] means "All", same as a single-select facet's
/// `null`).
class FilterMenuCheckboxSection {
  const FilterMenuCheckboxSection({
    required this.title,
    required this.options,
    required this.selectedValues,
    required this.onChanged,
  });

  final String title;
  final List<FilterMenuOption> options;
  final Set<String> selectedValues;
  final ValueChanged<Set<String>> onChanged;
}

/// Shared "Filter" button + dropdown — replaces the decorative, non-wired
/// "Filter" pill that used to be copy-pasted per dashboard (same icon +
/// label, `onTap: () {}`, no menu at all). Same pill shape as before.
///
/// With [checkboxSections] null (the default), this opens a plain dropdown
/// listing each [sections] entry as an "All" option plus its own choices,
/// with a checkmark on whichever is active — picking one closes the menu,
/// same as before.
///
/// With [checkboxSections] set, tapping the pill instead opens a
/// [showResponsiveSheet] panel (bottom sheet on mobile, dialog on desktop)
/// listing every [sections] entry (as tap-to-select rows) followed by every
/// [checkboxSections] entry (as checkboxes) — a `PopupMenuButton` closes on
/// every tap by design, which is exactly wrong for ticking several
/// checkboxes in a row, so a persistent panel is used instead whenever
/// multiple selections need to stay open across taps.
///
/// [checkboxSections] is a *builder*, not a plain list, so a facet whose
/// own choices depend on another facet's current selection (e.g. this
/// app's Program -> Year -> Section hierarchy, where picking a Program
/// narrows which Years/Sections even show up) can stay current while the
/// panel is open: `showResponsiveSheet`'s dialog/bottom-sheet is a
/// separate Navigator route, not a child of the caller's widget tree, so
/// it never sees a plain list's later rebuilds — only calling the builder
/// again (done after every change made inside the panel) picks up
/// whatever the caller's own state looks like *now*.
class FilterMenuButton extends StatelessWidget {
  const FilterMenuButton({
    super.key,
    this.sections = const [],
    this.checkboxSections,
    required this.backgroundColor,
    required this.menuColor,
    required this.borderColor,
    required this.iconColor,
    required this.textColor,
    required this.mutedTextColor,
    required this.accentColor,
    this.width = 107,
    this.compact = false,
  });

  final List<FilterMenuSection> sections;
  final List<FilterMenuCheckboxSection> Function()? checkboxSections;

  /// The pill's own fill (matches the muted "field" background every other
  /// dashboard control already uses).
  final Color backgroundColor;

  /// The dropdown/sheet's own surface color.
  final Color menuColor;
  final Color borderColor;
  final Color iconColor;
  final Color textColor;
  final Color mutedTextColor;
  final Color accentColor;
  final double width;

  /// Icon-only 32px square (no "Filter" label) for narrow rows — e.g. a
  /// 320px master-detail side panel, where the full 107px pill leaves the
  /// search field beside it too cramped. The active-filter dot still shows.
  final bool compact;

  bool get _hasActiveFilter =>
      sections.any((s) => s.selectedValue != null) ||
      (checkboxSections?.call().any((s) => s.selectedValues.isNotEmpty) ??
          false);

  @override
  Widget build(BuildContext context) {
    final checkboxSections = this.checkboxSections;
    if (checkboxSections == null) {
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
            items.add(_sectionHeaderItem(section.title));
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
        child: _pillContent(context),
      );
    }

    final button = InkWell(
      onTap: () => _openCheckboxSheet(context, checkboxSections),
      borderRadius: BorderRadius.circular(10),
      child: _pillContent(context),
    );
    // Icon-only needs a tooltip; the labelled pill doesn't.
    return compact ? Tooltip(message: 'Filter', child: button) : button;
  }

  Future<void> _openCheckboxSheet(
    BuildContext context,
    List<FilterMenuCheckboxSection> Function() checkboxSectionsBuilder,
  ) {
    return showResponsiveSheet<void>(
      context: context,
      backgroundColor: menuColor,
      desktopMaxWidth: 380,
      builder: (sheetContext) => _FilterSheetContent(
        sections: sections,
        checkboxSectionsBuilder: checkboxSectionsBuilder,
        textColor: textColor,
        mutedTextColor: mutedTextColor,
        borderColor: borderColor,
        accentColor: accentColor,
      ),
    );
  }

  Widget _pillContent(BuildContext context) {
    return Container(
      height: 32,
      width: compact ? 32 : width,
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
              if (!compact) ...[
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
            ],
          ),
          if (_hasActiveFilter)
            Positioned(
              right: compact ? 4 : 8,
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
    );
  }

  PopupMenuItem<(int, String?)> _sectionHeaderItem(String title) {
    return PopupMenuItem<(int, String?)>(
      enabled: false,
      height: 28,
      child: Text(
        title.toUpperCase(),
        style: GoogleFonts.poppins(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
          color: mutedTextColor,
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

/// The persistent filter panel shown by [showResponsiveSheet] when a
/// [FilterMenuButton] has [checkboxSectionsBuilder] set. [sections]
/// (single-select) options never change dynamically, so their selection is
/// tracked locally same as before; [checkboxSectionsBuilder] is called
/// again after every change made in here — including a single-select tap,
/// in case a hypothetical caller ever makes a checkbox facet depend on one
/// — so this panel's checkbox rows always reflect the caller's *current*
/// truth (both which options are even offered, and which of them are
/// checked) instead of a stale snapshot from when the panel opened.
class _FilterSheetContent extends StatefulWidget {
  const _FilterSheetContent({
    required this.sections,
    required this.checkboxSectionsBuilder,
    required this.textColor,
    required this.mutedTextColor,
    required this.borderColor,
    required this.accentColor,
  });

  final List<FilterMenuSection> sections;
  final List<FilterMenuCheckboxSection> Function() checkboxSectionsBuilder;
  final Color textColor;
  final Color mutedTextColor;
  final Color borderColor;
  final Color accentColor;

  @override
  State<_FilterSheetContent> createState() => _FilterSheetContentState();
}

class _FilterSheetContentState extends State<_FilterSheetContent> {
  late final List<String?> _singleValues =
      [for (final s in widget.sections) s.selectedValue];
  late List<FilterMenuCheckboxSection> _checkboxSections =
      widget.checkboxSectionsBuilder();

  bool get _hasAnySelection =>
      _singleValues.any((v) => v != null) ||
      _checkboxSections.any((s) => s.selectedValues.isNotEmpty);

  /// Re-fetches the checkbox facets from the caller right after it was
  /// just told about a change (every `onChanged` below is called before
  /// this) — see the class doc comment.
  void _refresh() =>
      setState(() => _checkboxSections = widget.checkboxSectionsBuilder());

  void _clearAll() {
    for (var i = 0; i < _singleValues.length; i++) {
      widget.sections[i].onChanged(null);
    }
    for (final section in _checkboxSections) {
      section.onChanged(const {});
    }
    setState(() {
      for (var i = 0; i < _singleValues.length; i++) {
        _singleValues[i] = null;
      }
      _checkboxSections = widget.checkboxSectionsBuilder();
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  'Filter',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: widget.textColor,
                  ),
                ),
                const Spacer(),
                if (_hasAnySelection)
                  TextButton(
                    onPressed: _clearAll,
                    child: Text(
                      'Clear all',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: widget.accentColor,
                      ),
                    ),
                  ),
                IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: Icon(Icons.close_rounded, color: widget.mutedTextColor),
                  tooltip: 'Close',
                ),
              ],
            ),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < widget.sections.length; i++)
                      _singleSection(i),
                    for (var i = 0; i < _checkboxSections.length; i++)
                      _checkboxSection(i),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Text(
        title.toUpperCase(),
        style: GoogleFonts.poppins(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
          color: widget.mutedTextColor,
        ),
      ),
    );
  }

  Widget _singleSection(int index) {
    final section = widget.sections[index];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(section.title),
        _selectRow(
          label: 'All',
          isSelected: _singleValues[index] == null,
          onTap: () {
            section.onChanged(null);
            setState(() => _singleValues[index] = null);
            _refresh();
          },
        ),
        for (final option in section.options)
          _selectRow(
            label: option.label,
            isSelected: _singleValues[index] == option.value,
            onTap: () {
              section.onChanged(option.value);
              setState(() => _singleValues[index] = option.value);
              _refresh();
            },
          ),
      ],
    );
  }

  Widget _selectRow({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: isSelected ? widget.accentColor : widget.textColor,
                ),
              ),
            ),
            if (isSelected)
              Icon(Icons.check_rounded, size: 16, color: widget.accentColor),
          ],
        ),
      ),
    );
  }

  Widget _checkboxSection(int index) {
    final section = _checkboxSections[index];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(section.title),
        if (section.options.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              'None available',
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: widget.mutedTextColor,
              ),
            ),
          ),
        for (final option in section.options)
          _checkboxRow(
            label: option.label,
            isChecked: section.selectedValues.contains(option.value),
            onChanged: (checked) {
              final next = {...section.selectedValues};
              if (checked) {
                next.add(option.value);
              } else {
                next.remove(option.value);
              }
              section.onChanged(next);
              _refresh();
            },
          ),
      ],
    );
  }

  Widget _checkboxRow({
    required String label,
    required bool isChecked,
    required ValueChanged<bool> onChanged,
  }) {
    return InkWell(
      onTap: () => onChanged(!isChecked),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Checkbox(
              value: isChecked,
              onChanged: (v) => onChanged(v ?? false),
              activeColor: widget.accentColor,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: isChecked ? FontWeight.w600 : FontWeight.w400,
                  color: isChecked ? widget.accentColor : widget.textColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
