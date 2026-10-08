import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_popup.dart';
import 'control_metrics.dart';
import 'filter_label_band.dart';
import 'nav_hover_underline.dart' show kSubNavActiveDarkColor;
import 'section_facets.dart';

/// Program order every section picker uses. Any other program that shows up
/// in the data (e.g. "BSCpE") sorts after these.
const List<String> kPickerPrograms = ['BSIT', 'BSTM', 'BSHM', 'BSBA'];

/// What a picker shows for each program — the full name, never the acronym.
/// A program not listed here is shown as-is.
const Map<String, String> kPickerProgramNames = {
  'BSIT': 'BS Information Technology',
  'BSTM': 'BS Tourism Management',
  'BSHM': 'BS Hospitality Management',
  'BSBA': 'BS Business Administration',
};

String pickerProgramLabel(String program) =>
    kPickerProgramNames[program] ?? program;

/// One key per program, whichever way the data spells it. `sections.program`
/// holds the full name ("BS Information Technology") on some rows while a
/// section name only gives the acronym ("BSIT-3B"); both must land under the
/// same program, so full names are folded back to their acronym key.
String? canonicalProgramKey(String? raw) {
  final value = raw?.trim();
  if (value == null || value.isEmpty) return null;
  final squashed = value.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  if (squashed.contains('INFORMATIONTECHNOLOGY')) return 'BSIT';
  if (squashed.contains('TOURISMMANAGEMENT')) return 'BSTM';
  if (squashed.contains('HOSPITALITYMANAGEMENT')) return 'BSHM';
  if (squashed.contains('BUSINESSADMINISTRATION')) return 'BSBA';
  return value.toUpperCase();
}

/// 1 -> '1st', 2 -> '2nd', 3 -> '3rd', n -> 'nth'.
String pickerYearLabel(int year) => switch (year) {
      1 => '1st',
      2 => '2nd',
      3 => '3rd',
      _ => '${year}th',
    };

/// The heading a section sits under in every grouped section list: its
/// program's full name ("BS Information Technology"), or "Other" when the
/// program is unknown.
String pickerGroupLabel(PickerEntry e) =>
    e.program == null ? 'Other' : pickerProgramLabel(e.program!);

/// The order of every grouped section list: by program (the known programs in
/// [kPickerPrograms] order, any other after them alphabetically), then by year
/// (1st to 4th), then by name — so each program's heading is followed by its
/// 1st-year sections down to its 4th-year ones.
int comparePickerEntries(PickerEntry a, PickerEntry b) {
  int rank(String? p) {
    final i = kPickerPrograms.indexOf(p ?? '');
    return i == -1 ? kPickerPrograms.length : i;
  }

  final byRank = rank(a.program).compareTo(rank(b.program));
  if (byRank != 0) return byRank;
  final byProgram = (a.program ?? '~').compareTo(b.program ?? '~');
  if (byProgram != 0) return byProgram;
  final byYear = (a.year ?? 99).compareTo(b.year ?? 99);
  if (byYear != 0) return byYear;
  return a.title.compareTo(b.title);
}

/// The colors a [SearchablePickerList] draws with — each dashboard passes
/// its own palette, the layout itself is identical everywhere.
class PickerPalette {
  const PickerPalette({
    required this.surface,
    required this.field,
    required this.border,
    required this.text,
    required this.muted,
    required this.placeholder,
    this.accent = const Color(0xFF345892),
  });

  /// The card / sheet / menu the list sits on.
  final Color surface;

  /// Search box fill and badge fill.
  final Color field;
  final Color border;
  final Color text;
  final Color muted;
  final Color placeholder;
  final Color accent;
}

/// One selectable row of a [SearchablePickerList].
class PickerEntry {
  const PickerEntry({
    required this.id,
    required this.title,
    this.subtitle,
    this.program,
    this.year,
    this.badge,
    this.enabled = true,
  });

