import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'bento_card.dart';
import 'brightness_x.dart';
import 'dashboard_dropdown.dart';
import 'dashboard_table.dart';
import 'mouse_draggable_scroll_behavior.dart';
import 'responsive_x.dart';
import 'secondary_pill_button.dart';
import 'section_facets.dart';

/// One meeting row in a generated per-section Class Schedule — package-
/// local so this widget stays independent of the host app's own data
/// layer (matches this codebase's usual connected-page mapping
/// convention, e.g. ItTechnicianConnectedPage._toReaderRow).
class SectionScheduleRowModel {
  const SectionScheduleRowModel({
    required this.classSectionId,
    this.subjectCode,
    required this.subjectTitle,
    required this.professorName,
    this.component,
    this.day,
    this.startTime,
    this.endTime,
    this.room,
    this.units,
    this.schoolYear,
    this.term,
  });

  /// Groups rows that belong to the same offering — a subject with both
  /// a Lecture and a Laboratory component produces two rows sharing one
  /// classSectionId.
  final String classSectionId;

  final String? subjectCode;
  final String subjectTitle;
  final String professorName;

  /// 'Lecture', 'Laboratory', or null when the subject has no split (or
  /// no meeting at all yet).
  final String? component;

  /// One of 'M', 'T', 'W', 'TH', 'F', 'S'. Null when this offering has no
  /// meeting committed yet — still shown as a row (just with blank day/
  /// time/room), matching the school's own template.
  final String? day;
  final String? startTime;
  final String? endTime;
  final String? room;
  final double? units;
  final String? schoolYear;
  final String? term;
}

/// Section picker + generated weekly schedule table + Print/Download —
/// shared by every dashboard that needs to view or hand out "the Class
/// Schedule" for a section (Registrar, Scheduling Officer). Deliberately
/// self-contained (owns its own selection/loading state) so each host
/// dashboard only has to supply data callbacks, matching
/// UploadSpreadsheetButton's shape in this same package.
class SectionScheduleCard extends StatefulWidget {
  const SectionScheduleCard({
    super.key,
    required this.sectionOptions,
    this.onSectionSelected,
    this.onExportPdf,
    this.onExportExcel,
    this.onAddSchedule,
    this.accentColor = const Color(0xFF2563EB),
  });

  /// (id, name) pairs — e.g. `[(id: '...', name: 'BSIT 2A'), ...]`.
  final List<({String id, String name})> sectionOptions;

  /// Fetches every meeting for the chosen section's id. Null disables the
  /// picker entirely (e.g. Supabase not configured).
  final Future<List<SectionScheduleRowModel>> Function(String sectionId)?
      onSectionSelected;

  /// Exports the currently-shown section's schedule as a PDF file. Null
  /// hides the "Export PDF" button.
  final Future<void> Function(String sectionName, List<SectionScheduleRowModel> rows)?
      onExportPdf;

  /// Exports the currently-shown section's schedule as an editable
  /// spreadsheet file. Null hides the "Export Excel" button.
  final Future<void> Function(String sectionName, List<SectionScheduleRowModel> rows)?
      onExportExcel;

  /// Opens the host's "Add Class Schedule" form. Null hides the
  /// "Add Schedule" button. Unlike the export buttons, it shows even before
  /// a section is picked.
  final VoidCallback? onAddSchedule;

  final Color accentColor;

  @override
  State<SectionScheduleCard> createState() => _SectionScheduleCardState();
}

class _SectionScheduleCardState extends State<SectionScheduleCard> {
  String? _selectedSectionId;
  List<SectionScheduleRowModel>? _rows;
  bool _loading = false;
  bool _exportingPdf = false;
  bool _exportingExcel = false;

  String? get _selectedSectionName {
    for (final section in widget.sectionOptions) {
      if (section.id == _selectedSectionId) return section.name;
    }
    return null;
  }

