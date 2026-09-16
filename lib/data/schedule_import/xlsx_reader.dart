import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// Decodes an Excel-style column reference ("A" -> 0, "B" -> 1, ...,
/// "Z" -> 25, "AA" -> 26, "AB" -> 27, ...) into a zero-based column
/// index.
int _columnLettersToIndex(String letters) {
  var index = 0;
  for (var i = 0; i < letters.length; i++) {
    index = index * 26 + (letters.codeUnitAt(i) - 'A'.codeUnitAt(0) + 1);
  }
  return index - 1;
}

/// Splits a cell reference like "B7" or "AA123" into its column letters
/// ("B"/"AA") and row number (7/123).
({String columnLetters, int rowNumber}) _splitCellRef(String cellRef) {
  final match = RegExp(r'^([A-Z]+)(\d+)$').firstMatch(cellRef);
  if (match == null) {
    throw FormatException('Not a valid cell reference: $cellRef');
  }
  return (columnLetters: match.group(1)!, rowNumber: int.parse(match.group(2)!));
}

/// Returns the text content of the first child element named [childName]
/// under [parent], or null if there isn't one. A small manual helper
/// rather than `.firstOrNull` on the `findElements` iterable, to avoid
/// depending on an extension method that may need a separate import.
String? _firstChildText(XmlElement parent, String childName) {
  for (final child in parent.findElements(childName)) {
    return child.innerText;
  }
  return null;
}

/// Parses xl/sharedStrings.xml's <si> entries into an ordered list of
/// plain strings, in the order Excel indexes them (a cell with t="s"
/// references these by position). Each <si> either holds one direct <t>
/// or several <r><t> "rich text runs" to concatenate — both forms are
/// handled. Returns an empty list when there is no shared strings part
/// at all (a sheet with only inline/numeric cells doesn't need one).
List<String> _parseSharedStrings(String? xmlContent) {
  if (xmlContent == null) return [];
  final document = XmlDocument.parse(xmlContent);
  final result = <String>[];
  for (final si in document.findAllElements('si')) {
    final direct = _firstChildText(si, 't');
    if (direct != null) {
      result.add(direct);
      continue;
    }
    final buffer = StringBuffer();
    for (final run in si.findElements('r')) {
      buffer.write(_firstChildText(run, 't') ?? '');
    }
    result.add(buffer.toString());
  }
  return result;
}

/// Parses one worksheet XML's <row>/<c> structure into a dense
/// List<List<String?>>, resolving shared-string indices via
/// [sharedStrings]. XLSX omits blank cells from the XML entirely, so
/// column positions are computed from each cell's own `r` attribute, not
/// assumed sequential — a blank cell becomes null, and rows are padded
/// to the widest row seen.
List<List<String?>> _parseWorksheetRows(String sheetXmlContent, List<String> sharedStrings) {
  final document = XmlDocument.parse(sheetXmlContent);
  final rows = <int, Map<int, String?>>{};
  var maxColumn = -1;

  for (final rowElement in document.findAllElements('row')) {
    final rowNumberAttr = rowElement.getAttribute('r');
    if (rowNumberAttr == null) continue;
    final rowIndex = int.parse(rowNumberAttr) - 1;
    final rowCells = rows.putIfAbsent(rowIndex, () => {});

    for (final cellElement in rowElement.findElements('c')) {
      final cellRefAttr = cellElement.getAttribute('r');
      if (cellRefAttr == null) continue;
      final ref = _splitCellRef(cellRefAttr);
      final columnIndex = _columnLettersToIndex(ref.columnLetters);
      if (columnIndex > maxColumn) maxColumn = columnIndex;

      final type = cellElement.getAttribute('t');
      String? value;
      if (type == 's') {
        final raw = _firstChildText(cellElement, 'v');
        final index = raw == null ? null : int.tryParse(raw);
        value = (index != null && index >= 0 && index < sharedStrings.length)
            ? sharedStrings[index]
            : null;
      } else if (type == 'inlineStr') {
        String? inlineText;
        for (final isElement in cellElement.findElements('is')) {
          inlineText = _firstChildText(isElement, 't');
          break;
        }
        value = inlineText;
      } else {
        value = _firstChildText(cellElement, 'v');
      }
      rowCells[columnIndex] = value;
    }
  }

  if (rows.isEmpty) return [];
  final maxRow = rows.keys.reduce((a, b) => a > b ? a : b);
  return List.generate(maxRow + 1, (r) {
    final rowCells = rows[r] ?? const {};
    return List.generate(maxColumn + 1, (c) => rowCells[c]);
  });
}

/// Reads the first worksheet of an .xlsx file's raw bytes into a dense
/// List<List<String?>> — one entry per cell, in row-major order, null
/// for blank cells.
///
/// This is a minimal, purpose-built reader (not a general-purpose Excel
/// library) using only `archive` and `xml` — both already depended on by
/// this repo (for docx_creator's DOCX writing) at versions already
/// proven compatible with every build target this repo has, including
/// Netlify's pinned old Dart SDK. See this plan's Tech Stack section for
/// why no third-party Excel-reading package could be used instead. Reads
/// only the FIRST worksheet found in the zip's natural file order —
/// every format this plan parses is single-sheet.
List<List<String?>> readFirstSheetRows(Uint8List xlsxBytes) {
  final archive = ZipDecoder().decodeBytes(xlsxBytes);

  String? sharedStringsXml;
  ArchiveFile? firstSheetFile;
  final sheetFilePattern = RegExp(r'^xl/worksheets/sheet\d+\.xml$');
  for (final file in archive.files) {
    if (file.name == 'xl/sharedStrings.xml') {
      sharedStringsXml = utf8.decode(file.content);
    } else if (firstSheetFile == null && sheetFilePattern.hasMatch(file.name)) {
      firstSheetFile = file;
    }
  }
  if (firstSheetFile == null) return [];

  final sharedStrings = _parseSharedStrings(sharedStringsXml);
  final sheetXml = utf8.decode(firstSheetFile.content);
  return _parseWorksheetRows(sheetXml, sharedStrings);
}
