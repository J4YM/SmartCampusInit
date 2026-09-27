import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// One meeting row for [buildSectionSchedulePdf] — mirrors
/// SectionScheduleEntryModel (lib/data/section_schedule_repository.dart)
/// without this document-building code depending on the data layer
/// directly, matching admission_slip_pdf.dart's own AdmissionSlipData
/// convention. [classSectionId] groups rows belonging to the same
/// offering back together — a subject with both a Lecture and a
/// Laboratory component arrives as two rows sharing one classSectionId.
/// [day]/[startTime]/[endTime]/[room] are null for an offering with no
/// meeting committed yet (still rendered as a row with blank cells,
/// matching the school's own "SCHEDULE OF CLASSES" template).
class SectionSchedulePdfRow {
  const SectionSchedulePdfRow({
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

  final String classSectionId;
  final String? subjectCode;
  final String subjectTitle;
  final String professorName;
  final String? component;
  final String? day;
  final String? startTime;
  final String? endTime;
  final String? room;
  final double? units;
  final String? schoolYear;
  final String? term;
}

const _days = ['M', 'T', 'W', 'TH', 'F', 'S'];

/// One rendered line of the grid — either a subject's own row (no
/// Lecture/Laboratory split) or a subject-header/component-sub-row pair.
class _GridRow {
  const _GridRow({
    required this.code,
    required this.label,
    required this.units,
    required this.dayText,
    required this.room,
    required this.instructor,
  });

  final String code;
  final String label;
  final String units;
  final Map<String, String> dayText;
  final String room;
  final String instructor;
}

T? _firstNonNullOf<T>(Iterable<T?> values) {
  for (final v in values) {
    if (v != null) return v;
  }
  return null;
}

int? _minutesSinceMidnight(String hhmm) {
  final parts = hhmm.split(':');
  if (parts.length != 2) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null) return null;
  return h * 60 + m;
}

/// Strips the leading zero and drops AM/PM entirely — matches the
/// school's own template exactly (e.g. "7:00-9:00", not "07:00-09:00" or
/// "7:00 AM-9:00 AM"). This is legitimately ambiguous in isolation (7:00
/// could be morning or evening) but is how the source document itself
/// reads, and replicating that format was the explicit ask.
String _formatTime12h(String hhmm) {
  final parts = hhmm.split(':');
  var hour = int.tryParse(parts[0]) ?? 0;
  final minute = parts.length > 1 ? parts[1] : '00';
  if (hour == 0) {
    hour = 12;
  } else if (hour > 12) {
    hour -= 12;
  }
  return '$hour:$minute';
}

String _formatUnits(double units) =>
    units == units.roundToDouble() ? units.toInt().toString() : units.toString();

String _labHoursSuffix(List<SectionSchedulePdfRow> bucketRows) {
  for (final r in bucketRows) {
    if (r.startTime == null || r.endTime == null) continue;
    final start = _minutesSinceMidnight(r.startTime!);
    final end = _minutesSinceMidnight(r.endTime!);
    if (start == null || end == null) continue;
    final hours = (end - start) / 60.0;
    final label = hours == hours.roundToDouble() ? hours.toInt().toString() : hours.toString();
    return '($label Hours)';
  }
  return '';
}

Map<String, String> _dayTextFor(List<SectionSchedulePdfRow> rows) {
  final dayText = <String, String>{for (final d in _days) d: ''};
  for (final r in rows) {
    if (r.day == null || r.startTime == null || r.endTime == null) continue;
    final range = '${_formatTime12h(r.startTime!)}-${_formatTime12h(r.endTime!)}';
    dayText[r.day!] = dayText[r.day!]!.isEmpty ? range : '${dayText[r.day!]}/$range';
  }
  return dayText;
}

/// Pivots a flat per-meeting row list into the grid the school's own
/// "SCHEDULE OF CLASSES" template uses: one line per subject (or, when it
/// splits into Lecture/Laboratory, one header line plus one line per
/// component), with each day of the week as its own column instead of a
/// "Day" column — chronological left-to-right (Monday through Saturday),
/// not the alphabetical F/M/S/T/TH/W order a naive `.order('day')` query
/// would produce.
({List<_GridRow> rows, double totalUnits}) _buildGrid(
  List<SectionSchedulePdfRow> rows,
) {
  final byClassSection = <String, List<SectionSchedulePdfRow>>{};
  for (final row in rows) {
    (byClassSection[row.classSectionId] ??= []).add(row);
  }

  final result = <_GridRow>[];
  var totalUnits = 0.0;

  for (final group in byClassSection.values) {
    final hasSplit = group.any((r) => r.component != null);

    if (!hasSplit) {
      final first = group.first;
      final units = _firstNonNullOf(group.map((r) => r.units));
      if (units != null) totalUnits += units;
      result.add(_GridRow(
        code: first.subjectCode ?? '',
        label: first.subjectTitle,
        units: units == null ? '' : _formatUnits(units),
        dayText: _dayTextFor(group),
        room: first.room ?? '',
        instructor: first.professorName,
      ));
      continue;
    }

    final buckets = <String, List<SectionSchedulePdfRow>>{};
    for (final r in group) {
      (buckets[r.component ?? ''] ??= []).add(r);
    }
    final orderedKeys = [
      'Lecture',
      'Laboratory',
      ...buckets.keys.where((k) => k != 'Lecture' && k != 'Laboratory'),
    ].where(buckets.containsKey);

    final rooms = group.map((r) => r.room).whereType<String>().toSet();
    result.add(_GridRow(
      code: group.first.subjectCode ?? '',
      label: group.first.subjectTitle,
      units: '',
      dayText: {for (final d in _days) d: ''},
      room: rooms.join(' / '),
      instructor: group.first.professorName,
    ));

    for (final key in orderedKeys) {
      final bucketRows = buckets[key]!;
      final units = _firstNonNullOf(bucketRows.map((r) => r.units));
      if (units != null) totalUnits += units;
      final label = key == 'Laboratory' ? 'Laboratory${_labHoursSuffix(bucketRows)}' : key;
      result.add(_GridRow(
        code: '',
        label: label,
        units: units == null ? '' : _formatUnits(units),
        dayText: _dayTextFor(bucketRows),
        room: '',
        instructor: '',
      ));
    }
  }

  return (rows: result, totalUnits: totalUnits);
}

const _gridHeaders = ['CODE', 'SUBJECT', 'UNITS', 'M', 'T', 'W', 'TH', 'F', 'S', 'ROOM', 'INSTRUCTOR'];

/// One sheet per section, laid out as the school's own "SCHEDULE OF
/// CLASSES" template: one row per subject (or per Lecture/Laboratory
/// component), with each weekday as its own column. Landscape, not the
/// admission slip's narrow-receipt format: this is a normal desktop
/// print/save, not a thermal-printer kiosk flow.
Future<Uint8List> buildSectionSchedulePdf({
  required String sectionName,
  required List<SectionSchedulePdfRow> rows,
}) async {
  final grid = _buildGrid(rows);
  final schoolYear = _firstNonNullOf(rows.map((r) => r.schoolYear));
  final term = _firstNonNullOf(rows.map((r) => r.term));
  final subtitle = (schoolYear != null && term != null)
      ? 'SCHEDULE OF CLASSES - ${term.toUpperCase()} A.Y. $schoolYear'
      : 'SCHEDULE OF CLASSES';

  final headerStyle = pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8);
  const cellStyle = pw.TextStyle(fontSize: 7.5);