  Future<void> _selectSection(String? sectionId) async {
    final onSectionSelected = widget.onSectionSelected;
    if (sectionId == null || onSectionSelected == null) return;
    setState(() {
      _selectedSectionId = sectionId;
      _rows = null;
      _loading = true;
    });
    try {
      final rows = await onSectionSelected(sectionId);
      if (mounted) setState(() => _rows = rows);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _handleExportPdf() async {
    final onExportPdf = widget.onExportPdf;
    final rows = _rows;
    final sectionName = _selectedSectionName;
    if (onExportPdf == null || rows == null || sectionName == null) return;
    setState(() => _exportingPdf = true);
    try {
      await onExportPdf(sectionName, rows);
    } finally {
      if (mounted) setState(() => _exportingPdf = false);
    }
  }

  Future<void> _handleExportExcel() async {
    final onExportExcel = widget.onExportExcel;
    final rows = _rows;
    final sectionName = _selectedSectionName;
    if (onExportExcel == null || rows == null || sectionName == null) return;
    setState(() => _exportingExcel = true);
    try {
      await onExportExcel(sectionName, rows);
    } finally {
      if (mounted) setState(() => _exportingExcel = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final borderColor =
        context.isDarkMode ? const Color(0xFF22242B) : const Color(0x0D000000);
    final cardColor = context.isDarkMode ? const Color(0xFF191A1F) : Colors.white;
    final mutedText =
        context.isDarkMode ? const Color(0xFFA1A1AA) : const Color(0xFF8F8F8F);
    final rowText =
        context.isDarkMode ? const Color(0xFFF5F5F5) : const Color(0xFF343A40);
    final fieldFill =
        context.isDarkMode ? const Color(0xFF22242B) : const Color(0xFFF3F5F8);
    final hasRows = _rows != null && _rows!.isNotEmpty;

    return BentoCard(
      backgroundColor: cardColor,
      borderColor: borderColor,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Wrap, not Row + Spacer: title + up to three buttons don't fit
          // on one line at mobile widths, so the buttons drop below.
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Generated Class Schedule',
                style: GoogleFonts.poppins(
                  fontSize: context.isMobileWidth ? 16 : 18,
                  fontWeight: FontWeight.w600,
                  color: rowText,
                ),
              ),
              // Tinted pills, matching the app's other card-header actions
              // (e.g. UploadSpreadsheetButton) rather than bare text links.
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (widget.onAddSchedule != null)
                    _HeaderPillButton(
                      label: 'Add Schedule',
                      icon: Icons.add_rounded,
                      accentColor: widget.accentColor,
                      backgroundColor: fieldFill,
                      onTap: widget.onAddSchedule,
                    ),
                  if (widget.onExportPdf != null && hasRows)
                    _HeaderPillButton(
                      label: 'Export PDF',
                      icon: Icons.picture_as_pdf_outlined,
                      busy: _exportingPdf,
                      accentColor: widget.accentColor,
                      backgroundColor: fieldFill,
                      onTap: _exportingPdf ? null : _handleExportPdf,
                    ),
                  if (widget.onExportExcel != null && hasRows)
                    _HeaderPillButton(
                      label: 'Export Excel',
                      icon: Icons.table_view_outlined,
                      busy: _exportingExcel,
                      accentColor: widget.accentColor,
                      backgroundColor: fieldFill,
                      onTap: _exportingExcel ? null : _handleExportExcel,
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          // One dropdown per program/course (BSIT, BSTM, …), each listing
          // only that program's sections in year order. Picking a section
          // in one clears the others — a single section is shown at a time.
          _ProgramDropdownRow(
            groups: _groupSectionsByProgram(widget.sectionOptions),
            selectedSectionId: _selectedSectionId,
            cardColor: cardColor,
            fieldFill: fieldFill,
            textColor: rowText,
            mutedColor: mutedText,
            onChanged: widget.onSectionSelected == null ? null : _selectSection,
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (_rows != null)
            _rows!.isEmpty
                ? const DashboardTableEmptyState(
                    icon: Icons.event_busy_outlined,
                    message: 'No subjects on file for this section yet.',
                  )
                : _ScheduleTable(rows: _rows!),
        ],
      ),
    );
  }
}

/// Tinted header action pill — same size/shape as [UploadSpreadsheetButton]
/// (12px w600 label, 16px icon, 12x8 padding, 10px radius).
class _HeaderPillButton extends StatelessWidget {
  const _HeaderPillButton({
    required this.label,
    required this.icon,
    required this.accentColor,
    required this.backgroundColor,
    required this.onTap,
    this.busy = false,
  });

  final String label;
  final IconData icon;
  final Color accentColor;
  final Color backgroundColor;
  final VoidCallback? onTap;

  /// Swaps the icon for a small spinner (e.g. while an export runs).
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return SecondaryPillButton(
      label: label,
      icon: icon,
      loading: busy,
      onTap: onTap,
    );
  }
}

const _dayLabels = {
  'M': 'Mon',
  'T': 'Tue',
  'W': 'Wed',
  'TH': 'Thu',
  'F': 'Fri',
  'S': 'Sat',
};

const _scheduleColumns = <DashboardTableColumn>[
  DashboardTableColumn('Subject', flex: 3),
  DashboardTableColumn('Component', flex: 2),
  DashboardTableColumn('Day', flex: 1),
  DashboardTableColumn('Time', flex: 2),
  DashboardTableColumn('Room', flex: 2),
  DashboardTableColumn('Instructor', flex: 3),
];

class _ScheduleTable extends StatelessWidget {
  const _ScheduleTable({required this.rows});

  final List<SectionScheduleRowModel> rows;

  @override
  Widget build(BuildContext context) {
    Text body(String text) => Text(
          text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: dashboardTableBodyStyle(context),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const DashboardTableHeader(columns: _scheduleColumns, topBorder: true),
        for (var i = 0; i < rows.length; i++)
          DashboardTableRow(
            columns: _scheduleColumns,
            showDivider: i < rows.length - 1,
            cells: [
              Text(
                rows[i].subjectTitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: dashboardTablePrimaryStyle(context),
              ),
              body(rows[i].component ?? '—'),
              body(rows[i].day == null
                  ? '—'
                  : (_dayLabels[rows[i].day] ?? rows[i].day!)),
              body(rows[i].startTime == null
                  ? 'Not yet scheduled'
                  : '${rows[i].startTime} - ${rows[i].endTime}'),
              body(rows[i].room ?? '—'),
              body(rows[i].professorName),
            ],
          ),
      ],
    );
  }
}

/// One program/course's sections — e.g. every BSIT section, sorted by year
/// level (1st to 4th) then block.
class _ProgramGroup {
  const _ProgramGroup(this.code, this.sections);

