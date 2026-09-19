// scripts/generate_sample_schedule_xlsx.dart
//
// Produces a real, valid .xlsx file in the Confirmation of Faculty
// Loading (CFL) format that lib/data/schedule_import/schedule_file_parser.dart
// already parses and lib/data/schedule_import_runner.dart already commits —
// for testing the Registrar's "Upload Spreadsheet" → import → Professor's
// "My Schedule" cycle end to end without needing a real school export.
//
// The Instructor: name ("Faculty Member") matches the demo professor's
// actual seeded profile (supabase/add_professor_module_schema.sql —
// first_name 'Faculty', last_name 'Member') exactly, so
// ScheduleImportRepository.resolveProfessorId's full-name match resolves
// it with no extra setup. The Section ("BSIT 2A") already exists via
// supabase/seed_sections.sql. The Subject ("Human Computer Interaction")
// does NOT exist anywhere yet — this format carries no course code, and
// resolveSubjectId correctly refuses to invent one for a brand-new
// subject (see its own doc comment: this is intentional, not a bug to
// work around). Run
// supabase/seed_sample_schedule_import_subject.sql first if you want to
// see the full successful commit (offering + 2 meetings); skip it to
// test the "could not resolve" per-row error-reporting path instead —
// both are real, correct behavior.
//
// Usage: dart run scripts/generate_sample_schedule_xlsx.dart
// Output: sample_data/confirmation_of_faculty_loading_sample.xlsx

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';

/// One cell, always written as an inline string — simplest correct form
/// for a hand-built workbook (no shared-strings table to maintain) and
/// exactly what schedule_file_parser.dart's own reader
/// (lib/data/schedule_import/xlsx_reader.dart) already expects to see.
String _cell(String columnLetters, int rowNumber, String? value) {
  if (value == null || value.isEmpty) {
    return '<c r="$columnLetters$rowNumber"/>';
  }
  final escaped = value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
  return '<c r="$columnLetters$rowNumber" t="inlineStr"><is><t>$escaped</t></is></c>';
}

const _columns = ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J'];

String _row(int rowNumber, List<String?> values) {
  final cells = StringBuffer();
  for (var i = 0; i < values.length; i++) {
    cells.write(_cell(_columns[i], rowNumber, values[i]));
  }
  return '<row r="$rowNumber">$cells</row>';
}

void main() {
  // Columns: SUBJECT, Units, M, T, W, TH, F, S, Room, Section — matches
  // parseFacultyLoading's expected layout exactly.
  final rows = <String>[
    _row(1, ['STI COLLEGE BALIUAG']),
    _row(2, ['Confirmation of Faculty Loading']),
    _row(3, ['Instructor:', 'Faculty Member']),
    _row(4, []),
    _row(5, [
      'SUBJECT', 'Units', 'M', 'T', 'W', 'TH', 'F', 'S', 'Room', 'Section',
    ]),
    _row(6, [
      'Human Computer Interaction', null, null, null, null, null, null,
      null, null, 'BSIT 2A',
    ]),
    _row(7, [
      'Lecture', '2', null, '7:00 - 9:00', null, null, null, null,
      'LR 203', null,
    ]),
    _row(8, [
      'Laboratory (3 hours)', '1', null, null, null, '7:00 - 10:00', null,
      null, 'ComLab 1', null,
    ]),
  ];

  final sheetXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
      '<sheetData>${rows.join()}</sheetData>'
      '</worksheet>';

  const contentTypesXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
      '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
      '</Types>';

  const rootRelsXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
      '</Relationships>';

  const workbookXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
      '<sheets><sheet name="CFL" sheetId="1" r:id="rId1"/></sheets>'
      '</workbook>';

  const workbookRelsXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
      '</Relationships>';

  final archive = Archive()
    ..addFile(ArchiveFile.bytes('[Content_Types].xml', utf8.encode(contentTypesXml)))
    ..addFile(ArchiveFile.bytes('_rels/.rels', utf8.encode(rootRelsXml)))
    ..addFile(ArchiveFile.bytes('xl/workbook.xml', utf8.encode(workbookXml)))
    ..addFile(ArchiveFile.bytes('xl/_rels/workbook.xml.rels', utf8.encode(workbookRelsXml)))
    ..addFile(ArchiveFile.bytes('xl/worksheets/sheet1.xml', utf8.encode(sheetXml)));

  final bytes = ZipEncoder().encodeBytes(archive);

  final outDir = Directory('sample_data');
  if (!outDir.existsSync()) outDir.createSync(recursive: true);
  final outFile = File('sample_data/confirmation_of_faculty_loading_sample.xlsx');
  outFile.writeAsBytesSync(bytes);
  // ignore: avoid_print
  print('Wrote ${outFile.path} (${bytes.length} bytes)');
}
