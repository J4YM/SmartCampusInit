import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'control_metrics.dart';
import 'filter_label_band.dart';
import 'responsive_x.dart';
import 'searchable_picker_list.dart';
import 'secondary_pill_button.dart';

/// One selectable choice inside a [FilterMenuSection].
class FilterMenuOption {
  const FilterMenuOption({required this.label, required this.value});

  final String label;
  final String value;
}

/// One single-select facet of a [FilterMenuButton] (e.g. "Status" or
/// "Risk Level"), with its own independently-selected value. `null` in
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

/// The Section facet of a [FilterMenuButton]: one section at a time, picked
/// from the full list of sections grouped under "1st Year" / "2nd Year" / ...
/// headings — the same list as Registrar's Change Section. `null`
/// [selectedId] means "All sections".
class FilterSectionPicker {
  const FilterSectionPicker({
    required this.entries,
    required this.selectedId,
    required this.onChanged,
  });

  /// Usually built with [PickerEntry.section]; [PickerEntry.id] is what
  /// [onChanged] receives.
  final List<PickerEntry> entries;
  final String? selectedId;
  final ValueChanged<String?> onChanged;
}

/// The app's one Filter button. Tapping it opens the shared filter popup —
/// the same layout as Registrar's Change Section window: a title, a search
/// box, and one list of radio rows under [FilterLabelBand] headings (one
/// heading per [sections] facet, then one per year for the
/// [sectionFilter]'s sections), with "Clear all" / "Done" at the bottom.
///
/// Picks apply immediately, so the table behind updates while the popup is
/// open. The popup tracks its own copy of every selection because it is a
/// separate route and never sees the caller's later rebuilds.
class FilterMenuButton extends StatelessWidget {
  const FilterMenuButton({
    super.key,
    this.sections = const [],
    this.sectionFilter,
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
  final FilterSectionPicker? sectionFilter;

  /// The pill's own fill (matches the muted "field" background every other
  /// dashboard control already uses) — also the popup's search box fill.
  final Color backgroundColor;

  /// The popup's own surface color.
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
      sectionFilter?.selectedId != null;

  PickerPalette get _palette => PickerPalette(
        surface: menuColor,
        field: backgroundColor,
        border: borderColor,
        text: textColor,
        muted: mutedTextColor,
        placeholder: iconColor,
        accent: accentColor,
      );

  @override
  Widget build(BuildContext context) {
    final button = InkWell(
      onTap: () => showDialog<void>(
        context: context,
        builder: (_) => _FilterDialog(
          sections: sections,
          sectionFilter: sectionFilter,
          palette: _palette,
        ),
      ),
      borderRadius: BorderRadius.circular(10),
      child: _pillContent(context),
    );
    // Icon-only needs a tooltip; the labelled pill doesn't.
    return compact ? Tooltip(message: 'Filter', child: button) : button;
  }

  Widget _pillContent(BuildContext context) {
    return Container(
      height: kDashboardControlHeight,
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
}

class _FilterDialog extends StatefulWidget {
  const _FilterDialog({
    required this.sections,
    required this.sectionFilter,
    required this.palette,
  });

  final List<FilterMenuSection> sections;
  final FilterSectionPicker? sectionFilter;
  final PickerPalette palette;

  @override
  State<_FilterDialog> createState() => _FilterDialogState();
}

class _FilterDialogState extends State<_FilterDialog> {
  final _search = TextEditingController();
  String _query = '';
  late final List<String?> _values = [
    for (final s in widget.sections) s.selectedValue,
  ];
  late String? _sectionId = widget.sectionFilter?.selectedId;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool get _hasAnySelection =>
      _values.any((v) => v != null) || _sectionId != null;

  void _setValue(int index, String? value) {
    widget.sections[index].onChanged(value);
    setState(() => _values[index] = value);
  }

  void _setSection(String? id) {
    widget.sectionFilter?.onChanged(id);
    setState(() => _sectionId = id);
  }

  void _clearAll() {
    for (var i = 0; i < _values.length; i++) {
      if (_values[i] != null) _setValue(i, null);
    }
    if (_sectionId != null) _setSection(null);
  }

  Widget _heading(String label, {int? count, String noun = ''}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: FilterLabelBand(
        label: label,
        surface: widget.palette.surface,
        trailing: count == null
            ? null
            : Text(
                '$count $noun${count == 1 ? '' : 's'}',
                style: GoogleFonts.poppins(
                    fontSize: 11, fontWeight: FontWeight.w500),
              ),
      ),
    );
  }

  Widget _row(PickerEntry entry, bool selected, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: PickerOptionRow(
        entry: entry,
        palette: widget.palette,
        selected: selected,
        onTap: onTap,
      ),
    );
  }

  List<Widget> _items() {
    final items = <Widget>[];
    void gap() {
      if (items.isNotEmpty) items.add(const SizedBox(height: 8));
    }

    // Single-select facets: a heading, "All", then each option.
    for (var i = 0; i < widget.sections.length; i++) {
      final section = widget.sections[i];
      final rows = <Widget>[
        for (final (value, label) in [
          (null, 'All'),
          for (final o in section.options) (o.value, o.label),
        ])
          if (PickerEntry(id: '$value', title: label).matches(_query))
            _row(
              PickerEntry(id: '$value', title: label),
              _values[i] == value,
              () => _setValue(i, value),
            ),
      ];
      if (rows.isEmpty) continue;
      gap();
      items
        ..add(_heading(section.title))
        ..addAll(rows);
    }

    // Section facet: "All sections", then the year-grouped section list.
    final sectionFilter = widget.sectionFilter;
    if (sectionFilter != null) {
      const all = PickerEntry(id: '', title: 'All sections');
      if (all.matches(_query)) {
        gap();
        items.add(_row(all, _sectionId == null, () => _setSection(null)));
      }
      final visible = sectionFilter.entries
          .where((e) => e.matches(_query))
          .toList()
        ..sort((a, b) {
          final byYear = (a.year ?? 99).compareTo(b.year ?? 99);
          if (byYear != 0) return byYear;
          final rank = kPickerPrograms.indexOf(a.program ?? '');
          final rankB = kPickerPrograms.indexOf(b.program ?? '');
          final byProgram = (rank == -1 ? 99 : rank)
              .compareTo(rankB == -1 ? 99 : rankB);
          if (byProgram != 0) return byProgram;
          return a.title.compareTo(b.title);
        });
      int? year;
      var firstGroup = true;
      for (final e in visible) {
        if (firstGroup || e.year != year) {
          year = e.year;
          firstGroup = false;
          gap();
          items.add(_heading(
            e.year == null ? 'Other' : '${pickerYearLabel(e.year!)} Year',
            count: visible.where((v) => v.year == e.year).length,
            noun: 'section',
          ));
        }
        items.add(_row(e, _sectionId == e.id, () => _setSection(e.id)));
      }
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final items = _items();
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide.none,
    );
    final listHeight =
        (MediaQuery.sizeOf(context).height * 0.45).clamp(180.0, 420.0);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: 520,
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: p.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Filter',
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: p.text,
                      ),
                    ),
                  ),
                  Tooltip(
                    message: 'Close',
                    child: InkWell(
                      onTap: () => Navigator.of(context).pop(),
                      borderRadius: BorderRadius.circular(20),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(Icons.close_rounded,
                            size: 22, color: p.text),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: kDashboardControlHeight,
                child: TextField(
                  expands: true,
                  maxLines: null,
                  minLines: null,
                  textAlignVertical: TextAlignVertical.center,
                  controller: _search,
                  onChanged: (v) => setState(() => _query = v),
                  style: GoogleFonts.poppins(fontSize: 13, color: p.text),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: widget.sectionFilter != null
                        ? 'Search sections'
                        : 'Search filters',
                    hintStyle:
                        GoogleFonts.poppins(fontSize: 13, color: p.placeholder),
                    prefixIcon: Icon(Icons.search_rounded,
                        size: 20, color: p.placeholder),
                    filled: true,
                    fillColor: p.field,
                    contentPadding: EdgeInsets.zero,
                    border: border,
                    enabledBorder: border,
                    focusedBorder: border,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: SizedBox(
                  height: listHeight,
                  child: items.isEmpty
                      ? Center(
                          child: Text(
                            'No results match your search.',
                            style: GoogleFonts.poppins(
                                fontSize: 12.5, color: p.muted),
                          ),
                        )
                      : ListView(padding: EdgeInsets.zero, children: items),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  SecondaryPillButton(
                    label: 'Clear all',
                    // The popup is its own route, outside the page Theme.
                    isDarkMode: p.surface.computeLuminance() < 0.4,
                    onTap: _hasAnySelection ? _clearAll : null,
                  ),
                  const SizedBox(width: 10),
                  _FooterButton(
                    label: 'Done',
                    background: p.accent,
                    foreground: Colors.white,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Same 34px pills as Change Section's Cancel / Save.
class _FooterButton extends StatelessWidget {
  const _FooterButton({
    required this.label,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return Material(
      color: disabled ? background.withOpacity(0.5) : background,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          constraints:
              const BoxConstraints(minHeight: kDashboardControlHeight),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: disabled ? foreground.withOpacity(0.6) : foreground,
            ),
          ),
        ),
      ),
    );
  }
}
