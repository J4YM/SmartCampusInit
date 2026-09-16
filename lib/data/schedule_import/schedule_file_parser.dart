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
