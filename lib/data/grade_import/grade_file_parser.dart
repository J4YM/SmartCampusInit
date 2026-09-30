import 'grade_import_row.dart';

String? _cell(List<String?> row, int index) {
  if (index < 0 || index >= row.length) return null;
  final text = row[index]?.trim();
  return (text == null || text.isEmpty) ? null : text;
}

double? _parseDouble(String? text) => text == null ? null : double.tryParse(text);
int? _parseInt(String? text) => text == null ? null : int.tryParse(text);

/// Parses the registrar's "Candidates for Academic Honors" GPA export — a
/// canned, automated report (unlike the hand-built enrollment/schedule
/// import files) with a fixed two-row merged header, so — unlike
/// enrollment_file_parser.dart/schedule_file_parser.dart's name-based
/// column lookup — this reads columns by fixed position. Built against
/// this exact layout (0-indexed):
///
///   0 Student ID | 1 First Name | 3 Middle Name | 4 Last Name |
///   5 Suffix | 7 Gender | 9 Program | 10 Level | 11 Transfer Units |
///   12 No of Failed Courses | 13 Units Taken (cumulative) |
///   15 GPA (cumulative) | 17 Units Taken (current term) |
///   22 GPA (current term) | 24+ Course 1..10 (name/grade/units triples,
///   not parsed — see GradeImportRow's own doc comment)
///
/// "GPA" and "Units Taken" each appear twice in the real header (once
/// under a "Cummulative" section, once under "Current Term") — a
/// name-based lookup like the other parsers use would only ever find the
/// first (cumulative) occurrence, which is why this parses by position
/// instead once the header row is located.
///
/// Also reads the "SY & Term:" banner row (e.g. "2025-2026/2nd Term",
/// split on the first "/") that appears above the header — every row in
/// the file shares that same term, so it's returned once on
/// [ParsedGradeFile] rather than duplicated per row. Returns null when
/// either the term banner or the "Student ID" header can't be found —
/// GradeImportRunner turns that into a clear user-facing error rather
/// than silently importing zero rows.
ParsedGradeFile? parseGradeFile(List<List<String?>> rows) {
  String? schoolYear;
  String? term;
  for (final row in rows) {
    final label = _cell(row, 0)?.toLowerCase();
    if (label != null && label.startsWith('sy & term')) {
      final value = _cell(row, 2);
      final slash = value?.indexOf('/') ?? -1;
      if (value != null && slash > 0) {
        schoolYear = value.substring(0, slash).trim();
        term = value.substring(slash + 1).trim();
      }
      break;
    }
  }
  if (schoolYear == null ||
      schoolYear.isEmpty ||
      term == null ||
      term.isEmpty) {
    return null;
  }

  final headerIndex = rows.indexWhere(
      (row) => _cell(row, 0)?.toUpperCase() == 'STUDENT ID');
  if (headerIndex == -1) return null;

  final result = <GradeImportRow>[];
  for (final row in rows.skip(headerIndex + 1)) {
    final studentNumber = _cell(row, 0);
    final firstName = _cell(row, 1);
    final lastName = _cell(row, 4);
    if (studentNumber == null || firstName == null || lastName == null) {
      continue; // blank/stray row
    }
    result.add(GradeImportRow(
      studentNumber: studentNumber,
      firstName: firstName,
      lastName: lastName,
      middleName: _cell(row, 3),
      suffix: _cell(row, 5),
      transferUnits: _parseDouble(_cell(row, 11)),
      failedCoursesCount: _parseInt(_cell(row, 12)),
      cumulativeUnitsTaken: _parseDouble(_cell(row, 13)),
      cumulativeGpa: _parseDouble(_cell(row, 15)),
      currentTermUnitsTaken: _parseDouble(_cell(row, 17)),
      currentTermGpa: _parseDouble(_cell(row, 22)),
    ));
  }

  return ParsedGradeFile(schoolYear: schoolYear, term: term, rows: result);
}
