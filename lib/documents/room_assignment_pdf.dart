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
    required this.classSectionId,
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

  /// Groups a subject's Lecture/Laboratory components back together within
  /// a room — two rows sharing one classSectionId merge into one subject
  /// block (header + component sub-rows), matching
  /// section_schedule_pdf.dart's own grid-pivot convention.
  final String classSectionId;
  final String? subjectCode;
  final String subjectTitle;

  /// 'Lecture', 'Laboratory', or null when the subject has no split.
  final String? component;

  final String sectionName;
  final String professorName;
  final String room;

  /// One of 'M', 'T', 'W', 'TH', 'F', 'S'.
  final String day;

  /// 24-hour "HH:MM".
  final String startTime;
  final String endTime;
}

const _days = ['M', 'T', 'W', 'TH', 'F', 'S'];

/// One rendered line of a room's grid — either a subject's own row (no
/// Lecture/Laboratory split) or a subject-header/component-sub-row pair.
/// Mirrors section_schedule_pdf.dart's own `_GridRow`, plus [section]
/// (blank on a sub-row) since one room hosts many different sections,
/// unlike a per-section schedule where the section is the page title.
class _GridRow {
  const _GridRow({
    required this.label,
    required this.dayText,
    required this.section,
    required this.instructor,
  });

  final String label;
  final Map<String, String> dayText;
  final String section;
  final String instructor;
}

int? _minutesSinceMidnight(String hhmm) {
  final parts = hhmm.split(':');
  if (parts.length != 2) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null) return null;
  return h * 60 + m;
}

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

String _labHoursSuffix(List<RoomAssignmentPdfRow> bucketRows) {
  for (final r in bucketRows) {
    final start = _minutesSinceMidnight(r.startTime);
    final end = _minutesSinceMidnight(r.endTime);
    if (start == null || end == null) continue;
    final hours = (end - start) / 60.0;
    final label = hours == hours.roundToDouble() ? hours.toInt().toString() : hours.toString();
    return ' ($label hours)';
  }
  return '';
}

Map<String, String> _dayTextFor(List<RoomAssignmentPdfRow> rows) {
  final dayText = <String, String>{for (final d in _days) d: ''};
  for (final r in rows) {
    final range = '${_formatTime12h(r.startTime)}-${_formatTime12h(r.endTime)}';
    dayText[r.day] = dayText[r.day]!.isEmpty ? range : '${dayText[r.day]}/$range';
  }
  return dayText;
}

/// Pivots one room's flat meeting-row list into the school's own "ROOM
/// SCHEDULE" template: one line per subject (or, when it splits into
/// Lecture/Laboratory, one header line plus one line per component), with
/// each weekday as its own column — same grid shape as
/// section_schedule_pdf.dart's `_buildGrid`, minus the CODE/UNITS columns
/// that template doesn't carry and plus a SECTION column, since one room
/// hosts many different sections where a per-section schedule hosts only
/// one.
List<_GridRow> _buildRoomGrid(List<RoomAssignmentPdfRow> roomRows) {
  final byClassSection = <String, List<RoomAssignmentPdfRow>>{};
  for (final row in roomRows) {
    (byClassSection[row.classSectionId] ??= []).add(row);
  }

  final result = <_GridRow>[];
  for (final group in byClassSection.values) {
    final first = group.first;
    final hasSplit = group.any((r) => r.component != null);

    if (!hasSplit) {
      result.add(_GridRow(
        label: first.subjectTitle,
        dayText: _dayTextFor(group),
        section: first.sectionName,
        instructor: first.professorName,
      ));
      continue;
    }

    final buckets = <String, List<RoomAssignmentPdfRow>>{};
    for (final r in group) {
      (buckets[r.component ?? ''] ??= []).add(r);
    }
    final orderedKeys = [
      'Lecture',
      'Laboratory',
      ...buckets.keys.where((k) => k != 'Lecture' && k != 'Laboratory'),
    ].where(buckets.containsKey);

    result.add(_GridRow(
      label: first.subjectTitle,
      dayText: {for (final d in _days) d: ''},
      section: first.sectionName,
      instructor: first.professorName,
    ));

    for (final key in orderedKeys) {
      final bucketRows = buckets[key]!;
      final label = key == 'Laboratory' ? 'Laboratory${_labHoursSuffix(bucketRows)}' : key;
      result.add(_GridRow(
        label: label,
        dayText: _dayTextFor(bucketRows),
        section: '',
        instructor: '',
      ));
    }
  }

  return result;
}

