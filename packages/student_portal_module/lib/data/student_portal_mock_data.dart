import '../models/attendance_models.dart';
import '../models/student_notification_model.dart';
import '../models/violation_models.dart';

/// Deterministic demo data for the student portal shell — no backend wired
/// up yet, so every page falls back to this when no `initialX` is supplied,
/// the same convention every other dashboard module (Discipline Officer,
/// Guidance Counselor, …) already follows.
abstract final class StudentPortalMockData {
  static const subjects = [
    SubjectModel(
      id: 'sub_1',
      name: 'Data Structures & Algorithms',
      instructor: 'Prof. R. Santiago',
    ),
    SubjectModel(
      id: 'sub_2',
      name: 'Mobile Application Development',
      instructor: 'Prof. L. Ramos',
    ),
    SubjectModel(
      id: 'sub_3',
      name: 'Networking Fundamentals',
      instructor: 'Prof. M. Cruz',
    ),
    SubjectModel(
      id: 'sub_4',
      name: 'Technopreneurship',
      instructor: 'Prof. A. Villanueva',
    ),
  ];

  /// Generates weekday attendance across every subject for the
  /// [daysBack]-day window ending today, with a light deterministic
  /// pseudo-random spread so the week rail (and its history view) has a
  /// realistic mix of present/late/absent/excused days without ever being
  /// truly random (stable across rebuilds/hot reloads). A rolling window
  /// rather than a single calendar month so "this week" and "6 weeks back"
  /// both resolve correctly regardless of where today falls in the month.
  static List<AttendanceEntry> generateAttendance({int daysBack = 90}) {
    final today = dateOnly(DateTime.now());
    final start = today.subtract(Duration(days: daysBack));

    final entries = <AttendanceEntry>[];
    for (var date = start;
        !date.isAfter(today);
        date = date.add(const Duration(days: 1))) {
      if (date.weekday == DateTime.saturday ||
          date.weekday == DateTime.sunday) {
        continue;
      }
      final dayIndex = date.difference(start).inDays;

      for (var i = 0; i < subjects.length; i++) {
        final subject = subjects[i];
        final seed = (dayIndex * 7 + i * 13) % 20;
        final AttendanceStatus status;
        if (seed == 0) {
          status = AttendanceStatus.absent;
        } else if (seed == 1 || seed == 2) {
          status = AttendanceStatus.late;
        } else if (seed == 3) {
          status = AttendanceStatus.excused;
        } else {
          status = AttendanceStatus.present;
        }

        entries.add(
          AttendanceEntry(
            date: date,
            subjectId: subject.id,
            subjectName: subject.name,
            status: status,
            timeIn: status == AttendanceStatus.absent
                ? null
                : status == AttendanceStatus.late
                    ? '8:1${i}5 AM'
                    : '7:5$i AM',
            remarks: status == AttendanceStatus.excused
                ? 'Medical certificate on file'
                : null,
          ),
        );
      }
    }
    return entries;
  }

  static List<StudentViolationModel> violations() {
    final now = DateTime.now();
    return [
      StudentViolationModel(
        id: 'v_1',
        title: 'Improper uniform (no ID lace)',
        category: ViolationCategory.minor,
        status: ViolationStatus.recorded,
        dateFiled: now.subtract(const Duration(days: 18)),
        description:
            'Flagged at the gate during morning RFID tap-in for not wearing '
            'the school ID lace with the uniform.',
        recordedBy: 'Student Affairs & Services',
      ),
      StudentViolationModel(
        id: 'v_2',
        title: 'Unauthorized use of mobile phone during exam',
        category: ViolationCategory.major,
        status: ViolationStatus.pending,
        dateFiled: now.subtract(const Duration(days: 4)),
        description:
            'Reported by the proctor during the Networking Fundamentals '
            'midterm exam. Awaiting review by Student Affairs.',
        recordedBy: 'Prof. M. Cruz',
      ),
      StudentViolationModel(
        id: 'v_3',
        title: 'Late submission of admission slip',
        category: ViolationCategory.minor,
        status: ViolationStatus.recorded,
        dateFiled: now.subtract(const Duration(days: 32)),
        description:
            'Admission slip for an excused absence was filed two days past '
            'the deadline.',
        recordedBy: 'Student Affairs & Services',
      ),
    ];
  }

  static List<StudentNotificationModel> notifications() {
    final now = DateTime.now();
    return [
      StudentNotificationModel(
        id: 'n_1',
        senderName: 'Student Affairs & Services',
        senderRole: NotificationSenderRole.studentAffairsOffice,
        title: 'Violation report received',
        message:
            'A conduct report was filed against you for "Unauthorized use of '
            'mobile phone during exam." It is currently pending review — '
            'you may be asked to submit a written explanation.',
        timestamp: now.subtract(const Duration(hours: 3)),
        isRead: false,
      ),
      StudentNotificationModel(
        id: 'n_2',
        senderName: 'Prof. L. Ramos',
        senderRole: NotificationSenderRole.professor,
        title: 'Mobile App Dev — project deadline moved',
        message:
            'The final project deliverable is moved to next Friday. Please '
            'submit your repository link through the class portal.',
        timestamp: now.subtract(const Duration(hours: 20)),
        isRead: false,
      ),
      StudentNotificationModel(
        id: 'n_3',
        senderName: 'Registrar',
        senderRole: NotificationSenderRole.registrar,
        title: 'Enrollment window reminder',
        message: 'Early enrollment for next term opens in two weeks. Clear any '
            'pending balance to avoid a hold on registration.',
        timestamp: now.subtract(const Duration(days: 2)),
        isRead: true,
      ),
      StudentNotificationModel(
        id: 'n_4',
        senderName: 'Student Affairs & Services',
        senderRole: NotificationSenderRole.studentAffairsOffice,
        title: 'Attendance advisory',
        message:
            'You were marked late three times this month in Data Structures '
            '& Algorithms. Please coordinate with your adviser if this '
            'continues.',
        timestamp: now.subtract(const Duration(days: 6)),
        isRead: true,
      ),
    ];
  }
}
