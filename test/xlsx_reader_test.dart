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
}