/// Groups [rows] by room, preserving the order rooms first appear in (the
/// repository already returns them room-sorted) — the printable "one room,
/// one page" breakdown matching the school's own "ROOM SCHEDULE" workbook
/// (one sheet per room).
Map<String, List<RoomAssignmentPdfRow>> groupRoomAssignmentsByRoom(
  List<RoomAssignmentPdfRow> rows,
) {
  final byRoom = <String, List<RoomAssignmentPdfRow>>{};
  for (final row in rows) {
    (byRoom[row.room] ??= []).add(row);
  }
  return byRoom;
}

const _gridHeaders = ['SUBJECT', 'M', 'T', 'W', 'TH', 'F', 'S', 'INSTRUCTOR', 'SECTION'];

/// One page per room, each laid out as the school's own "ROOM SCHEDULE"
/// template: one row per subject (or per Lecture/Laboratory component),
/// each weekday as its own column, section and instructor on the header
/// row only. Landscape A4 — a normal desktop print/save, not a kiosk
/// receipt format.
Future<Uint8List> buildRoomAssignmentPdf({
  required String schoolYear,
  required String term,
  required List<RoomAssignmentPdfRow> rows,
}) async {
  final headerStyle = pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8);
  const cellStyle = pw.TextStyle(fontSize: 7.5);

  pw.Widget cellText(String text, {pw.TextStyle? style}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 3),
        child: pw.Text(text, style: style ?? cellStyle),
      );

  final doc = pw.Document();
  final byRoom = groupRoomAssignmentsByRoom(rows);

  for (final entry in byRoom.entries) {
    final grid = _buildRoomGrid(entry.value);
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        build: (context) => [
          pw.Center(
            child: pw.Text(
              'ROOM SCHEDULE',
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.Center(
            child: pw.Text(
              entry.key,
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.Center(
            child: pw.Text(
              '${term.toUpperCase()} A.Y. $schoolYear',
              style: const pw.TextStyle(fontSize: 10),
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Table(
            border: pw.TableBorder.all(width: 0.5),
            columnWidths: const {
              0: pw.FlexColumnWidth(3.4),
              1: pw.FlexColumnWidth(1.5),
              2: pw.FlexColumnWidth(1.5),
              3: pw.FlexColumnWidth(1.5),
              4: pw.FlexColumnWidth(1.5),
              5: pw.FlexColumnWidth(1.5),
              6: pw.FlexColumnWidth(1.5),
              7: pw.FlexColumnWidth(2.4),
              8: pw.FlexColumnWidth(1.8),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFE5E7EB)),
                children: [for (final h in _gridHeaders) cellText(h, style: headerStyle)],
              ),
              for (final row in grid)
                pw.TableRow(children: [
                  cellText(row.label),
                  for (final d in _days) cellText(row.dayText[d] ?? ''),
                  cellText(row.instructor),
                  cellText(row.section),
                ]),
            ],
          ),
        ],
      ),
    );
  }
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

/// CSV mirroring the same per-room grid as [buildRoomAssignmentPdf] —
/// Excel/Sheets open these natively, matching buildSectionScheduleCsv's
/// own rationale. Each room's block is stacked with a blank line between
/// them (a single CSV has no separate sheets/tabs to put each room on).
String buildRoomAssignmentCsv({
  required String schoolYear,
  required String term,
  required List<RoomAssignmentPdfRow> rows,
}) {
  final byRoom = groupRoomAssignmentsByRoom(rows);
  final buffer = StringBuffer();
  var first = true;
  for (final entry in byRoom.entries) {
    if (!first) buffer.writeln();
    first = false;
    buffer.writeln(_csvEscape('ROOM SCHEDULE'));
    buffer.writeln(_csvEscape(entry.key));
    buffer.writeln(_csvEscape('${term.toUpperCase()} A.Y. $schoolYear'));
    buffer.writeln(_gridHeaders.map(_csvEscape).join(','));
    for (final row in _buildRoomGrid(entry.value)) {
      buffer.writeln(
        [
          row.label,
          for (final d in _days) row.dayText[d] ?? '',
          row.instructor,
          row.section,
        ].map(_csvEscape).join(','),
      );
    }
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
