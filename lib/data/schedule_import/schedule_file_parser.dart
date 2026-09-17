import 'schedule_import_row.dart';
import 'schedule_time_parsing.dart';

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

/// Reads the "Instructor:" labeled cell's neighboring cell — CFL's
/// professor-name header is a two-cell pair (`Instructor:`, name)
/// somewhere in the sheet's first few rows, not tied to the data
/// table's own column layout.
String? _findInstructorName(List<List<String?>> rows) {
  for (final row in rows) {
    for (var i = 0; i < row.length - 1; i++) {
      final value = row[i]?.trim();
      if (value != null && value.toUpperCase() == 'INSTRUCTOR:') {
        final name = row[i + 1]?.trim();
        if (name != null && name.isNotEmpty) return name;
      }
    }
  }
  return null;
}

const _dayColumns = ['M', 'T', 'W', 'TH', 'F', 'S'];

/// Parses a Confirmation of Faculty Loading file into one
/// [ScheduleImportRow] per (subject, component, day, time-range)
/// combination. Every subject row (a row whose first cell is non-blank
/// and isn't itself "Lecture"/"Laboratory (3 hours)") is immediately
/// followed by exactly one Lecture sub-row and one Laboratory sub-row —
/// the file's own established shape. Section is read from the subject
/// row (not the component sub-rows, which leave it blank); Room is read
/// per component sub-row, since lecture and lab can be in different
/// rooms.
List<ScheduleImportRow> parseFacultyLoading(List<List<String?>> rows) {
  final professorName = _findInstructorName(rows);

  final headerIndex = rows.indexWhere((row) =>
      row.any((cell) => cell?.trim().toUpperCase() == 'SUBJECT'));
  if (headerIndex == -1) return [];
  final header = rows[headerIndex];

  final unitsCol = _columnIndex(header, 'Units');
  final roomCol = _columnIndex(header, 'Room');
  final sectionCol = _columnIndex(header, 'Section');
  final dayCols = {
    for (final day in _dayColumns) day: _columnIndex(header, day),
  };

  final result = <ScheduleImportRow>[];
  var i = headerIndex + 1;
  while (i < rows.length) {
    final subjectRow = rows[i];
    final subjectTitle = _cellText(subjectRow, 0);
    if (subjectTitle == null) break; // first fully blank row ends the sheet

    final section = _cellText(subjectRow, sectionCol);
    final componentRows = <(ScheduleComponent, List<String?>)>[];
    if (i + 1 < rows.length &&
        _cellText(rows[i + 1], 0)?.toUpperCase() == 'LECTURE') {
      componentRows.add((ScheduleComponent.lecture, rows[i + 1]));
    }
    if (i + 2 < rows.length &&
        (_cellText(rows[i + 2], 0)?.toUpperCase().startsWith('LABORATORY') ??
            false)) {
      componentRows.add((ScheduleComponent.laboratory, rows[i + 2]));
    }

    for (final (component, row) in componentRows) {
      final units = double.tryParse(_cellText(row, unitsCol) ?? '');
      final room = _cellText(row, roomCol);
      for (final day in _dayColumns) {
        final cellText = _cellText(row, dayCols[day]!);
        if (cellText == null) continue;
        for (final range in extractTimeRanges(cellText)) {
          result.add(ScheduleImportRow(
            subjectTitle: subjectTitle,
            component: component,
            section: section,
            professorName: professorName,
            room: room,
            day: day,
            startTime: range.start,
            endTime: range.end,
            units: units,
          ));
        }
      }
    }
    i += 1 + componentRows.length;
  }
  return result;
}

/// The Room Schedule format names the room on the line directly under
/// the "ROOM SCHEDULE" title, not as a table column. Returns the first
/// non-blank cell found after the title row.
String? _findRoomScheduleRoomName(List<List<String?>> rows) {
  final titleIndex = rows.indexWhere((row) =>
      row.any((cell) => cell?.trim().toUpperCase() == 'ROOM SCHEDULE'));
  if (titleIndex == -1 || titleIndex + 1 >= rows.length) return null;
  for (final cell in rows[titleIndex + 1]) {
    final text = cell?.trim();
    if (text != null && text.isNotEmpty) return text;
  }
  return null;
}

/// Parses a Room Schedule file into one [ScheduleImportRow] per
/// (subject, component, day, time-range) combination. Same subject-row-
/// plus-component-sub-row shape as CFL (Task 4), but unlike CFL a
/// subject here is not guaranteed to have both a Lecture and a
/// Laboratory sub-row — a lab-only subject's Laboratory row sits
/// directly at `i + 1`, with no blank Lecture row before it — so
/// sub-rows are consumed sequentially by their own label rather than by
/// fixed offset. The room is the whole sheet's own header (not a
/// per-row column) and there is no Units column in this format.
List<ScheduleImportRow> parseRoomSchedule(List<List<String?>> rows) {
  final room = _findRoomScheduleRoomName(rows);

  final headerIndex = rows.indexWhere((row) =>
      row.any((cell) => cell?.trim().toUpperCase() == 'SUBJECT'));
  if (headerIndex == -1) return [];
  final header = rows[headerIndex];

  final instructorCol = _columnIndex(header, 'Instructor');
  final sectionCol = _columnIndex(header, 'Section');
  final dayCols = {
    for (final day in _dayColumns) day: _columnIndex(header, day),
  };

  final result = <ScheduleImportRow>[];
  var i = headerIndex + 1;
  while (i < rows.length) {
    final subjectRow = rows[i];
    final subjectTitle = _cellText(subjectRow, 0);
    if (subjectTitle == null) break;

    final section = _cellText(subjectRow, sectionCol);
    final componentRows = <(ScheduleComponent, List<String?>)>[];
    var cursor = i + 1;
    if (cursor < rows.length &&
        _cellText(rows[cursor], 0)?.toUpperCase() == 'LECTURE') {
      componentRows.add((ScheduleComponent.lecture, rows[cursor]));
      cursor++;
    }
    if (cursor < rows.length &&
        (_cellText(rows[cursor], 0)?.toUpperCase().startsWith('LABORATORY') ??
            false)) {
      componentRows.add((ScheduleComponent.laboratory, rows[cursor]));
      cursor++;
    }

    for (final (component, row) in componentRows) {
      final professorName = _cellText(row, instructorCol);
      for (final day in _dayColumns) {
        final cellText = _cellText(row, dayCols[day]!);
        if (cellText == null) continue;
        for (final range in extractTimeRanges(cellText)) {
          result.add(ScheduleImportRow(
            subjectTitle: subjectTitle,
            component: component,
            section: section,
            professorName: professorName,
            room: room,
            day: day,
            startTime: range.start,
            endTime: range.end,
          ));
        }
      }
    }
    i = cursor;
  }
  return result;
}