  /// A section, from its name ("BSIT-3B", "BSHM 1A") plus optional explicit
  /// program/year columns. Grouped lists put the program in the heading, so
  /// the row's subtitle is its year ("3rd Year") — with an explicit [subtitle]
  /// (e.g. a professor's name) it follows the year: "3rd Year · Prof. Reyes".
  factory PickerEntry.section({
    required String id,
    required String name,
    String? program,
    int? yearLevel,
    String? subtitle,
    String? badge,
    bool enabled = true,
  }) {
    final key = canonicalProgramKey(
      program != null && program.trim().isNotEmpty
          ? program
          : sectionProgramCode(name),
    );
    final year = yearLevel != null && yearLevel > 0
        ? yearLevel
        : int.tryParse(sectionYearDigit(name) ?? '');
    final yearText = year == null ? null : '${pickerYearLabel(year)} Year';
    return PickerEntry(
      id: id,
      title: name,
      subtitle: subtitle == null || subtitle.trim().isEmpty
          ? yearText
          : (yearText == null ? subtitle : '$yearText · $subtitle'),
      program: key,
      year: year,
      badge: badge,
      enabled: enabled,
    );
  }

  final String id;
  final String title;
  final String? subtitle;

  /// Canonical program key (e.g. "BSIT") — sort order and search only.
  final String? program;
  final int? year;

  /// Small tag at the row's right edge (e.g. "Current").
  final String? badge;

  /// A disabled row is shown but can't be picked.
  final bool enabled;

  /// Lower-cased text the search box matches against — includes the year
  /// as "3rd year" so typing "bsit 3rd" narrows to that cohort.
  /// True when every whitespace-separated word of [query] occurs in the
  /// row's title, subtitle, program or "Nth year" (case-insensitive).
  bool matches(String query) {
    final hay = _haystack;
    return query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .every(hay.contains);
  }

  String get _haystack => [
        title,
        if (subtitle != null) subtitle!,
        if (program != null) ...[program!, pickerProgramLabel(program!)],
        if (year != null) '${pickerYearLabel(year!)} year',
      ].join(' ').toLowerCase();
}

/// The app's one section-picking layout (first built for Registrar's Change
/// Section): a search box above a list that, with [groupByProgram], sits under
/// a [FilterLabelBand] heading per program ("BS Information Technology", ...)
/// with the program's section count at its right, each program's sections
/// running 1st year to 4th. No Filter button — search narrows it.
///
/// Single-select by default ([selectedId] + [onSelected], radio rows);
/// multi-select with [selectedIds] + [onToggled] (checkbox rows), as used for
/// the Section facet inside the Filter sheet.
///
/// With [scrollable] (default) it must get a bounded height (a `Flexible`
/// inside a dialog's `Column`) and scrolls its own list; with it false the
/// rows are laid out in full for a parent that already scrolls.
class SearchablePickerList extends StatefulWidget {
  const SearchablePickerList({
    super.key,
    required this.entries,
    required this.palette,
    this.selectedId,
    this.onSelected,
    this.selectedIds,
    this.onToggled,
    this.searchHint = 'Search',
    this.groupByProgram = false,
    this.groupNoun = 'section',
    this.emptyMessage = 'Nothing to show.',
    this.scrollable = true,
  }) : assert((onSelected != null) != (onToggled != null),
            'Pass onSelected (single) or onToggled (multi), not both');

  final List<PickerEntry> entries;
  final PickerPalette palette;

  final String? selectedId;
  final ValueChanged<String>? onSelected;

  final Set<String>? selectedIds;
  final void Function(String id, bool selected)? onToggled;

  final String searchHint;
  final bool groupByProgram;

  /// Singular noun for the heading counts ("3 sections").
  final String groupNoun;
  final String emptyMessage;
  final bool scrollable;

  @override
  State<SearchablePickerList> createState() => _SearchablePickerListState();
}

