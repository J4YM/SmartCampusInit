import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'brightness_x.dart';

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
    final hasRows = _rows != null && _rows!.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'Generated Class Schedule',
                style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: rowText),
              ),
              const Spacer(),
              if (widget.onExportPdf != null && hasRows)
                TextButton.icon(
                  onPressed: _exportingPdf ? null : _handleExportPdf,
                  icon: _exportingPdf
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.picture_as_pdf_outlined, size: 18),
                  label: const Text('Export PDF'),
                ),
              if (widget.onExportExcel != null && hasRows)
                TextButton.icon(
                  onPressed: _exportingExcel ? null : _handleExportExcel,
                  icon: _exportingExcel
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.table_view_outlined, size: 18),
                  label: const Text('Export Excel'),
                ),
            ],
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: _selectedSectionId,
            isExpanded: true,
            decoration: InputDecoration(
              isDense: true,
              labelText: 'Section',
              labelStyle: GoogleFonts.poppins(fontSize: 12),
              border: const OutlineInputBorder(),
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
                      style: GoogleFonts.poppins(fontSize: 12, color: mutedText),
                    ),
                  )
                : _ScheduleTable(rows: _rows!, mutedText: mutedText, rowText: rowText),
        ],
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
    final headerStyle = GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: mutedText);
    final cellStyle = GoogleFonts.poppins(fontSize: 12, color: rowText);

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
