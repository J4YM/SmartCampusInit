import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'bento_card.dart';
import 'brightness_x.dart';
import 'responsive_x.dart';

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
          // Static label above the field, not `labelText` — a floating
          // label on an OutlineInputBorder (even with `borderSide: none`)
          // still positions itself straddling the field's top edge (notch
          // math). Matches the School Year / Term fields' own fix.
          Padding(
            padding: const EdgeInsets.only(bottom: 6, left: 2),
            child: Text(
              'Section',
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: mutedText,
              ),
            ),
          ),
          DropdownButtonFormField<String>(
            value: _selectedSectionId,
            isExpanded: true,
            dropdownColor: cardColor,
            style: GoogleFonts.poppins(fontSize: 13, color: rowText),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Select a section',
              hintStyle: GoogleFonts.poppins(fontSize: 13, color: mutedText),
              filled: true,
              fillColor: fieldFill,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
            ),
            items: [
              for (final section in widget.sectionOptions)
                DropdownMenuItem(value: section.id, child: Text(section.name)),
            ],
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
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'No subjects on file for this section yet.',
                      style: GoogleFonts.poppins(fontSize: 13, color: mutedText),
                    ),
                  )
                : _ScheduleTable(rows: _rows!, mutedText: mutedText, rowText: rowText),
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
    return Material(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              busy
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: accentColor),
                    )
                  : Icon(icon, size: 16, color: accentColor),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: accentColor,
                ),
              ),
            ],
          ),
        ),
      ),
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

class _ScheduleTable extends StatelessWidget {
  const _ScheduleTable({required this.rows, required this.mutedText, required this.rowText});

  final List<SectionScheduleRowModel> rows;
  final Color mutedText;
  final Color rowText;

  @override
  Widget build(BuildContext context) {
    final headerStyle = GoogleFonts.poppins(
      fontSize: context.isMobileWidth ? 10 : 12,
      fontWeight: FontWeight.w600,
      color: mutedText,
    );
    final cellStyle = GoogleFonts.poppins(
      fontSize: context.isMobileWidth ? 11 : 13,
      fontWeight: FontWeight.w500,
      color: rowText,
    );

    Widget cell(String text, {int flex = 2, TextStyle? style}) => Expanded(
          flex: flex,
          child: Text(text, style: style ?? cellStyle, overflow: TextOverflow.ellipsis),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          cell('Subject', flex: 3, style: headerStyle),
          cell('Component', flex: 2, style: headerStyle),
          cell('Day', flex: 1, style: headerStyle),
          cell('Time', flex: 2, style: headerStyle),
          cell('Room', flex: 2, style: headerStyle),
          cell('Instructor', flex: 3, style: headerStyle),
        ]),
        const Divider(height: 12),
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              cell(row.subjectTitle, flex: 3),
              cell(row.component ?? '—', flex: 2),
              cell(row.day == null ? '—' : (_dayLabels[row.day] ?? row.day!), flex: 1),
              cell(
                row.startTime == null ? 'Not yet scheduled' : '${row.startTime} - ${row.endTime}',
                flex: 2,
              ),
              cell(row.room ?? '—', flex: 2),
              cell(row.professorName, flex: 3),
            ]),
          ),
      ],
    );
  }
}
