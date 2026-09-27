import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:capstone_dashboard/data/schedule_import/xlsx_reader.dart';

Uint8List _buildMinimalXlsx({
  required String sheetXml,
  String? sharedStringsXml,
}) {
  final archive = Archive();
  if (sharedStringsXml != null) {
    archive.addFile(ArchiveFile.bytes('xl/sharedStrings.xml', utf8.encode(sharedStringsXml)));
  }
  archive.addFile(ArchiveFile.bytes('xl/worksheets/sheet1.xml', utf8.encode(sheetXml)));
  return ZipEncoder().encodeBytes(archive);
}

const _sharedStringsXml = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="2" uniqueCount="2">
  <si><t>Hello</t></si>
  <si><t>World</t></si>
</sst>
''';

void main() {
  test('reads shared strings, an inline string, a plain cell, a blank cell, and a skipped row', () {
    final bytes = _buildMinimalXlsx(
      sharedStringsXml: _sharedStringsXml,
      sheetXml: '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <sheetData>
    <row r="1">
      <c r="A1" t="s"><v>0</v></c>
      <c r="B1" t="s"><v>1</v></c>
    </row>
    <row r="3">
      <c r="A3" t="inlineStr"><is><t>Direct</t></is></c>
      <c r="C3"><v>42</v></c>
    </row>
  </sheetData>
</worksheet>
''',
    );

    final rows = readFirstSheetRows(bytes);
    expect(rows, [
      ['Hello', 'World', null],
      [null, null, null],
      ['Direct', null, '42'],
    ]);
  });

  test('decodes multi-letter column references (AA is column index 26)', () {
    final bytes = _buildMinimalXlsx(
      sharedStringsXml: '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="1" uniqueCount="1">
  <si><t>Far column</t></si>
</sst>
''',
      sheetXml: '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <sheetData>
    <row r="1">
      <c r="AA1" t="s"><v>0</v></c>
    </row>
  </sheetData>
</worksheet>
''',
    );

    final rows = readFirstSheetRows(bytes);
    expect(rows.single, hasLength(27));
    expect(rows.single[26], 'Far column');
  });

  test('returns an empty list when there is no worksheet in the archive', () {
    final archive = Archive();
    archive.addFile(ArchiveFile.bytes('xl/other.xml', utf8.encode('<x/>')));
    final bytes = ZipEncoder().encodeBytes(archive);
    expect(readFirstSheetRows(bytes), isEmpty);
  });

  test('works with no sharedStrings.xml at all (only inline/numeric cells)', () {
    final bytes = _buildMinimalXlsx(sheetXml: '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <sheetData>
    <row r="1">
      <c r="A1"><v>7</v></c>
    </row>
  </sheetData>
</worksheet>
''');
    expect(readFirstSheetRows(bytes), [['7']]);
  });

  test('reads the workbook\'s first TAB, not just "sheet1.xml" by name', () {
    // A real, multi-year-reused workbook accumulates sheets whose
    // filenames no longer match tab order — Excel never renumbers a
    // surviving sheet's file when others are added/reordered. Here
    // sheet1.xml is actually the SECOND tab; sheet2.xml is the first.
    final archive = Archive();
    archive.addFile(ArchiveFile.bytes('xl/workbook.xml', utf8.encode('''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"
          xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheets>
    <sheet name="ActuallyFirst" sheetId="1" r:id="rId2"/>
    <sheet name="Leftover" sheetId="2" r:id="rId1"/>
  </sheets>
</workbook>
''')));
    archive.addFile(ArchiveFile.bytes('xl/_rels/workbook.xml.rels', utf8.encode('''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/>
</Relationships>
''')));
    archive.addFile(ArchiveFile.bytes('xl/worksheets/sheet1.xml', utf8.encode('''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <sheetData>
    <row r="1"><c r="A1" t="inlineStr"><is><t>Wrong sheet</t></is></c></row>
  </sheetData>
</worksheet>
''')));
    archive.addFile(ArchiveFile.bytes('xl/worksheets/sheet2.xml', utf8.encode('''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <sheetData>
    <row r="1"><c r="A1" t="inlineStr"><is><t>Right sheet</t></is></c></row>
  </sheetData>
</worksheet>
''')));
    final bytes = ZipEncoder().encodeBytes(archive);

    expect(readFirstSheetRows(bytes), [
      ['Right sheet'],
    ]);
  });

  test('concatenates a shared string built from multiple rich-text runs', () {
    // Excel emits <si><r><t>...</t></r>...</si> (no direct <t> child)
    // whenever a shared string has inline formatting applied to only
    // part of it (e.g. one bold word) — each formatted span becomes its
    // own <r> run, and the runs must be concatenated in document order.
    final bytes = _buildMinimalXlsx(
      sharedStringsXml: '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="1" uniqueCount="1">
  <si><r><t>Hello </t></r><r><t>World</t></r><r><t>!</t></r></si>
</sst>
''',
      sheetXml: '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <sheetData>
    <row r="1">
      <c r="A1" t="s"><v>0</v></c>
    </row>
  </sheetData>
</worksheet>
''',
    );

    final rows = readFirstSheetRows(bytes);
    expect(rows, [
      ['Hello World!'],
    ]);
  });
}
