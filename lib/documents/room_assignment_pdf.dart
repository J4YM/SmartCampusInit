import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// One row of the generated Room Assignment schedule for
/// [buildRoomAssignmentPdf] — mirrors RoomAssignmentEntry
/// (lib/data/room_assignment_repository.dart) without this document-
/// building code depending on the data layer directly, matching
/// section_schedule_pdf.dart's own SectionSchedulePdfRow convention.
class RoomAssignmentPdfRow {
  const RoomAssignmentPdfRow({
    this.subjectCode,
    required this.subjectTitle,
    this.component,
    required this.sectionName,
    required this.professorName,
    required this.room,
    required this.day,
    required this.startTime,
    required this.endTime,
  });

  final String? subjectCode;
  final String subjectTitle;
  final String? component;
  final String sectionName;
  final String professorName;
  final String room;
  final String day;
  final String startTime;
  final String endTime;
}

const _dayLabels = {
  'M': 'Mon',
  'T': 'Tue',
  'W': 'Wed',
  'TH': 'Thu',
  'F': 'Fri',
  'S': 'Sat',
};

/// Strips the leading zero and drops AM/PM — same formatting choice as
/// section_schedule_pdf.dart's own `_formatTime12h` (duplicated rather
/// than shared, matching this codebase's small-helper-duplication
/// convention for document builders).
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

String _subjectLabel(RoomAssignmentPdfRow row) {
  // A plain hyphen, not an em dash: Helvetica (the pdf package's default
  // font) has no glyph for U+2014 and silently drops it — confirmed via
  // this file's own test, which logs "Unable to find a font to draw —"
  // when an em dash is used here.
  final code = row.subjectCode;
  final title = (code == null || code.isEmpty) ? row.subjectTitle : '$code - ${row.subjectTitle}';
  final component = row.component;
  return component == null ? title : '$title ($component)';
}

const _headers = ['Room', 'Day', 'Time', 'Subject', 'Section', 'Instructor'];

/// One flat, room-sorted table of every meeting that has a real room for
/// a school year/term — the Room Assignment analog of
/// buildSectionSchedulePdf, printable/exportable the same way. Landscape
/// A4, same header/table styling as that document.
Future<Uint8List> buildRoomAssignmentPdf({
  required String schoolYear,
  required String term,
  required List<RoomAssignmentPdfRow> rows,
}) async {
  final headerStyle = pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9);
  const cellStyle = pw.TextStyle(fontSize: 8.5);

  pw.Widget cellText(String text, {pw.TextStyle? style}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: pw.Text(text, style: style ?? cellStyle),
      );

  final doc = pw.Document();
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      build: (context) => [
        pw.Center(
          child: pw.Text(
            'Room Assignment Schedule',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
        ),
        pw.Center(
          child: pw.Text(
            '${term.toUpperCase()} A.Y. $schoolYear',
            style: const pw.TextStyle(fontSize: 11),
          ),
        ),
        pw.SizedBox(height: 12),
        pw.Table(
          border: pw.TableBorder.all(width: 0.5),
          columnWidths: const {
            0: pw.FlexColumnWidth(1.4),
            1: pw.FlexColumnWidth(1),
            2: pw.FlexColumnWidth(1.8),
            3: pw.FlexColumnWidth(4),
            4: pw.FlexColumnWidth(1.8),
            5: pw.FlexColumnWidth(2.6),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFE5E7EB)),
              children: [for (final h in _headers) cellText(h, style: headerStyle)],
            ),
            for (final row in rows)
              pw.TableRow(children: [
                cellText(row.room),
                cellText(_dayLabels[row.day] ?? row.day),
                cellText('${_formatTime12h(row.startTime)}-${_formatTime12h(row.endTime)}'),
                cellText(_subjectLabel(row)),
                cellText(row.sectionName),
                cellText(row.professorName),
              ]),
          ],
        ),
      ],
    ),
  );
  return doc.save();
}

/// Saves [buildRoomAssignmentPdf]'s output straight to a file the user
/// picks — matches exportSectionSchedulePdf's own convention.
Future<void> exportRoomAssignmentPdf({
  required String schoolYear,
  required String term,
  required List<RoomAssignmentPdfRow> rows,
}) async {
  final bytes = await buildRoomAssignmentPdf(schoolYear: schoolYear, term: term, rows: rows);
  final termSlug = term.replaceAll(' ', '_');
  await FilePicker.saveFile(
    fileName: 'Room_Assignment_${termSlug}_$schoolYear.pdf',
    type: FileType.custom,
    allowedExtensions: const ['pdf'],
    bytes: bytes,
  );
}

/// CSV mirroring the same table as [buildRoomAssignmentPdf] — Excel/Sheets
/// open these natively, matching buildSectionScheduleCsv's own rationale.
String buildRoomAssignmentCsv({
  required String schoolYear,
  required String term,
  required List<RoomAssignmentPdfRow> rows,
}) {
  final buffer = StringBuffer()
    ..writeln(_csvEscape('Room Assignment Schedule - ${term.toUpperCase()} A.Y. $schoolYear'));
  buffer.writeln(_headers.map(_csvEscape).join(','));
  for (final row in rows) {
    buffer.writeln(
      [
        row.room,
        _dayLabels[row.day] ?? row.day,
        '${_formatTime12h(row.startTime)}-${_formatTime12h(row.endTime)}',
        _subjectLabel(row),
        row.sectionName,
        row.professorName,
      ].map(_csvEscape).join(','),
    );
  }
  return buffer.toString();
}

/// Saves [buildRoomAssignmentCsv]'s output straight to a file the user
/// picks.
Future<void> exportRoomAssignmentCsv({
  required String schoolYear,
  required String term,
  required List<RoomAssignmentPdfRow> rows,
}) async {
  final csv = buildRoomAssignmentCsv(schoolYear: schoolYear, term: term, rows: rows);
  final termSlug = term.replaceAll(' ', '_');
  await FilePicker.saveFile(
    fileName: 'Room_Assignment_${termSlug}_$schoolYear.csv',
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