class _SearchablePickerListState extends State<SearchablePickerList> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool get _multi => widget.onToggled != null;

  bool _isSelected(PickerEntry e) => _multi
      ? (widget.selectedIds?.contains(e.id) ?? false)
      : e.id == widget.selectedId;

  List<PickerEntry> get _visible {
    final tokens = _query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
    // Program first, then year: each program's rows are contiguous (one
    // heading per program when grouped) and run 1st year to 4th.
    return widget.entries
        .where((e) => tokens.every(e._haystack.contains))
        .toList()
      ..sort(comparePickerEntries);
  }

  List<Widget> _items(List<PickerEntry> visible) {
    Widget row(PickerEntry e) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: PickerOptionRow(
            entry: e,
            palette: widget.palette,
            selected: _isSelected(e),
            multi: _multi,
            onTap: () {
              if (_multi) {
                widget.onToggled!(e.id, !_isSelected(e));
              } else {
                widget.onSelected!(e.id);
              }
            },
          ),
        );

    if (!widget.groupByProgram) return [for (final e in visible) row(e)];

    final items = <Widget>[];
    String? currentProgram;
    var first = true;
    for (final e in visible) {
      if (first || e.program != currentProgram) {
        currentProgram = e.program;
        final count = visible.where((v) => v.program == e.program).length;
        items.add(Padding(
          padding: EdgeInsets.only(top: first ? 0 : 8, bottom: 6),
          child: FilterLabelBand(
            label: pickerGroupLabel(e),
            surface: widget.palette.surface,
            trailing: Text(
              '$count ${widget.groupNoun}${count == 1 ? '' : 's'}',
              style: GoogleFonts.poppins(
                  fontSize: 11, fontWeight: FontWeight.w500),
            ),
          ),
        ));
        first = false;
      }
      items.add(row(e));
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final visible = _visible;
    final listHeight =
        (MediaQuery.sizeOf(context).height * 0.36).clamp(150.0, 320.0);

    final Widget body = visible.isEmpty
        ? Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                widget.entries.isEmpty
                    ? widget.emptyMessage
                    : 'No results match your search.',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(fontSize: 12.5, color: p.muted),
              ),
            ),
          )
        : widget.scrollable
            ? ListView(padding: EdgeInsets.zero, children: _items(visible))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _items(visible),
              );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PickerSearchField(
          controller: _searchController,
          hintText: widget.searchHint,
          palette: p,
          onChanged: (v) => setState(() => _query = v),
        ),
        const SizedBox(height: 10),
        Text(
          visible.length == widget.entries.length
              ? '${visible.length} ${visible.length == 1 ? 'result' : 'results'}'
              : '${visible.length} of ${widget.entries.length} shown',
          style: GoogleFonts.poppins(fontSize: 11.5, color: p.muted),
        ),
        const SizedBox(height: 6),
        if (widget.scrollable)
          Flexible(child: SizedBox(height: listHeight, child: body))
        else
          body,
      ],
    );
  }
}

class _PickerSearchField extends StatelessWidget {
  const _PickerSearchField({
    required this.controller,
    required this.hintText,
    required this.palette,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String hintText;
  final PickerPalette palette;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide.none,
    );
    return SizedBox(
      height: kDashboardControlHeight,
      child: TextField(
        expands: true,
        maxLines: null,
        minLines: null,
        textAlignVertical: TextAlignVertical.center,
        controller: controller,
        onChanged: onChanged,
        style: GoogleFonts.poppins(fontSize: 13, color: palette.text),
        decoration: InputDecoration(
          isDense: true,
          hintText: hintText,
          hintStyle: GoogleFonts.poppins(fontSize: 13, color: palette.placeholder),
          prefixIcon:
              Icon(Icons.search_rounded, size: 20, color: palette.placeholder),
          filled: true,
          fillColor: palette.field,
          contentPadding: EdgeInsets.zero,
          border: border,
          enabledBorder: border,
          focusedBorder: border,
        ),
      ),
    );
  }
}

/// One bordered radio / checkbox row of the shared picker layout.
class PickerOptionRow extends StatelessWidget {
  const PickerOptionRow({
    super.key,
    required this.entry,
    required this.palette,
    required this.selected,
    this.multi = false,
    required this.onTap,
  });