  pw.Widget cellText(String text, {pw.TextStyle? style}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 3),
        child: pw.Text(text, style: style ?? cellStyle),
      );

  final doc = pw.Document();
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      build: (context) => [
        pw.Center(
          child: pw.Text(
            sectionName,
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
        ),
        pw.Center(child: pw.Text(subtitle, style: const pw.TextStyle(fontSize: 11))),
        pw.SizedBox(height: 12),
        pw.Table(
          border: pw.TableBorder.all(width: 0.5),
          columnWidths: const {
            0: pw.FlexColumnWidth(1.3),
            1: pw.FlexColumnWidth(4),
            2: pw.FlexColumnWidth(0.8),
            3: pw.FlexColumnWidth(1.5),
            4: pw.FlexColumnWidth(1.5),
            5: pw.FlexColumnWidth(1.5),
            6: pw.FlexColumnWidth(1.5),
            7: pw.FlexColumnWidth(1.5),
            8: pw.FlexColumnWidth(1.5),
            9: pw.FlexColumnWidth(1.6),
            10: pw.FlexColumnWidth(2.4),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFE5E7EB)),
              children: [for (final h in _gridHeaders) cellText(h, style: headerStyle)],
            ),
            for (final row in grid.rows)
              pw.TableRow(children: [
                cellText(row.code),
                cellText(row.label),
                cellText(row.units),
                for (final d in _days) cellText(row.dayText[d] ?? ''),
                cellText(row.room),
                cellText(row.instructor),
              ]),
            pw.TableRow(children: [
              cellText(''),
              cellText(''),
              cellText(_formatUnits(grid.totalUnits), style: headerStyle),
              for (final _ in _days) cellText(''),
              cellText(''),
              cellText(''),
            ]),
          ],
        ),
      ],
    ),
  );
  return doc.save();
}

