import 'schedule_import_row.dart';

/// Reads every cell's text across every row of [rows], upper-cased, for
/// signature matching. Small inputs only (these are single-sheet
/// per-professor/per-room exports) — building one combined string is
/// simpler and fast enough than a cell-by-cell scan.
String _allCellsText(List<List<String?>> rows) {
  final buffer = StringBuffer();
  for (final row in rows) {
    for (final cell in row) {
      if (cell != null) buffer.write('$cell ');
    }
  }
  return buffer.toString().toUpperCase();
}

/// Determines which of the school's export formats [rows] (as produced
/// by [readFirstSheetRows]) matches, by checking for each format's
/// distinctive header text. Checked in this order because 'CLASS NO'
/// and 'INSTRUCTOR ID' are the most specific signature (both must be
/// present), while the others each match one unambiguous phrase.
ScheduleFileFormat detectScheduleFileFormat(List<List<String?>> rows) {
  final text = _allCellsText(rows);
  if (text.contains('CLASS NO') && text.contains('INSTRUCTOR ID')) {
    return ScheduleFileFormat.classesAndProfessorList;
  }
  if (text.contains('CONFIRMATION OF FACULTY LOADING')) {
    return ScheduleFileFormat.facultyLoading;
  }
  if (text.contains('ROOM SCHEDULE')) {
    return ScheduleFileFormat.roomSchedule;
  }
  if (text.contains('SCHEDULE OF CLASSES')) {
    return ScheduleFileFormat.classSchedule;
  }
  return ScheduleFileFormat.unknown;
}

/// Finds the column index whose header cell (row 0) case-insensitively
/// equals [header], or -1 if not found.
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

/// Parses a Classes+Professor list ("Course and Grade Monitoring"
/// report) into one [ScheduleImportRow] per class offering. This format
/// carries no room/day/time/section — only which subject each professor
/// is assigned to (the Registrar's roster).
List<ScheduleImportRow> parseClassesAndProfessorList(List<List<String?>> rows) {
  if (rows.isEmpty) return [];

  final header = rows.first;
  final codeCol = _columnIndex(header, 'Course Code');
  final titleCol = _columnIndex(header, 'Description');
  final unitCol = _columnIndex(header, 'Course Unit');
  final instructorIdCol = _columnIndex(header, 'Instructor ID');
  final lastNameCol = _columnIndex(header, 'Last Name');
  final firstNameCol = _columnIndex(header, 'First Name');
  final middleNameCol = _columnIndex(header, 'Middle Name');

  final result = <ScheduleImportRow>[];
  for (final row in rows.skip(1)) {
    final code = _cellText(row, codeCol);
    final title = _cellText(row, titleCol);
    if (code == null || title == null) continue; // blank/stray row

    final nameParts = [
      _cellText(row, lastNameCol),
      _cellText(row, firstNameCol),
      _cellText(row, middleNameCol),
    ].whereType<String>();

    result.add(ScheduleImportRow(
      subjectTitle: title,
      subjectCode: code,
      units: double.tryParse(_cellText(row, unitCol) ?? ''),
      instructorId: _cellText(row, instructorIdCol),
      professorName: nameParts.isEmpty ? null : nameParts.join(' '),
    ));
  }
  return result;
}