  final PickerEntry entry;
  final PickerPalette palette;
  final bool selected;
  final bool multi;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final enabled = entry.enabled;
    final icon = multi
        ? (selected
            ? Icons.check_box_rounded
            : Icons.check_box_outline_blank_rounded)
        : (selected
            ? Icons.radio_button_checked_rounded
            : Icons.radio_button_unchecked_rounded);
    return Material(
      color: selected ? p.accent.withOpacity(0.14) : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: selected ? p.accent : p.border),
      ),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            children: [
              Icon(icon,
                  size: 18,
                  color: !selected
                      ? p.placeholder
                      // A tick-box is light blue (#A9C6FD) in dark mode, like
                      // every checkbox; the radio dot keeps the palette accent.
                      : multi && p.surface.computeLuminance() < 0.4
                          ? kSubNavActiveDarkColor
                          : p.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Opacity(
                  opacity: enabled ? 1.0 : 0.55,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: p.text,
                        ),
                      ),
                      if (entry.subtitle != null)
                        Text(
                          entry.subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              GoogleFonts.poppins(fontSize: 11.5, color: p.muted),
                        ),
                    ],
                  ),
                ),
              ),
              if (entry.badge != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: p.field,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    entry.badge!,
                    style: GoogleFonts.poppins(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: p.muted,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Opens the shared section picker in a dialog — search box + program-grouped
/// list, the same layout as Registrar's Change Section — and returns the
/// picked section's id (null if dismissed). Picking a row closes it.
Future<String?> showSectionPickerDialog({
  required BuildContext context,
  required List<PickerEntry> entries,
  required PickerPalette palette,
  String title = 'Select Section',
  String? selectedId,
}) {
  return showAppPopup<String>(
    context: context,
    builder: (dialogContext) => AppPopup(
      title: title,
      width: 520,
      // The list scrolls itself, so it needs a bounded height rather than a
      // scroll view around it.
      scrollBody: false,
      body: SearchablePickerList(
        entries: entries,
        palette: palette,
        searchHint: 'Search sections',
        emptyMessage: 'No sections available.',
        groupByProgram: true,
        selectedId: selectedId,
        onSelected: (id) => Navigator.of(dialogContext).pop(id),
      ),
    ),
  );
}

/// A 34px field-styled button showing the current section (or a prompt);
/// tapping it opens [showSectionPickerDialog]. Stands in for a section
/// dropdown wherever one used to be.
class SectionPickerField extends StatelessWidget {
  const SectionPickerField({
    super.key,
    required this.entries,
    required this.palette,
    required this.selectedId,
    required this.onChanged,
    this.placeholder = 'Select a section',
  });

  final List<PickerEntry> entries;
  final PickerPalette palette;
  final String? selectedId;

  /// Null disables the field.
  final ValueChanged<String>? onChanged;
  final String placeholder;

  @override
  Widget build(BuildContext context) {
    String? selectedName;
    for (final e in entries) {
      if (e.id == selectedId) selectedName = e.title;
    }
    final onChanged = this.onChanged;
    return Material(
      color: palette.field,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onChanged == null
            ? null
            : () async {
                final id = await showSectionPickerDialog(
                  context: context,
                  entries: entries,
                  palette: palette,
                  selectedId: selectedId,
                );
                if (id != null) onChanged(id);
              },
        child: Container(
          height: kDashboardControlHeight,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Icon(Icons.search_rounded, size: 18, color: palette.placeholder),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  selectedName ?? placeholder,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: selectedName == null ? palette.muted : palette.text,
                  ),
                ),
              ),
              Icon(Icons.arrow_drop_down_rounded,
                  size: 20, color: palette.muted),
            ],
          ),
        ),
      ),
    );
  }
}

/// One [PickerEntry.section] per distinct section string in [rows] (each a
/// section plus, optionally, its program), for a Filter button's
/// [FilterSectionPicker]. The section string itself is the entry's id, so a
/// table row matches the filter when its trimmed section equals the picked
/// id — see [matchesSectionFilter].
List<PickerEntry> sectionFilterEntries(
  Iterable<(String section, String? program)> rows,
) {
  final seen = <String, PickerEntry>{};
  for (final (section, program) in rows) {
    final name = section.trim();
    if (name.isEmpty || seen.containsKey(name)) continue;
    seen[name] = PickerEntry.section(id: name, name: name, program: program);
  }
  return seen.values.toList();
}

/// True when [selected] (a [sectionFilterEntries] id) is null — "All
/// sections" — or equals [section] once trimmed.
bool matchesSectionFilter(String? selected, String? section) =>
    selected == null || (section ?? '').trim() == selected;