/// Saves [buildSectionSchedulePdf]'s output straight to a file the user
/// picks — a real download, not the system print dialog. The Registrar/
/// Scheduling Officer asked for an actual exported copy they can keep or
/// hand off, not just a print preview.
Future<void> exportSectionSchedulePdf({
  required String sectionName,
  required List<SectionSchedulePdfRow> rows,
}) async {
  final bytes = await buildSectionSchedulePdf(sectionName: sectionName, rows: rows);
  await FilePicker.saveFile(
    fileName: 'Class_Schedule_${sectionName.replaceAll(' ', '_')}.pdf',
    type: FileType.custom,
    allowedExtensions: const ['pdf'],
    bytes: bytes,
  );
}

/// CSV content mirroring the same grid layout as [buildSectionSchedulePdf]
/// — Excel/Sheets open these natively and every cell stays editable,
/// which a PDF can't offer. Matches
/// reports_exports_connected_page.dart's own "Export to Excel"
/// convention: a true .xlsx writer isn't used here since every current
/// option conflicts with docx_creator's pinned `archive`/`xml` versions.
/// Split from [exportSectionScheduleCsv] (which just saves this to a
/// file) so the actual grid-building logic can be unit-tested without a
/// file-picker platform channel.
String buildSectionScheduleCsv({
  required String sectionName,
  required List<SectionSchedulePdfRow> rows,
}) {
  final grid = _buildGrid(rows);
  final buffer = StringBuffer()..writeln(_csvEscape(sectionName));
  buffer.writeln(_gridHeaders.map(_csvEscape).join(','));
  for (final row in grid.rows) {
    buffer.writeln(
      [
        row.code,
        row.label,
        row.units,
        for (final d in _days) row.dayText[d] ?? '',
        row.room,
        row.instructor,
      ].map(_csvEscape).join(','),
    );
  }
  buffer.writeln(
    ['', '', _formatUnits(grid.totalUnits), '', '', '', '', '', '', '', '']
        .map(_csvEscape)
        .join(','),
  );
  return buffer.toString();
}

/// Saves [buildSectionScheduleCsv]'s output straight to a file the user
/// picks.
Future<void> exportSectionScheduleCsv({
  required String sectionName,
  required List<SectionSchedulePdfRow> rows,
}) async {
  final csv = buildSectionScheduleCsv(sectionName: sectionName, rows: rows);
  await FilePicker.saveFile(
    fileName: 'Class_Schedule_${sectionName.replaceAll(' ', '_')}.csv',
    type: FileType.custom,
    allowedExtensions: const ['csv'],
    bytes: utf8.encode(csv),
  );
}

String _csvEscape(String value) {
  if (value.contains(',') || value.contains('"') || value.contains('\n')) {
    return '"${value.replaceAll('"', '""')}"';
  }
  return value;
}
