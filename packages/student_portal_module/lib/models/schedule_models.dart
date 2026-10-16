import 'package:dashboard_layout/dashboard_layout.dart' show formatClockRange12h;

/// One weekly meeting of a class offering (a row of `class_section_meetings`,
/// which is where the schedule import writes the real day/time/room).
class ScheduleMeetingModel {
  const ScheduleMeetingModel({
    required this.day,
    required this.startTime,
    required this.endTime,
    this.room = '',
  });

  /// 'M', 'T', 'W', 'TH', 'F' or 'S'.
  final String day;
  final String startTime;
  final String endTime;
  final String room;
}

const _meetingDayWeekday = {
  'M': DateTime.monday,
  'T': DateTime.tuesday,
  'W': DateTime.wednesday,
  'TH': DateTime.thursday,
  'F': DateTime.friday,
  'S': DateTime.saturday,
  // Legacy `class_sections.schedule_days` spelling (manual Add Schedule form).
  'MON': DateTime.monday,
  'TUE': DateTime.tuesday,
  'WED': DateTime.wednesday,
  'THU': DateTime.thursday,
  'FRI': DateTime.friday,
  'SAT': DateTime.saturday,
};

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
    this.subjectId,
    this.meetings = const [],
  });

  final String id;

  /// `subjects.id` — matches `AttendanceEntry.subjectId`, so the portal's
  /// subject filter can pair a class with its attendance rows.
  final String? subjectId;
  final String subjectTitle;
  final String professorName;
  final String room;
  final List<String> days;

  /// 24-hour "HH:mm" as stored (Postgres `time` column, ISO-ish string
  /// once decoded by the Supabase client).
  final String startTime;
  final String endTime;

  /// Real per-day meetings from `class_section_meetings`. Empty for an
  /// offering that only has the legacy one-row day/time/room columns.
  final List<ScheduleMeetingModel> meetings;

  String get daysLabel => meetings.isNotEmpty
      ? {for (final m in meetings) m.day}.join(', ')
      : days.join(', ');

  /// "8:00 AM - 9:30 AM" — always the 12-hour clock. Several distinct time
  /// ranges (a class meeting at a different hour each day) are joined.
  String get timeLabel {
    if (meetings.isEmpty) return formatClockRange12h(startTime, endTime);
    final ranges = <String>{
      for (final m in meetings) formatClockRange12h(m.startTime, m.endTime),
    };
    return ranges.join(' / ');
  }

  String get roomLabel {
    if (meetings.isEmpty) return room;
    final rooms = <String>{
      for (final m in meetings)
        if (m.room.isNotEmpty) m.room,
    };
    return rooms.isEmpty ? room : rooms.join(' / ');
  }

  /// The meetings that fall on [weekday] (DateTime.monday ... saturday),
  /// falling back to the legacy day list + single time range.
  List<ScheduleMeetingModel> meetingsOn(int weekday) {
    if (meetings.isNotEmpty) {
      return [
        for (final m in meetings)
          if (_meetingDayWeekday[m.day.toUpperCase()] == weekday) m,
      ];
    }
    final onDay = days.any((d) => _meetingDayWeekday[d.toUpperCase()] == weekday);
    if (!onDay || startTime.isEmpty) return const [];
    return [
      ScheduleMeetingModel(
          day: '', startTime: startTime, endTime: endTime, room: room),
    ];
  }
}
