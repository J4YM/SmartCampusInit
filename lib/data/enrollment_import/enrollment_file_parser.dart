import 'enrollment_import_row.dart';

int _columnIndex(List<String?> headerRow, String header) {
  for (var i = 0; i < headerRow.length; i++) {
    final text = headerRow[i]?.trim();
    if (text != null && text.toUpperCase() == header.toUpperCase()) {
      return i;
    }
  }
  return -1;
}

String? _cellText(List<String?> row, int column) {
  if (column < 0 || column >= row.length) return null;
  final text = row[column]?.trim();
  return (text == null || text.isEmpty) ? null : text;
}

/// Accepts "1st Year"/"2nd Year"/... (matching AddStudentDialog's own
/// dropdown options), a bare number ("1", "3"), or any text with a
/// leading digit ("1 - Freshman") — the real file's exact wording for
/// this column isn't confirmed against filled sample data yet, so this
/// favors matching more spellings over being strict. Returns null (not a
/// crash) for anything else; EnrollmentImportRunner falls back to the
/// batch's chosen section in that case.
int? _parseYearLevel(String? text) {
  if (text == null) return null;
  final match = RegExp(r'^(\d+)').firstMatch(text);
  return match == null ? null : int.tryParse(match.group(1)!);
}

/// Parses the Registrar's "Student Information" batch enrollment export
/// into one [EnrollmentImportRow] per student. Same header-row search as
/// the schedule-import parsers (schedule_file_parser.dart) — a banner/
/// title row above the real header can't be assumed away, and the real
/// export this was built against has the header on row 1 with no banner,
/// but this stays defensive rather than hard-coding that.
List<EnrollmentImportRow> parseEnrollmentFile(List<List<String?>> rows) {
  final headerIndex = rows.indexWhere(
      (row) => row.any((cell) => cell?.trim().toUpperCase() == 'STUDENT ID'));
  if (headerIndex == -1) return [];

  final header = rows[headerIndex];
  final idCol = _columnIndex(header, 'Student ID');
  final lastNameCol = _columnIndex(header, 'Last Name');
  final suffixCol = _columnIndex(header, 'Suffix');
  final firstNameCol = _columnIndex(header, 'First Name');
  final middleNameCol = _columnIndex(header, 'Middle Name');
  final programCol = _columnIndex(header, 'Program');
  final levelCol = _columnIndex(header, 'Level');
  final emailCol = _columnIndex(header, 'Campus Email Address');

  final result = <EnrollmentImportRow>[];
  for (final row in rows.skip(headerIndex + 1)) {
    final studentNumber = _cellText(row, idCol);
    final lastName = _cellText(row, lastNameCol);
    final firstName = _cellText(row, firstNameCol);
    if (studentNumber == null || lastName == null || firstName == null) {
      continue; // blank/stray row
    }
    result.add(EnrollmentImportRow(
      studentNumber: studentNumber,
      firstName: firstName,
      lastName: lastName,
      middleName: _cellText(row, middleNameCol),
      suffix: _cellText(row, suffixCol),
      course: _cellText(row, programCol),
      yearLevel: _parseYearLevel(_cellText(row, levelCol)),
      email: _cellText(row, emailCol),
    ));
  }
  return result;
}