  /// Upper-cased program code ('BSIT'), or 'Other' for names that don't
  /// follow the "<program> <year><block>" shape.
  final String code;
  final List<({String id, String name})> sections;
}

const _otherProgramCode = 'Other';

/// Splits [options] into one group per program, programs in alphabetical
/// order (with unparseable names last, under 'Other'), and each group's
/// sections ordered by year then block then name.
List<_ProgramGroup> _groupSectionsByProgram(
  List<({String id, String name})> options,
) {
  final byProgram = <String, List<({String id, String name})>>{};
  for (final option in options) {
    final code = sectionProgramCode(option.name) ?? _otherProgramCode;
    byProgram.putIfAbsent(code, () => []).add(option);
  }

  int year(String name) => int.tryParse(sectionYearDigit(name) ?? '') ?? 99;
  String block(String name) => sectionBlockLetter(name) ?? '';

  for (final sections in byProgram.values) {
    sections.sort((a, b) {
      final byYear = year(a.name).compareTo(year(b.name));
      if (byYear != 0) return byYear;
      final byBlock = block(a.name).compareTo(block(b.name));
      if (byBlock != 0) return byBlock;
      return a.name.compareTo(b.name);
    });
  }

  final codes = byProgram.keys.toList()
    ..sort((a, b) {
      if (a == _otherProgramCode) return 1;
      if (b == _otherProgramCode) return -1;
      return a.compareTo(b);
    });
  return [for (final code in codes) _ProgramGroup(code, byProgram[code]!)];
}

/// Every program's dropdown on ONE row: they share the card's width equally
/// while each can keep at least [_minFieldWidth]; if that doesn't fit (many
/// programs or a phone), the row scrolls sideways instead of wrapping onto a
/// second line.
class _ProgramDropdownRow extends StatelessWidget {
  const _ProgramDropdownRow({
    required this.groups,
    required this.selectedSectionId,
    required this.cardColor,
    required this.fieldFill,
    required this.textColor,
    required this.mutedColor,
    required this.onChanged,
  });

