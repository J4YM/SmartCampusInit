import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'bento_card.dart';
import 'brightness_x.dart';
import 'dashboard_table.dart';
import 'searchable_picker_list.dart';
import 'responsive_x.dart';
import 'secondary_pill_button.dart';
import 'time_format.dart';

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
      // Flush: the schedule table runs edge to edge (the app-wide table
      // standard), so only the title and section picker are padded, below.
      padding: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
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
                // The shared section picker: opens a search + program-grouped list.
                SectionPickerField(
                  entries: [
                    for (final s in widget.sectionOptions)
                      PickerEntry.section(id: s.id, name: s.name),
                  ],
                  palette: PickerPalette(
                    surface: cardColor,
                    field: fieldFill,
                    border: borderColor,
                    text: rowText,
                    muted: mutedText,
                    placeholder: mutedText,
                    accent: widget.accentColor,
                  ),
                  selectedId: _selectedSectionId,
                  onChanged:
                      widget.onSectionSelected == null ? null : _selectSection,
                ),
              ],
            ),
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

    return DashboardTableScrollFrame(
      columns: _scheduleColumns,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const DashboardTableHeader(
              columns: _scheduleColumns, topBorder: true),
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
                    : formatClockRange12h(
                        rows[i].startTime!, rows[i].endTime ?? '')),
                body(rows[i].room ?? '—'),
                body(rows[i].professorName),
              ],
            ),
        ],
      ),
    );
  }
}
