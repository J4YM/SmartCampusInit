// scripts/generate_curriculum_sample_xlsx.dart
//
// Turns sample_data/curriculum/curriculum_upload_template.csv into the Excel
// equivalent the Registrar's Curriculum tab upload accepts:
//
//   sample_data/curriculum/curriculum_upload_sample.xlsx
//     -> lib/data/curriculum_import/curriculum_file_parser.dart
//        (Program, Year, Term, Code, Title, Units, Prerequisites)
//
// Year / Term / Units are written as real numeric cells (what Excel produces
// when a person types them); everything else is text. Year/Term 0 marks a
// "List of Electives" row.
//
// Deterministic, so re-running yields an identical file.
//
// Usage: dart run scripts/generate_curriculum_sample_xlsx.dart [out.xlsx]

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:capstone_dashboard/data/curriculum_import/curriculum_file_parser.dart';

String _colLetter(int i) => String.fromCharCode('A'.codeUnitAt(0) + i);

String _esc(String v) =>
    v.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

// Columns (0-based) holding numbers: Year, Term, Units.
const _numericColumns = {1, 2, 5};

List<int> _buildXlsx(String sheetName, List<List<String?>> rows) {
  final sheetRows = StringBuffer();
  for (var r = 0; r < rows.length; r++) {
    final cells = StringBuffer();
    for (var c = 0; c < rows[r].length; c++) {
      final v = rows[r][c];
      if (v == null || v.isEmpty) continue;
      final ref = '${_colLetter(c)}${r + 1}';
      if (r > 0 && _numericColumns.contains(c)) {
        cells.write('<c r="$ref"><v>$v</v></c>');
      } else {
        cells.write('<c r="$ref" t="inlineStr"><is><t>${_esc(v)}</t></is></c>');
      }
    }
    sheetRows.write('<row r="${r + 1}">$cells</row>');
  }
  final sheetXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
      '<sheetData>$sheetRows</sheetData></worksheet>';

  const contentTypes = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
      '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
      '</Types>';
  const rootRels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
      '</Relationships>';
  final workbook = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
      '<sheets><sheet name="$sheetName" sheetId="1" r:id="rId1"/></sheets></workbook>';
  const workbookRels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
      '</Relationships>';

  final archive = Archive()
    ..addFile(ArchiveFile.bytes('[Content_Types].xml', utf8.encode(contentTypes)))
    ..addFile(ArchiveFile.bytes('_rels/.rels', utf8.encode(rootRels)))
    ..addFile(ArchiveFile.bytes('xl/workbook.xml', utf8.encode(workbook)))
    ..addFile(ArchiveFile.bytes('xl/_rels/workbook.xml.rels', utf8.encode(workbookRels)))
    ..addFile(ArchiveFile.bytes('xl/worksheets/sheet1.xml', utf8.encode(sheetXml)));
  return ZipEncoder().encodeBytes(archive);
}

void main(List<String> args) {
  final csv = File('sample_data/curriculum/curriculum_upload_template.csv')
      .readAsStringSync();
  final rows = parseCsvText(csv);
  final out = args.isNotEmpty
      ? args.first
      : 'sample_data/curriculum/curriculum_upload_sample.xlsx';
  File(out).writeAsBytesSync(_buildXlsx('Curriculum', rows));
  stdout.writeln('Wrote $out (${rows.length - 1} course rows)');
}
