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

const _relationshipsNs =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';

/// Resolves every worksheet's (tab name, file name) pair, in tab order,
/// via xl/workbook.xml's `<sheets>` order and xl/_rels/workbook.xml.rels'
/// id-to-target mapping. A real, multi-year-reused workbook accumulates
/// sheets whose filenames no longer match tab order at all — Excel never
/// renumbers a surviving sheet's underlying file when others are added/
/// removed/reordered, so "Sheet1" (first tab) can easily be saved as
/// sheet3.xml while sheet1.xml is some other, no-longer-first tab (or a
/// leftover tab that isn't the one this plan's formats actually live on
/// at all — some real exports put the target table on a second or third
/// tab, not the first). Returns null (the caller falls back to matching
/// `sheetN.xml` by name in the zip's own file order) if either workbook
/// part is missing or doesn't parse — keeps this working for minimal/
/// synthetic archives (e.g. this file's own tests) that don't bother with
/// a real workbook.xml.
List<({String name, String fileName})>? _resolveSheetsInTabOrder(Archive archive) {
  ArchiveFile? workbookFile;
  ArchiveFile? relsFile;
  for (final file in archive.files) {
    if (file.name == 'xl/workbook.xml') workbookFile = file;
    if (file.name == 'xl/_rels/workbook.xml.rels') relsFile = file;
  }
  if (workbookFile == null || relsFile == null) return null;

  try {
    final relsDoc = XmlDocument.parse(utf8.decode(relsFile.content));
    final targetByRid = <String, String>{};
    for (final rel in relsDoc.findAllElements('Relationship')) {
      final id = rel.getAttribute('Id');
      final target = rel.getAttribute('Target');
      if (id == null || target == null) continue;
      // Targets are relative to xl/ (occasionally already prefixed with
      // it, or with a leading "/xl/" for a package-absolute form).
      final normalized = target
          .replaceFirst(RegExp(r'^/?xl/'), '')
          .replaceFirst(RegExp(r'^/'), '');
      targetByRid[id] = 'xl/$normalized';
    }

    final workbookDoc = XmlDocument.parse(utf8.decode(workbookFile.content));
    final result = <({String name, String fileName})>[];
    for (final sheet in workbookDoc.findAllElements('sheet')) {
      String? rid;
      for (final a in sheet.attributes) {
        if (a.name.local == 'id' && a.name.namespaceUri == _relationshipsNs) {
          rid = a.value;
          break;
        }
      }
      final fileName = rid == null ? null : targetByRid[rid];
      if (fileName == null) continue;
      result.add((name: sheet.getAttribute('name') ?? fileName, fileName: fileName));
    }
    return result.isEmpty ? null : result;
  } catch (_) {
    return null;
  }
}

/// Every worksheet name paired with its file, in the archive, keyed by
/// file name — the shared lookup [readAllSheets]/[readFirstSheetRows]
/// both build once per call.
Map<String, ArchiveFile> _sheetFilesByName(Archive archive) {
  final sheetFilePattern = RegExp(r'^xl/worksheets/sheet\d+\.xml$');
  return {
    for (final file in archive.files)
      if (sheetFilePattern.hasMatch(file.name)) file.name: file,
  };
}

/// Reads every worksheet in an .xlsx file's raw bytes, in tab order, each
/// as a dense List<List<String?>> — see [_parseWorksheetRows]. Needed
/// because a real, evolved workbook can carry the target table on any
/// tab, not necessarily the first (a cover/notes/summary sheet ahead of
/// it is common) — [ScheduleImportRunner] checks each in turn for a
/// recognized format instead of assuming the first is always right.
List<({String name, List<List<String?>> rows})> readAllSheets(Uint8List xlsxBytes) {
  final archive = ZipDecoder().decodeBytes(xlsxBytes);

  String? sharedStringsXml;
  for (final file in archive.files) {
    if (file.name == 'xl/sharedStrings.xml') sharedStringsXml = utf8.decode(file.content);
  }
  final sharedStrings = _parseSharedStrings(sharedStringsXml);

  final sheetFiles = _sheetFilesByName(archive);
  final tabOrder = _resolveSheetsInTabOrder(archive);
  final ordered = tabOrder ??
      [
        for (final entry in sheetFiles.entries)
          (name: entry.key, fileName: entry.key),
      ];

  return [
    for (final sheet in ordered)
      if (sheetFiles[sheet.fileName] case final file?)
        (
          name: sheet.name,
          rows: _parseWorksheetRows(utf8.decode(file.content), sharedStrings),
        ),
  ];
}

/// Reads the first worksheet (by tab order) of an .xlsx file's raw bytes
/// into a dense List<List<String?>> — one entry per cell, in row-major
/// order, null for blank cells.
///
/// This is a minimal, purpose-built reader (not a general-purpose Excel
/// library) using only `archive` and `xml` — both already depended on by
/// this repo (for docx_creator's DOCX writing) at versions already
/// proven compatible with every build target this repo has, including
/// Netlify's pinned old Dart SDK. See this plan's Tech Stack section for
/// why no third-party Excel-reading package could be used instead. Kept
/// for callers that only ever want the first sheet; [ScheduleImportRunner]
/// itself uses [readAllSheets] instead, since the target table isn't
/// always on the first tab.
List<List<String?>> readFirstSheetRows(Uint8List xlsxBytes) {
  final sheets = readAllSheets(xlsxBytes);
  return sheets.isEmpty ? [] : sheets.first.rows;
}
