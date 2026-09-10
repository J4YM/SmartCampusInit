/// One active enrollment's class_sections offering, reduced to what the
/// student portal's "My Schedule" card needs. Backed by real
/// enrollments/class_sections/subjects data — see
/// StudentPortalRepository.fetchSchedule.
class StudentScheduleEntryModel {
  const StudentScheduleEntryModel({
    required this.id,
    required this.subjectTitle,
    required this.professorName,
    required this.room,
    required this.days,
    required this.startTime,
    required this.endTime,
  });

  final String id;
  final String subjectTitle;
  final String professorName;
  final String room;
  final List<String> days;

  /// 24-hour "HH:mm" as stored (Postgres `time` column, ISO-ish string
  /// once decoded by the Supabase client).
  final String startTime;
  final String endTime;

  String get daysLabel => days.join(', ');
  String get timeLabel => '$startTime - $endTime';
}
