import 'schedule_import_row.dart';

const _minutesPerLectureUnit = 60;
const _minutesPerLabUnit = 180;

/// Total weekly minutes a subject's unit counts imply. Verified against
/// every sample row reviewed for this feature (see the plan's Global
/// Constraints): 1 lecture unit = 1 hour/week, 1 laboratory unit = 3
/// hours/week, and a subject with no lecture/lab split maps its whole
/// unit count 1:1 to hours.
int expectedWeeklyMinutes({
  required double? lectureUnits,
  required double? labUnits,
  required double? plainUnits,
}) {
  if (plainUnits != null) return (plainUnits * 60).round();
  final lectureMinutes = (lectureUnits ?? 0) * _minutesPerLectureUnit;
  final labMinutes = (labUnits ?? 0) * _minutesPerLabUnit;
  return (lectureMinutes + labMinutes).round();
}

int _minutesSinceMidnight(String hhmm) {
  final parts = hhmm.split(':');
  return int.parse(parts[0]) * 60 + int.parse(parts[1]);
}

/// Duration of one parsed meeting. Rows missing a start/end time (should
/// not happen for a row [extractTimeRanges] produced, but a manually
/// constructed row could omit them) count as zero duration rather than
/// throwing.
Duration meetingDuration(ScheduleImportRow row) {
  if (row.startTime == null || row.endTime == null) return Duration.zero;
  final minutes =
      _minutesSinceMidnight(row.endTime!) - _minutesSinceMidnight(row.startTime!);
  return Duration(minutes: minutes < 0 ? 0 : minutes);
}

/// Whether an offering's actual scheduled minutes match what its unit
/// counts imply.
typedef UnitHoursValidation = ({int expectedMinutes, int actualMinutes, bool matches});

/// Cross-checks one offering's parsed meetings against its expected
/// weekly hours (Component 3a). [subjectTitle] and [section] are for the
/// caller's own reporting/logging — this function itself only inspects
/// [meetings]. Exactly one of [plainUnits] or ([lectureUnits],
/// [labUnits]) should be supplied, matching [expectedWeeklyMinutes].
UnitHoursValidation validateUnitHours(
  String subjectTitle,
  String section,
  List<ScheduleImportRow> meetings, {
  double? lectureUnits,
  double? labUnits,
  double? plainUnits,
}) {
  final expected = expectedWeeklyMinutes(
    lectureUnits: lectureUnits,
    labUnits: labUnits,
    plainUnits: plainUnits,
  );
  final actual = meetings.fold<int>(
      0, (sum, m) => sum + meetingDuration(m).inMinutes);
  return (expectedMinutes: expected, actualMinutes: actual, matches: expected == actual);
}

enum ScheduleConflictKind { professorOverlap, roomOverlap, sourceDisagreement }

class ScheduleConflict {
  const ScheduleConflict({
    required this.kind,
    required this.first,
    required this.second,
    required this.description,
  });

  final ScheduleConflictKind kind;
  final ScheduleImportRow first;
  final ScheduleImportRow second;
  final String description;
}

bool _timesOverlap(ScheduleImportRow a, ScheduleImportRow b) {
  if (a.day != b.day || a.startTime == null || a.endTime == null ||
      b.startTime == null || b.endTime == null) {
    return false;
  }
  final aStart = _minutesSinceMidnight(a.startTime!);
  final aEnd = _minutesSinceMidnight(a.endTime!);
  final bStart = _minutesSinceMidnight(b.startTime!);
  final bEnd = _minutesSinceMidnight(b.endTime!);
  return aStart < bEnd && bStart < aEnd;
}

/// Flags any two meetings in [meetings] sharing the same professor (or
/// the same room) on the same day with overlapping time ranges. O(n^2)
/// over one batch's meetings, which is small (a term's worth of
/// meetings numbers in the hundreds, not millions) — no index needed.
List<ScheduleConflict> detectOverlapConflicts(List<ScheduleImportRow> meetings) {
  final conflicts = <ScheduleConflict>[];
  for (var i = 0; i < meetings.length; i++) {
    for (var j = i + 1; j < meetings.length; j++) {
      final a = meetings[i];
      final b = meetings[j];
      if (!_timesOverlap(a, b)) continue;

      if (a.professorName != null &&
          a.professorName == b.professorName) {
        conflicts.add(ScheduleConflict(
          kind: ScheduleConflictKind.professorOverlap,
          first: a,
          second: b,
          description:
              '${a.professorName} is double-booked on ${a.day} between '
              '${a.subjectTitle} (${a.startTime}-${a.endTime}) and '
              '${b.subjectTitle} (${b.startTime}-${b.endTime})',
        ));
      }
      if (a.room != null && a.room == b.room) {
        conflicts.add(ScheduleConflict(
          kind: ScheduleConflictKind.roomOverlap,
          first: a,
          second: b,
          description:
              'Room ${a.room} is double-booked on ${a.day} between '
              '${a.subjectTitle} (${a.startTime}-${a.endTime}) and '
              '${b.subjectTitle} (${b.startTime}-${b.endTime})',
        ));
      }
    }
  }
  return conflicts;
}

bool _sameMeetingIdentity(ScheduleImportRow a, ScheduleImportRow b) {
  return a.subjectTitle == b.subjectTitle &&
      a.section == b.section &&
      a.professorName == b.professorName &&
      a.day == b.day &&
      a.startTime == b.startTime &&
      a.endTime == b.endTime;
}

/// Compares [cflMeetings] against [roomScheduleMeetings]: for every pair
/// that appears to describe the same meeting (same subject, section,
/// professor, day, and time), flags a conflict if they disagree on room.
/// A meeting present in only one source is not a conflict here — that
/// gap is the roster cross-check's job (Task 8), not this function's.
List<ScheduleConflict> detectSourceDisagreements(
  List<ScheduleImportRow> cflMeetings,
  List<ScheduleImportRow> roomScheduleMeetings,
) {
  final conflicts = <ScheduleConflict>[];
  for (final cflRow in cflMeetings) {
    for (final roomRow in roomScheduleMeetings) {
      if (!_sameMeetingIdentity(cflRow, roomRow)) continue;
      if (cflRow.room != roomRow.room) {
        conflicts.add(ScheduleConflict(
          kind: ScheduleConflictKind.sourceDisagreement,
          first: cflRow,
          second: roomRow,
          description:
              '${cflRow.subjectTitle} (${cflRow.section}, ${cflRow.day} '
              '${cflRow.startTime}-${cflRow.endTime}): CFL says room '
              '${cflRow.room}, Room Schedule says room ${roomRow.room}',
        ));
      }
    }
  }
  return conflicts;
}