  static const double _minFieldWidth = 130;
  static const double _gap = 12;

  final List<_ProgramGroup> groups;
  final String? selectedSectionId;
  final Color cardColor;
  final Color fieldFill;
  final Color textColor;
  final Color mutedColor;
  final ValueChanged<String?>? onChanged;

  @override
  Widget build(BuildContext context) {
    if (groups.isEmpty) return const SizedBox.shrink();

    _ProgramSectionDropdown field(_ProgramGroup group) =>
        _ProgramSectionDropdown(
          group: group,
          selectedSectionId: selectedSectionId,
          cardColor: cardColor,
          fieldFill: fieldFill,
          textColor: textColor,
          mutedColor: mutedColor,
          onChanged: onChanged,
        );

    return LayoutBuilder(
      builder: (context, constraints) {
        final needed =
            groups.length * _minFieldWidth + (groups.length - 1) * _gap;
        if (constraints.maxWidth >= needed) {
          return Row(
            children: [
              for (var i = 0; i < groups.length; i++) ...[
                if (i > 0) const SizedBox(width: _gap),
                Expanded(child: field(groups[i])),
              ],
            ],
          );
        }
        return ScrollConfiguration(
          behavior: mouseDraggableScrollBehavior,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < groups.length; i++) ...[
                  if (i > 0) const SizedBox(width: _gap),
                  SizedBox(width: _minFieldWidth, child: field(groups[i])),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A dropdown for a single program's sections, with a small non-selectable
/// "1st Year" … "4th Year" heading above each year's sections. Shows the
/// program code as its hint until one of its sections is selected.
class _ProgramSectionDropdown extends StatelessWidget {
  const _ProgramSectionDropdown({
    required this.group,
    required this.selectedSectionId,
    required this.cardColor,
    required this.fieldFill,
    required this.textColor,
    required this.mutedColor,
    required this.onChanged,
  });

  final _ProgramGroup group;
  final String? selectedSectionId;
  final Color cardColor;
  final Color fieldFill;
  final Color textColor;
  final Color mutedColor;
  final ValueChanged<String?>? onChanged;

  @override
  Widget build(BuildContext context) {
    final value = group.sections.any((s) => s.id == selectedSectionId)
        ? selectedSectionId
        : null;

    final items = <DropdownMenuItem<String>>[];
    String? currentYear;
    for (final section in group.sections) {
      final year = sectionYearDigit(section.name);
      if (year != null && year != currentYear) {
        currentYear = year;
        items.add(DropdownMenuItem<String>(
          value: '__${group.code}_year_$year',
          enabled: false,
          child: Text(
            '${yearLabelForDigit(year)} Year',
            style: GoogleFonts.poppins(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: mutedColor,
            ),
          ),
        ));
      }
      items.add(DropdownMenuItem<String>(
        value: section.id,
        child: Text(section.name),
      ));
    }

    return DashboardDropdown<String>(
      value: value,
      fillColor: fieldFill,
      menuColor: cardColor,
      borderRadius: 8,
      horizontalPadding: 14,
      textStyle: GoogleFonts.poppins(fontSize: 12, color: textColor),
      // Shows the program code until one of its sections is selected.
      hint: Text(
        group.code,
        style: GoogleFonts.poppins(fontSize: 12, color: mutedColor),
      ),
      items: items,
      onChanged: onChanged,
    );
  }
}
