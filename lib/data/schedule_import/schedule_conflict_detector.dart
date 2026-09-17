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
