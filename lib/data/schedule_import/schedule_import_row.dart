/// A subject/professor/room/day/time-range component (0 or 1) parsed
/// from one of the school's export formats. Roster-only rows (from the
/// Classes+Professor list) leave [component]/[section]/[room]/[day]/
/// [startTime]/[endTime] null — that format carries no meeting detail at
/// all, only which subject a professor is assigned to.
enum ScheduleComponent { lecture, laboratory }

class ScheduleImportRow {
  const ScheduleImportRow({
    required this.subjectTitle,
    this.subjectCode,
    this.component,
    this.section,
    this.professorName,
    this.instructorId,
    this.room,
    this.day,
    this.startTime,
    this.endTime,
    this.units,
  });

  /// Always present — every format names the subject by its title.
  final String subjectTitle;

  /// Only the Classes+Professor list carries a course code. CFL/Room
  /// Schedule identify subjects by title only.
  final String? subjectCode;

  /// Null when the subject has no lecture/laboratory split.
  final ScheduleComponent? component;

  /// Section label as it appears in the source file (e.g. "BSIT 2A") —
  /// not yet normalized against `sections.name`.
  final String? section;

  /// Full name as it appears in CFL/Room Schedule (e.g.
  /// "Ronald Christian Pallorina"). Null for Classes+Professor list rows,
  /// which identify the professor by [instructorId] instead.
  final String? professorName;

  /// Only the Classes+Professor list carries this.
  final String? instructorId;

  /// Room name as it appears in the source file — not yet resolved
  /// against `room_aliases`.
  final String? room;

  /// One of 'M', 'T', 'W', 'TH', 'F', 'S'. Null for a roster-only row.
  final String? day;

  /// 24-hour "HH:MM". Null for a roster-only row.
  final String? startTime;

  /// 24-hour "HH:MM". Null for a roster-only row.
  final String? endTime;

  /// Course unit count, when the source row carries one.
  final double? units;
}

/// Which of the school's export formats a file matches.
enum ScheduleFileFormat {
  classesAndProfessorList,
  facultyLoading,
  roomSchedule,
  classSchedule,
  unknown,
}
