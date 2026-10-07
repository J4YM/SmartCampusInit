/// One course placement parsed from a curriculum upload: which program/year/
/// term a subject (code + title + units) belongs to, with its prerequisites.
/// `yearLevel`/`term` 0 means "List of Electives" (no fixed year/term).
class CurriculumRow {
  const CurriculumRow({
    required this.program,
    required this.yearLevel,
    required this.term,
    required this.code,
    required this.title,
    required this.units,
    this.prerequisites,
  });

  final String program;
  final int yearLevel;
  final int term;
  final String code;
  final String title;
  final num units;
  final String? prerequisites;
}

class ParsedCurriculum {
  const ParsedCurriculum({required this.rows, required this.errors});

  final List<CurriculumRow> rows;

  /// Human-readable problems (bad row skipped), e.g. "Row 12: missing units".
  final List<String> errors;
}

/// Splits CSV text into rows of cells. Handles quoted cells containing
/// commas, doubled quotes and newlines; tolerates CRLF and a leading BOM.
List<List<String?>> parseCsvText(String text) {
  final rows = <List<String?>>[];
  var row = <String?>[];
  final cell = StringBuffer();
  var inQuotes = false;
  if (text.startsWith('﻿')) text = text.substring(1);

  void endCell() {
    row.add(cell.toString());
    cell.clear();
  }

  void endRow() {
    endCell();
    if (row.any((c) => c != null && c.trim().isNotEmpty)) rows.add(row);
    row = <String?>[];
  }

  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (inQuotes) {
      if (ch == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        cell.write(ch);
      }
    } else if (ch == '"') {
      inQuotes = true;
    } else if (ch == ',') {
      endCell();
    } else if (ch == '\n') {
      endRow();
    } else if (ch == '\r') {
      // swallowed; the following \n ends the row
    } else {
      cell.write(ch);
    }
  }
  if (cell.isNotEmpty || row.isNotEmpty) endRow();
  return rows;
}

const _headerAliases = <String, List<String>>{
  'program': ['program', 'course', 'degree', 'curriculum'],
  'year': ['year', 'yearlevel', 'year level', 'yr'],
  'term': ['term', 'semester', 'sem'],
  'code': ['code', 'coursecode', 'course code', 'subjectcode', 'subject code'],
  'title': ['title', 'subject', 'coursetitle', 'course title', 'description',
      'subject title', 'name'],
  'units': ['units', 'unit', 'credits'],
  'prerequisites': ['prerequisites', 'prerequisite', 'prerequisite(s)',
      'prereq', 'pre-requisite(s)', 'pre-requisites'],
};

String? _cell(List<String?> row, int index) {
  if (index < 0 || index >= row.length) return null;
  final text = row[index]?.trim();
  return (text == null || text.isEmpty) ? null : text;
}

/// "1", "1st", "1st Year", "Year 2" -> 1/2; "Elective(s)" -> 0.
int? _parseLevel(String? text) {
  if (text == null) return null;
  if (text.toLowerCase().startsWith('elective')) return 0;
  final match = RegExp(r'\d+').firstMatch(text);
  return match == null ? null : int.tryParse(match.group(0)!);
}

/// Parses an uploaded curriculum sheet (CSV text rows or the first sheet of
/// an .xlsx). Columns are found by header name, any order:
/// `Program, Year, Term, Code, Title, Units, Prerequisites` (aliases such as
/// "Course Code", "Subject", "Semester" are accepted). Prerequisites is
/// optional. Rows with a missing/invalid required field are skipped and
/// reported in [ParsedCurriculum.errors] rather than aborting the whole file.
/// Returns null when no header row with the required columns is found.
ParsedCurriculum? parseCurriculumRows(List<List<String?>> rows) {
  var headerIndex = -1;
  final columns = <String, int>{};
  for (var r = 0; r < rows.length && r < 15; r++) {
    final found = <String, int>{};
    for (var c = 0; c < rows[r].length; c++) {
      final name = rows[r][c]?.trim().toLowerCase();
      if (name == null || name.isEmpty) continue;
      for (final entry in _headerAliases.entries) {
        if (!found.containsKey(entry.key) && entry.value.contains(name)) {
          found[entry.key] = c;
        }
      }
    }
    if (['program', 'year', 'term', 'code', 'title', 'units']
        .every(found.containsKey)) {
      headerIndex = r;
      columns.addAll(found);
      break;
    }
  }
  if (headerIndex == -1) return null;

  final result = <CurriculumRow>[];
  final errors = <String>[];
  for (var r = headerIndex + 1; r < rows.length; r++) {
    final row = rows[r];
    if (row.every((c) => c == null || c.trim().isEmpty)) continue;
    final label = 'Row ${r + 1}';

    final program = _cell(row, columns['program']!);
    final code = _cell(row, columns['code']!)?.toUpperCase().replaceAll(' ', '');
    final title = _cell(row, columns['title']!);
    final year = _parseLevel(_cell(row, columns['year']!));
    final term = _parseLevel(_cell(row, columns['term']!));
    final units = num.tryParse(_cell(row, columns['units']!) ?? '');

    final missing = <String>[
      if (program == null) 'program',
      if (code == null) 'code',
      if (title == null) 'title',
      if (year == null) 'year',
      if (term == null) 'term',
      if (units == null) 'units',
    ];
    if (missing.isNotEmpty) {
      errors.add('$label: missing or invalid ${missing.join(', ')}');
      continue;
    }

    final prereqIndex = columns['prerequisites'];
    result.add(CurriculumRow(
      program: program!,
      yearLevel: year!,
      term: term!,
      code: code!,
      title: title!,
      units: units!,
      prerequisites: prereqIndex == null ? null : _cell(row, prereqIndex),
    ));
  }
  return ParsedCurriculum(rows: result, errors: errors);
}
