import 'dart:math' as math;

import 'package:dashboard_layout/dashboard_layout.dart';
// Reuses the Discipline Officer module's shared header-popover components
// directly rather than duplicating them, matching the same pattern the
// Guidance Counselor module already uses for this widget set.
import 'package:discipline_officer_module/discipline_officer_module.dart'
    show
        AccountProfileMenu,
        LogoutConfirmationDialog,
        NotificationItemModel,
        NotificationsListView,
        NotificationsPopover,
        ProfileScreen,
        showHeaderPopover;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../data/conduct_mock_data.dart';
import '../../data/professor_mock_data.dart';
import '../../theme/professor_colors.dart';
import 'conduct_report_view.dart';
import 'violation_reports_view.dart';

// ---------------------------------------------------------------------------
// Data models — Supabase (`class_sections` / `attendance_records`) ready.
// fromJson()/toJson() map directly onto snake_case Postgres columns so rows
// can be streamed straight into these models once the backend is wired up.
// ---------------------------------------------------------------------------

class ProfessorSectionModel {
  const ProfessorSectionModel({
    required this.id,
    required this.name,
    required this.studentCount,
    this.subjectId,
    this.subjectName,
    this.classSectionId,
  });

  final String id;
  final String name;
  final int studentCount;

  /// The `class_sections.id` (subject + section + professor) this entry
  /// represents; null for mock/legacy data. Attendance is scoped to it.
  final String? classSectionId;

  /// The parent [ProfessorSubjectModel] this section is offered under, for
  /// grouping in the Section List sidebar's accordion (Subject -> Section).
  /// Filled by `fetchAssignedSections` (lib/data/professor_repository.dart)
  /// from `class_sections`; a section with no subject isn't listed.
  final String? subjectId;
  final String? subjectName;

  factory ProfessorSectionModel.fromJson(Map<String, dynamic> json) {
    return ProfessorSectionModel(
      id: json['id'] as String,
      name: json['name'] as String,
      studentCount: json['student_count'] as int? ?? 0,
      subjectId: json['subject_id'] as String?,
      subjectName: json['subject_name'] as String?,
      classSectionId: json['class_section_id'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'student_count': studentCount,
      'subject_id': subjectId,
      'subject_name': subjectName,
      'class_section_id': classSectionId,
    };
  }
}

/// One meeting on a professor's real teaching schedule — a specific
/// subject taught to a specific section, on a specific day/time/room.
/// Backed by `class_sections` joined to `class_section_meetings` (see
/// lib/data/professor_repository.dart's fetchMySchedule), which is a
/// completely different table pair from [ProfessorSectionModel]'s
/// `class_assignments` (that one is "which home section do I take
/// attendance for"; this one is "what do I actually teach, and when").
class ProfessorScheduleEntryModel {
  const ProfessorScheduleEntryModel({
    required this.id,
    required this.subjectTitle,
    required this.sectionName,
    required this.component,
    required this.day,
    required this.startTime,
    required this.endTime,
    required this.room,
  });

  final String id;
  final String subjectTitle;
  final String sectionName;

  /// 'Lecture', 'Laboratory', or null when the subject has no split.
  final String? component;

  /// One of 'M', 'T', 'W', 'TH', 'F', 'S'.
  final String day;

  /// 24-hour "HH:MM" as stored; shown through formatClockRange12h.
  final String startTime;
  final String endTime;
  final String room;
}

/// One subject a professor teaches, grouping every [ProfessorSectionModel]
/// offered under it — the Section List sidebar's top-level accordion
/// group. Supabase-ready: mirrors the `subjects` table joined through
/// `class_sections` (see supabase/add_subjects_enrollments_schema.sql) —
/// not wired to a live query yet, so this is currently always derived from
/// [ProfessorSectionModel.subjectName] client-side rather than fetched
/// directly (see [ProfessorDashboardPage._subjects]).
class ProfessorSubjectModel {
  const ProfessorSubjectModel({
    required this.id,
    required this.name,
    required this.sections,
  });

  final String id;
  final String name;
  final List<ProfessorSectionModel> sections;

  /// Total enrolled students across every section under this subject — the
  /// subject accordion header's summary badge.
  int get totalStudentCount =>
      sections.fold(0, (sum, section) => sum + section.studentCount);

  factory ProfessorSubjectModel.fromJson(Map<String, dynamic> json) {
    return ProfessorSubjectModel(
      id: json['id'] as String,
      name: json['title'] as String,
      sections: (json['sections'] as List<dynamic>? ?? const [])
          .map((e) => ProfessorSectionModel.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': name,
      'sections': sections.map((s) => s.toJson()).toList(),
    };
  }
}

/// Today's live attendance tally for whichever section is selected. Defaults
/// to all-zero, matching the Figma frame's empty/pre-session state.
class AttendanceSummaryModel {
  const AttendanceSummaryModel({
    this.present = 0,
    this.absent = 0,
    this.late = 0,
    this.excused = 0,
  });

  final int present;
  final int absent;
  final int late;
  final int excused;

  factory AttendanceSummaryModel.fromJson(Map<String, dynamic> json) {
    return AttendanceSummaryModel(
      present: json['present'] as int? ?? 0,
      absent: json['absent'] as int? ?? 0,
      late: json['late'] as int? ?? 0,
      excused: json['excused'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'present': present,
      'absent': absent,
      'late': late,
      'excused': excused,
    };
  }
}

/// A student's status for whichever session is currently in progress — shown
/// as the Student List table's clickable Status icon, which cycles through
/// these in order on tap. The [value] strings match the existing
/// `'Present'`/`'Absent'`/`'Late'`/`'Excuse'` convention used by
/// [ProfessorDashboardPage.onSubmitAttendance]'s status map.
enum AttendanceStatus {
  /// Not yet marked for this session — the default before the icon has ever
  /// been tapped. Shown as a gray dash-in-circle; the first tap moves
  /// straight to [present], never back to [none] (see [next]).
  none,
  present,
  absent,
  tardy,
  excused;

  String get value => switch (this) {
        AttendanceStatus.none => 'Unmarked',
        AttendanceStatus.present => 'Present',
        AttendanceStatus.absent => 'Absent',
        AttendanceStatus.tardy => 'Late',
        AttendanceStatus.excused => 'Excuse',
      };

  /// The status this cycles to on the next tap — unmarked → present →
  /// absent → late → excused → present → … ([none] is only ever a starting
  /// point, not part of the repeating cycle).
  AttendanceStatus get next => switch (this) {
        AttendanceStatus.none => AttendanceStatus.present,
        AttendanceStatus.present => AttendanceStatus.absent,
        AttendanceStatus.absent => AttendanceStatus.tardy,
        AttendanceStatus.tardy => AttendanceStatus.excused,
        AttendanceStatus.excused => AttendanceStatus.present,
      };

  IconData get icon => switch (this) {
        AttendanceStatus.none => Icons.remove_circle_outline_rounded,
        AttendanceStatus.present => Icons.check_circle_rounded,
        AttendanceStatus.absent => Icons.cancel_rounded,
        AttendanceStatus.tardy => Icons.watch_later_rounded,
        AttendanceStatus.excused => Icons.info_rounded,
      };

  Color get color => switch (this) {
        AttendanceStatus.none => ProfessorColors.statusNeutral,
        AttendanceStatus.present => ProfessorColors.successGreen,
        AttendanceStatus.absent => ProfessorColors.dangerRed,
        AttendanceStatus.tardy => ProfessorColors.warningYellow,
        AttendanceStatus.excused => ProfessorColors.azureBlue,
      };

  static AttendanceStatus fromValue(String? value) => switch (value) {
        'Present' => AttendanceStatus.present,
        'Absent' => AttendanceStatus.absent,
        'Late' => AttendanceStatus.tardy,
        'Excuse' => AttendanceStatus.excused,
        _ => AttendanceStatus.none,
      };
}

class StudentAttendanceRecordModel {
  const StudentAttendanceRecordModel({
    required this.id,
    required this.studentName,
    required this.studentId,
    required this.presentCount,
    required this.totalSessions,
    required this.absentCount,
    this.kioskTapInAt,
    this.kioskTapOutAt,
  });

  final String id;
  final String studentName;

  /// When this student first tapped IN at a kiosk today (local time), or
  /// null if they have no tap-in yet — lets the professor see who is
  /// actually on campus before marking attendance. Read from the kiosk's
  /// `rfid_tap_events`, independent of the status the professor records.
  final DateTime? kioskTapInAt;

  /// When this student last tapped OUT at a kiosk today (local time), or null
  /// if they have not left yet — so the professor can tell a student who has
  /// already gone home for the day.
  final DateTime? kioskTapOutAt;

  /// The student's display ID (e.g. institution ID number) — distinct from
  /// [id], the internal row identifier used as [AttendanceCellModel]'s
  /// `studentRecordId` and as the key in
  /// [ProfessorDashboardPage.onSubmitAttendance]'s status map.
  final String studentId;
  final int presentCount;
  final int totalSessions;
  final int absentCount;

  factory StudentAttendanceRecordModel.fromJson(Map<String, dynamic> json) {
    return StudentAttendanceRecordModel(
      id: json['id'] as String,
      studentName: json['student_name'] as String,
      studentId: json['student_id'] as String? ?? '',
      presentCount: json['present_count'] as int? ?? 0,
      totalSessions: json['total_sessions'] as int? ?? 0,
      absentCount: json['absent_count'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'student_name': studentName,
      'student_id': studentId,
      'present_count': presentCount,
      'total_sessions': totalSessions,
      'absent_count': absentCount,
    };
  }
}

/// One student's status for one calendar date — the unit cell of the
/// Attendance tab's weekly matrix. Supabase-ready: mirrors
/// `attendance_records` (`student_id`, `session_date`, `status`).
class AttendanceCellModel {
  const AttendanceCellModel({
    required this.studentRecordId,
    required this.date,
    this.status = AttendanceStatus.none,
  });

  /// [StudentAttendanceRecordModel.id] this cell belongs to.
  final String studentRecordId;

  /// Always a bare calendar date (midnight, no time component) — see
  /// [dateOnly].
  final DateTime date;
  final AttendanceStatus status;

  AttendanceCellModel copyWith({AttendanceStatus? status}) {
    return AttendanceCellModel(
      studentRecordId: studentRecordId,
      date: date,
      status: status ?? this.status,
    );
  }

  factory AttendanceCellModel.fromJson(Map<String, dynamic> json) {
    return AttendanceCellModel(
      studentRecordId: json['student_record_id'] as String,
      date: dateOnly(DateTime.parse(json['session_date'] as String)),
      status: AttendanceStatus.fromValue(json['status'] as String?),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'student_record_id': studentRecordId,
      'session_date': date.toIso8601String(),
      'status': status.value,
    };
  }
}

/// One earlier class the same day, with a student's recorded status in it.
/// [AttendanceStatus.none] means "not recorded".
class EarlierClassStatus {
  const EarlierClassStatus({
    required this.subjectName,
    required this.professorName,
    required this.startTime,
    required this.status,
  });

  final String subjectName;
  final String professorName;

  /// 'HH:MM'
  final String startTime;
  final AttendanceStatus status;
}

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// The Monday that starts the week containing [d].
DateTime mondayOf(DateTime d) {
  final day = dateOnly(d);
  return day.subtract(Duration(days: day.weekday - DateTime.monday));
}

const _shortMonthNames = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];
const _shortWeekdayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// "Mon, Sep 1" — a date column header.
String formatDayMonthDate(DateTime date) {
  final weekday = _shortWeekdayNames[date.weekday - 1];
  return '$weekday, ${_shortMonthNames[date.month - 1]} ${date.day}';
}

/// "Sep 1 - 6" (or "Sep 29 - Oct 4" across a month boundary) — the
/// toolbar's week-range label, for the Monday-Saturday week containing
/// [weekStart].
String formatWeekRangeLabel(DateTime weekStart) {
  final start = dateOnly(weekStart);
  final end = start.add(const Duration(days: 5));
  final startLabel = '${_shortMonthNames[start.month - 1]} ${start.day}';
  final endLabel = start.month == end.month
      ? '${end.day}'
      : '${_shortMonthNames[end.month - 1]} ${end.day}';
  return '$startLabel - $endLabel';
}

/// Styled `showDatePicker` matching every other dashboard's typography/
/// color convention (mirrors admin_dashboard's `reports_exports_page.dart`
/// `_showStyledDatePicker`, substituting `ProfessorColors` tokens).
Future<DateTime?> _showStyledDatePicker({
  required BuildContext context,
  required DateTime initialDate,
}) {
  return showDatePicker(
    context: context,
    initialDate: initialDate,
    firstDate: DateTime(2020),
    lastDate: DateTime(2100),
    // The attendance matrix only ever shows Monday-Saturday columns (see
    // formatWeekRangeLabel/_datesInWeek) — Sundays are excluded from the
    // cycle entirely, so picking one here would add a column that could
    // never actually be seen in the table.
    selectableDayPredicate: (date) => date.weekday != DateTime.sunday,
    builder: (context, child) {
      final baseTheme = Theme.of(context);
      return Theme(
        data: baseTheme.copyWith(
          textTheme: GoogleFonts.poppinsTextTheme(baseTheme.textTheme),
          colorScheme: baseTheme.colorScheme.copyWith(
            primary: ProfessorColors.azureBlue,
            onPrimary: Colors.white,
            surface: ProfessorColors.card(context),
            onSurface: ProfessorColors.rowText(context),
          ),
          datePickerTheme: DatePickerThemeData(
            backgroundColor: ProfessorColors.card(context),
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            headerBackgroundColor: ProfessorColors.azureBlue,
            headerForegroundColor: Colors.white,
            headerHeadlineStyle: GoogleFonts.poppins(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
            weekdayStyle: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: ProfessorColors.mutedText(context),
            ),
            // Today's cell (and today's year in the year list) reads
            // `todayForegroundColor` even while selected — and a selected
            // cell is filled azure, so a flat azure number vanishes into
            // it. White when selected, brand blue otherwise.
            todayForegroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? Colors.white
                  : subNavActiveColor(context, ProfessorColors.azureBlue),
            ),
            todayBorder: BorderSide(
              color: subNavActiveColor(context, ProfessorColors.azureBlue),
              width: 1,
            ),
            dayForegroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? Colors.white
                  : ProfessorColors.rowText(context),
            ),
            dayBackgroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? ProfessorColors.azureBlue
                  : null,
            ),
            dayShape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            yearForegroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? Colors.white
                  : ProfessorColors.rowText(context),
            ),
            yearBackgroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? ProfessorColors.azureBlue
                  : null,
            ),
          ),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(
              foregroundColor: subNavActiveColor(context, ProfessorColors.azureBlue),
              textStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600),
            ),
          ),
        ),
        child: child!,
      );
    },
  );
}

// ---------------------------------------------------------------------------
// Tab navigation state
// ---------------------------------------------------------------------------

enum ProfessorDashboardTab { schedule, attendance, conductReport }

/// "View all notifications" swap the main content area
/// exactly like a normal sub-nav tab does — header and sub-nav bar stay put
/// — rather than opening a new page/route. Not one of [ProfessorDashboardTab]'s
/// own values since it isn't a real, always-visible tab; tapping any real
/// tab clears this back to null.
enum _MailboxView { notifications }

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

class ProfessorDashboardPage extends StatefulWidget {
  const ProfessorDashboardPage({
    super.key,
    this.professorName = 'Juan Dela Cruz',
    this.onReturnToHub,
    this.onSignOut,
    this.initialSections,
    this.initialSchedule,
    this.isScheduleLoading = false,
    this.isLoading = false,
    this.initialAttendanceSummary,
    this.initialStudentAttendance,
    this.initialAttendanceCells,
    this.onSectionSelected,
    this.initialReports,
    this.initialViolationOptions,
    this.onSearchReportStudents,
    this.onSubmitReport,
    this.onDecideReport,
    this.initialNotifications,
    this.onMarkNotificationsRead,
    this.onMarkNotificationRead,
    this.onReplyToNotification,
    this.onSubmitAttendance,
    this.onDeleteAttendance,
    this.onFetchEarlierClasses,
    this.onReportTechnicalIssue,
  });

  final String professorName;

  /// Set when Admin opens this page from the hub as a preview; renders a
  /// back button in the header. Null for a Professor's own direct login
  /// route, where there is no hub to return to.
  final VoidCallback? onReturnToHub;

  /// Renders a sign-out action in the header when set.
  final VoidCallback? onSignOut;

  /// Supplies live-data initial state (e.g. wired to Supabase from the host
  /// app). Each falls back to [ProfessorMockData] when omitted, so this
  /// package stays independently runnable/demoable without a backend.
  final List<ProfessorSectionModel>? initialSections;

  /// This professor's real teaching schedule — see
  /// [ProfessorScheduleEntryModel]'s doc comment for how this differs from
  /// [initialSections]. Falls back to an empty "no schedule yet" state
  /// when omitted/empty (demo behavior — no backend to have populated it).
  final List<ProfessorScheduleEntryModel>? initialSchedule;
  final bool isScheduleLoading;

  /// `true` while the host is still fetching this dashboard's data — the
  /// header and sub-nav render immediately and only the tab content below
  /// them shows a skeleton, instead of the host blocking the whole screen.
  final bool isLoading;

  final AttendanceSummaryModel? initialAttendanceSummary;
  final List<StudentAttendanceRecordModel>? initialStudentAttendance;

  /// Every recorded (student, date) status across every session ever taken
  /// for [initialStudentAttendance]'s roster — the weekly attendance
  /// matrix's raw cells. Falls back to [ProfessorMockData.getAttendanceCells]
  /// when omitted.
  final List<AttendanceCellModel>? initialAttendanceCells;

  /// Called when a different section is picked from the Section List —
  /// the host app can use this to (re)fetch that section's attendance data.
  final Future<void> Function(ProfessorSectionModel section)? onSectionSelected;

  /// Violation Reports tab: every report tied to this professor, the
  /// violation list for the File a Report form, and its two callbacks.
  /// Without [onSubmitReport] the File a Report button is hidden (demo).
  final List<ProfessorReportModel>? initialReports;
  final List<ConductViolationOption>? initialViolationOptions;
  final Future<List<ReportStudentOption>> Function(String query)?
      onSearchReportStudents;
  final Future<void> Function(ReportSubmission submission)? onSubmitReport;
  final Future<void> Function(
    ProfessorReportModel report, {
    required bool confirm,
    String? note,
  })? onDecideReport;

  /// Notifications targeted at this dashboard from the centralized
  /// notification system (Admin's Notifications page). Falls back to an
  /// empty bell when omitted (demo behavior).
  final List<NotificationItemModel>? initialNotifications;

  /// Marks every currently-unread notification read — invoked by the bell's
  /// "View all notifications" action.
  final Future<void> Function()? onMarkNotificationsRead;

  /// Saves that one notification was read (by id) — called when its details
  /// are opened. When omitted the read mark is local only.
  final Future<void> Function(String notificationId)? onMarkNotificationRead;

  /// Sends a reply to a technical-issue notification (one with a report id)
  /// from its details popup; throws on failure. No reply box when omitted.
  final Future<void> Function(NotificationItemModel item, String message)?
      onReplyToNotification;

  /// Persists a status change (`'Present'`/`'Absent'`/`'Late'`/`'Excuse'`) for
  /// the active section on the given calendar [date] — called with a
  /// single-entry map when one cell is tapped (see [_handleStatusCycle]),
  /// or with every student in the roster for a column's "Mark all…" bulk
  /// action, or with every changed cell across every edited date when
  /// "Save Changes" commits an edit-mode session. When omitted, the action
  /// is unavailable (demo behavior — there's nowhere to persist it).
  final Future<void> Function(
    ProfessorSectionModel activeSection,
    DateTime date,
    Map<String, String> statusByStudentId,
  )? onSubmitAttendance;

  /// Deletes every attendance record taken for the active section on [date]
  /// (the date column's "Delete attendance for this day" action). Throws on
  /// failure. When omitted the action is hidden (demo behavior).
  final Future<void> Function(ProfessorSectionModel activeSection, DateTime date)?
      onDeleteAttendance;

  /// Loads each student's status in the classes that ran earlier on [date]
  /// (keyed by student record id), shown as chips while editing that day's
  /// column. Failures leave the chips empty. Omitted → no chips.
  final Future<Map<String, List<EarlierClassStatus>>> Function(
    ProfessorSectionModel section,
    DateTime date,
    List<String> studentIds,
  )? onFetchEarlierClasses;

  /// Opens the shared technical-issue report dialog when supplied. Falls
  /// back to no header icon at all when omitted (demo behavior — nowhere to
  /// send the report).
  final Future<void> Function({
    required ReportTechnicalIssueCategory category,
    required String description,
    String? location,
  })? onReportTechnicalIssue;

  @override
  State<ProfessorDashboardPage> createState() => _ProfessorDashboardPageState();
}

class _ProfessorDashboardPageState extends State<ProfessorDashboardPage> {
  late List<ProfessorSectionModel> sections;
  late AttendanceSummaryModel attendanceSummary;
  late List<StudentAttendanceRecordModel> studentAttendance;
  late List<AttendanceCellModel> attendanceCells;

  /// The Monday of the week currently shown in the attendance matrix.
  late DateTime _weekStart = mondayOf(DateTime.now());

  /// True while the matrix accepts taps to cycle a cell's status; changes
  /// are local-only until "Save Changes" persists them (or "Discard"
  /// reverts to [_cellsBeforeEdit]). Bulk "Mark all…" actions and single
  /// taps behave the same way while this is on.
  bool _editMode = false;
  List<AttendanceCellModel>? _cellsBeforeEdit;

  /// The date column last tapped in edit mode (defaults to today when it is
  /// in the visible week); earlier-class chips are shown for this day only.
  DateTime? _focusedDate;

  /// Earlier same-day classes per student record id for [_focusedDate].
  Map<String, List<EarlierClassStatus>> _earlierByStudent = const {};

  /// Sets [_focusedDate] (inside a setState the caller owns) and kicks off a
  /// fetch for it; a null date clears the chips.
  void _focusDate(DateTime? date) {
    if (date == _focusedDate) return;
    _focusedDate = date;
    _earlierByStudent = const {};
    if (date != null) _loadEarlierClasses(date);
  }

  Future<void> _loadEarlierClasses(DateTime date) async {
    final section = activeSection;
    final fetch = widget.onFetchEarlierClasses;
    if (section == null || fetch == null) return;
    Map<String, List<EarlierClassStatus>> result;
    try {
      result = await fetch(
          section, date, [for (final r in studentAttendance) r.id]);
    } catch (e) {
      debugPrint('Earlier classes fetch failed: $e');
      return;
    }
    // Drop stale results: edit mode ended or the date/section changed.
    if (!mounted ||
        _focusedDate != date ||
        (activeSection?.classSectionId ?? activeSection?.id) !=
            (section.classSectionId ?? section.id)) {
      return;
    }
    setState(() => _earlierByStudent = result);
  }

  void _resetEarlier() {
    _focusedDate = null;
    _earlierByStudent = const {};
    _showTodayEarlier();
  }

  /// Outside Take Attendance, the other-class chips follow TODAY (when today
  /// falls in the week on screen), so a student's status in their other
  /// subjects is visible without entering edit mode. In edit mode the focus
  /// follows the column being edited instead (see [_focusDate]).
  void _showTodayEarlier() {
    if (_editMode) return;
    final today = dateOnly(DateTime.now());
    final weekEnd = _weekStart.add(const Duration(days: 5));
    if (today.weekday > DateTime.saturday ||
        today.isBefore(_weekStart) ||
        today.isAfter(weekEnd)) {
      return;
    }
    _focusedDate = today;
    _loadEarlierClasses(today);
  }

  /// The Section List sidebar's active attendance context — the Attendance
  /// tab's matrix always reflects whichever section is active here, and
  /// [_SubjectSectionListCard] highlights it under its parent subject.
  /// [activeSubject] is kept in sync with [activeSection] (see
  /// [_selectActiveSection]) rather than tracked independently — a section
  /// can only ever belong to one subject group at a time.
  ProfessorSectionModel? activeSection;
  ProfessorSubjectModel? activeSubject;
  ProfessorDashboardTab activeTab = ProfessorDashboardTab.schedule;

  /// Non-null while "View all notifications" is showing
  /// in place of the normal tab content. See [_MailboxView].
  _MailboxView? _mailboxView;

  final _searchController = TextEditingController();
  String _searchQuery = '';

  late List<ProfessorReportModel> reports;
  late List<ConductViolationOption> violationOptions;

  final ValueNotifier<ThemeMode> _themeMode = PersistedThemeModeNotifier();

  late List<NotificationItemModel> _notifications;

  @override
  void initState() {
    super.initState();
    _seedFromWidget();
    _showTodayEarlier();
  }

  void _seedFromWidget() {
    sections = widget.initialSections ?? ProfessorMockData.getSections();
    attendanceSummary = widget.initialAttendanceSummary ??
        ProfessorMockData.getAttendanceSummary();
    studentAttendance = widget.initialStudentAttendance ??
        ProfessorMockData.getStudentAttendance();
    attendanceCells = widget.initialAttendanceCells ??
        ProfessorMockData.getAttendanceCells(studentAttendance);
    if (sections.isNotEmpty) {
      activeSection = sections.first;
      activeSubject = _subjectContaining(activeSection!);
    }

    reports = widget.initialReports ?? const [];
    violationOptions =
        widget.initialViolationOptions ?? ConductMockData.getViolationOptions();

    _notifications = List.of(widget.initialNotifications ?? const []);
  }

  /// The host app's connected page reloads data (e.g. after Take
  /// Attendance/Submit Report persists, or a realtime notification insert)
  /// by rebuilding this widget with fresh `initialX` props — `initState`
  /// above only seeds local state once, so without this none of that would
  /// ever actually reach the screen.
  @override
  void didUpdateWidget(covariant ProfessorDashboardPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    // The shell is built before the host's data arrives (only the tab
    // content shows a skeleton meanwhile), so the one-time seeds in
    // initState were mock data — re-seed from the real data once it lands.
    if (oldWidget.isLoading && !widget.isLoading) _seedFromWidget();

    final freshNotifications = widget.initialNotifications;
    if (freshNotifications != null &&
        !identical(freshNotifications, oldWidget.initialNotifications)) {
      setState(() => _notifications = List.of(freshNotifications));
    }

    final freshSummary = widget.initialAttendanceSummary;
    if (freshSummary != null &&
        !identical(freshSummary, oldWidget.initialAttendanceSummary)) {
      setState(() => attendanceSummary = freshSummary);
    }

    final freshAttendance = widget.initialStudentAttendance;
    if (freshAttendance != null &&
        !identical(freshAttendance, oldWidget.initialStudentAttendance)) {
      setState(() => studentAttendance = freshAttendance);
      final focused = _focusedDate;
      if (focused != null) {
        _loadEarlierClasses(focused);
      } else {
        _showTodayEarlier();
      }
    }

    final freshCells = widget.initialAttendanceCells;
    // Not while the matrix is being edited: the host re-reads attendance in
    // the background, and that must never overwrite marks the professor has
    // tapped in but not saved yet. Saving or discarding ends edit mode, and
    // the next refresh lands then.
    if (freshCells != null &&
        !_editMode &&
        !identical(freshCells, oldWidget.initialAttendanceCells)) {
      setState(() => attendanceCells = freshCells);
    }

    final freshReports = widget.initialReports;
    if (freshReports != null &&
        !identical(freshReports, oldWidget.initialReports)) {
      setState(() => reports = freshReports);
    }
    final freshOptions = widget.initialViolationOptions;
    if (freshOptions != null &&
        !identical(freshOptions, oldWidget.initialViolationOptions)) {
      setState(() => violationOptions = freshOptions);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _themeMode.dispose();
    super.dispose();
  }

  /// Groups [sections] under their parent subject, in first-seen order —
  /// the Section List sidebar's accordion structure (Subject -> Section).
  /// A section without a subject has no place in that hierarchy and is left
  /// out (the live query only returns sections that have one).
  List<ProfessorSubjectModel> get _subjects {
    final sectionsBySubjectId = <String, List<ProfessorSectionModel>>{};
    final nameBySubjectId = <String, String>{};
    for (final section in sections) {
      final name = section.subjectName;
      if (name == null || name.isEmpty) continue;
      final id = section.subjectId ?? name;
      sectionsBySubjectId.putIfAbsent(id, () => []).add(section);
      nameBySubjectId[id] = name;
    }
    return [
      for (final entry in sectionsBySubjectId.entries)
        ProfessorSubjectModel(
          id: entry.key,
          name: nameBySubjectId[entry.key]!,
          sections: entry.value,
        ),
    ];
  }

  ProfessorSubjectModel? _subjectContaining(ProfessorSectionModel section) {
    for (final subject in _subjects) {
      if (subject.sections.any(
        (s) =>
            (s.classSectionId ?? s.id) ==
            (section.classSectionId ?? section.id),
      )) {
        return subject;
      }
    }
    return null;
  }

  /// [_subjects], narrowed to whatever matches [_searchQuery] — a subject
  /// whose own name matches keeps every section; one that doesn't still
  /// surfaces if any single section under it matches, so a search never
  /// flattens a section out from under its parent subject.
  List<ProfessorSubjectModel> get _filteredSubjects {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return _subjects;
    final filtered = <ProfessorSubjectModel>[];
    for (final subject in _subjects) {
      final subjectMatches = subject.name.toLowerCase().contains(query);
      final matchingSections = subjectMatches
          ? subject.sections
          : subject.sections
              .where((s) => s.name.toLowerCase().contains(query))
              .toList();
      if (matchingSections.isEmpty) continue;
      filtered.add(ProfessorSubjectModel(
        id: subject.id,
        name: subject.name,
        sections: matchingSections,
      ));
    }
    return filtered;
  }

  Future<void> _selectActiveSection(
    ProfessorSubjectModel subject,
    ProfessorSectionModel section,
  ) async {
    // Switching class mid-edit would let _saveChanges submit this class's
    // marks under the newly selected class's id, so block it.
    if (_editMode) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Save or discard your attendance changes before switching class.',
          ),
        ),
      );
      return;
    }
    setState(() {
      activeSubject = subject;
      activeSection = section;
      _resetEarlier();
    });
    await widget.onSectionSelected?.call(section);
  }

  // ---------------------------------------------------------------------
  // Weekly attendance matrix
  // ---------------------------------------------------------------------

  /// Every distinct session date on record, across every student —
  /// dedupes and sorts [attendanceCells] into the matrix's column set.
  List<DateTime> get _allSessionDates {
    final dates = attendanceCells.map((c) => c.date).toSet().toList()..sort();
    return dates;
  }

  /// This week's columns (Monday through Saturday), newest first — the
  /// latest session sits in the very first (left) column, then the day
  /// before it, and so on (e.g. Oct 12, Oct 11, Oct 10). Only dates a
  /// session was actually recorded/added for, not every weekday. Sunday is
  /// intentionally excluded from the cycle (see [formatWeekRangeLabel]).
  List<DateTime> get _datesInWeek {
    final weekEnd = _weekStart.add(const Duration(days: 5));
    return _allSessionDates
        .where((d) => !d.isBefore(_weekStart) && !d.isAfter(weekEnd))
        .toList()
        .reversed
        .toList();
  }

  void _changeWeek(int deltaWeeks) {
    setState(() {
      _weekStart = _weekStart.add(Duration(days: 7 * deltaWeeks));
      final today = dateOnly(DateTime.now());
      final weekEnd = _weekStart.add(const Duration(days: 5));
      final todayInWeek =
          !today.isBefore(_weekStart) && !today.isAfter(weekEnd);
      if (_editMode && todayInWeek) {
        _focusDate(today);
      } else {
        _resetEarlier();
      }
    });
  }

  AttendanceCellModel? _cellFor(String studentRecordId, DateTime date) {
    for (final cell in attendanceCells) {
      if (cell.studentRecordId == studentRecordId && cell.date == date) {
        return cell;
      }
    }
    return null;
  }

  /// Opens a date picker (defaulting to today) and, once a date is picked,
  /// adds a new unassigned ("-"/[AttendanceStatus.none]) column for every
  /// student currently in [studentAttendance] — unless that date already
  /// has a column, in which case this just navigates the week view to it.
  /// Either way this also enters edit mode (if not already in it), so the
  /// new column's cells are immediately tappable and the toolbar shows
  /// Save Changes/Discard without a separate click on "Edit" — matching
  /// [_enterEditMode], a snapshot is only taken once per edit session, so
  /// adding a second date mid-edit doesn't clobber the earlier snapshot
  /// "Discard" needs to revert to.
  Future<void> _addAttendanceDate(BuildContext context) async {
    // showDatePicker asserts that initialDate satisfies
    // selectableDayPredicate — since Sundays are disabled there, roll a
    // Sunday "today" forward to Monday so opening the picker never throws.
    final now = dateOnly(DateTime.now());
    final initialDate =
        now.weekday == DateTime.sunday ? now.add(const Duration(days: 1)) : now;
    final picked = await _showStyledDatePicker(
      context: context,
      initialDate: initialDate,
    );
    if (picked == null) return;

    final date = dateOnly(picked);
    final alreadyExists = attendanceCells.any((c) => c.date == date);
    final snapshotBeforeAdd = List.of(attendanceCells);
    setState(() {
      if (!alreadyExists) {
        attendanceCells = [
          ...attendanceCells,
          for (final student in studentAttendance)
            AttendanceCellModel(studentRecordId: student.id, date: date),
        ];
      }
      _weekStart = mondayOf(date);
      _cellsBeforeEdit ??= snapshotBeforeAdd;
      _editMode = true;
      _focusDate(date);
    });
  }

  void _enterEditMode() {
    setState(() {
      _editMode = true;
      _cellsBeforeEdit = List.of(attendanceCells);
      final today = dateOnly(DateTime.now());
      _focusDate(_datesInWeek.contains(today) ? today : null);
    });
  }

  void _discardChanges() {
    setState(() {
      attendanceCells = _cellsBeforeEdit ?? attendanceCells;
      _cellsBeforeEdit = null;
      _editMode = false;
      _resetEarlier();
    });
  }

  /// Persists every cell that changed since [_enterEditMode], grouped into
  /// one [ProfessorDashboardPage.onSubmitAttendance] call per date (so a
  /// multi-day edit session doesn't need one call per cell).
  Future<void> _saveChanges() async {
    final section = activeSection;
    final before = _cellsBeforeEdit;

    // Every student must have a real status for any day being saved: an
    // unmarked cell has no value the database accepts, so saving one used to
    // fail with a raw enum error. Stay in edit mode so the professor can
    // finish marking instead of losing the half-done column.
    if (before != null) {
      final beforeStatus = {
        for (final cell in before) (cell.studentRecordId, cell.date): cell.status,
      };
      final unmarkedByDate = <DateTime, int>{};
      for (final date in {
        for (final cell in attendanceCells)
          if (beforeStatus[(cell.studentRecordId, cell.date)] != cell.status)
            cell.date,
      }) {
        final unmarked = studentAttendance
            .where((s) =>
                (_cellFor(s.id, date)?.status ?? AttendanceStatus.none) ==
                AttendanceStatus.none)
            .length;
        if (unmarked > 0) unmarkedByDate[date] = unmarked;
      }
      if (unmarkedByDate.isNotEmpty) {
        final days = unmarkedByDate.entries
            .map((e) => '${formatDayMonthDate(e.key)} '
                '(${e.value} ${e.value == 1 ? 'student' : 'students'} left)')
            .join(', ');
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: Text(
              'Mark every student before saving — all students need a status '
              '(Present, Absent, Late or Excuse). Still unmarked: $days.',
            ),
          ));
        return;
      }
    }

    setState(() {
      _editMode = false;
      _cellsBeforeEdit = null;
      _resetEarlier();
    });
    if (section == null || before == null) return;

    final beforeByKey = {
      for (final cell in before) (cell.studentRecordId, cell.date): cell.status,
    };
    final changedByDate = <DateTime, Map<String, String>>{};
    for (final cell in attendanceCells) {
      final key = (cell.studentRecordId, cell.date);
      if (beforeByKey[key] == cell.status) continue;
      (changedByDate[cell.date] ??= {})[cell.studentRecordId] =
          cell.status.value;
    }
    if (changedByDate.isEmpty) return;

    try {
      for (final entry in changedByDate.entries) {
        await widget.onSubmitAttendance?.call(section, entry.key, entry.value);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save attendance: $e')),
      );
    }
  }

  /// Cycles one cell's status (unmarked → present → absent → late →
  /// excused → present → …) when tapped in the matrix. Only responds while
  /// [_editMode] is on — see [_enterEditMode]/[_saveChanges].
  void _handleCellTap(String studentRecordId, DateTime date) {
    if (!_editMode) return;
    final current = _cellFor(studentRecordId, date);
    final nextStatus = (current?.status ?? AttendanceStatus.none).next;
    setState(() {
      _focusDate(date);
      attendanceCells = [
        for (final cell in attendanceCells)
          if (cell.studentRecordId == studentRecordId && cell.date == date)
            cell.copyWith(status: nextStatus)
          else
            cell,
        if (current == null)
          AttendanceCellModel(
              studentRecordId: studentRecordId, date: date, status: nextStatus),
      ];
    });
  }

  /// The date column header's "⋮" menu — bulk-marks every student for
  /// [date] in one go. Only available in edit mode, same as a single tap.
  void _markAllForDate(DateTime date, AttendanceStatus status) {
    if (!_editMode) return;
    setState(() {
      _focusDate(date);
      final studentIds = studentAttendance.map((s) => s.id).toSet();
      final updated = <AttendanceCellModel>[];
      final seen = <String>{};
      for (final cell in attendanceCells) {
        if (cell.date == date && studentIds.contains(cell.studentRecordId)) {
          updated.add(cell.copyWith(status: status));
          seen.add(cell.studentRecordId);
        } else {
          updated.add(cell);
        }
      }
      for (final student in studentAttendance) {
        if (!seen.contains(student.id)) {
          updated.add(AttendanceCellModel(
              studentRecordId: student.id, date: date, status: status));
        }
      }
      attendanceCells = updated;
    });
  }

  /// The date column's "Delete attendance for this day" action: after a
  /// confirmation, removes that day's records from the database right away
  /// (it isn't held back for "Save Changes") and drops the column locally.
  /// Edits to other days made in the same edit session are left alone.
  Future<void> _deleteAttendanceForDate(DateTime date) async {
    final section = activeSection;
    final delete = widget.onDeleteAttendance;
    if (section == null || delete == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete attendance?'),
        content: Text(
          'This permanently deletes all attendance recorded for '
          '${section.name} on ${formatDayMonthDate(date)}. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: ProfessorColors.dangerRed),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await delete(section, date);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete attendance: $e')),
      );
      return;
    }
    if (!mounted) return;
    setState(() {
      attendanceCells = [
        for (final cell in attendanceCells)
          if (cell.date != date) cell,
      ];
      // Also forget the day in the "Discard" snapshot, so discarding other
      // edits doesn't bring the deleted day back.
      final before = _cellsBeforeEdit;
      if (before != null) {
        _cellsBeforeEdit = [
          for (final cell in before)
            if (cell.date != date) cell,
        ];
      }
      if (_focusedDate == date) _resetEarlier();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text('Deleted attendance for ${formatDayMonthDate(date)}.')),
    );
  }

  Future<void> _markNotificationsRead() async {
    if (_notifications.every((n) => n.isRead)) return;
    setState(() {
      _notifications =
          _notifications.map((n) => n.copyWith(isRead: true)).toList();
    });
    try {
      await widget.onMarkNotificationsRead?.call();
    } catch (e) {
      debugPrint('Could not mark notifications read: $e');
    }
  }

  /// Opening a notification's details marks that one read — here at once, and
  /// saved through the host when [onMarkNotificationRead] is supplied.
  Future<void> _markNotificationRead(String id) async {
    final index = _notifications.indexWhere((n) => n.id == id);
    if (index == -1 || _notifications[index].isRead) return;
    setState(() {
      _notifications = [
        for (final n in _notifications)
          n.id == id ? n.copyWith(isRead: true) : n,
      ];
    });
    try {
      await widget.onMarkNotificationRead?.call(id);
    } catch (e) {
      debugPrint('Could not mark notification read: $e');
    }
  }

  void _showNotificationsMenu() {
    showHeaderPopover(
      context: context,
      cardWidth: 400,
      // Once the header's icons have moved into the bottom nav bar
      // (mobile), anchoring the popover under the top header reads as
      // disconnected from where it was actually triggered — center it on
      // the screen instead.
      centered: context.isMobileWidth,
      contentBuilder: (popoverContext, setPopoverState) {
        return NotificationsPopover(
          notifications: _notifications,
          onOpenNotification: (n) {
            _markNotificationRead(n.id);
            setPopoverState(() {});
          },
          onReplyToNotification: widget.onReplyToNotification,
          accentColor: ProfessorColors.azureBlue,
          isDarkMode: _themeMode.value == ThemeMode.dark,
          onViewAll: () {
            Navigator.of(popoverContext).pop();
            setState(() => _mailboxView = _MailboxView.notifications);
          },
          onMarkAllRead: () {
            Navigator.of(popoverContext).pop();
            _markNotificationsRead();
          },
        );
      },
    );
  }

  /// `ProfileScreen` is pushed onto the app's root `Navigator`, so its
  /// subtree lands outside this page's own local `Theme` (the same
  /// Overlay-escapes-local-Theme issue as the header popovers) — wrap it in
  /// a `Theme` matching the current toggle so its `context.isDarkMode`
  /// reads correctly instead of always seeing the app's ambient theme.
  Widget _themedProfileScreen() {
    return Theme(
      data: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: ProfessorColors.navyBlue,
        brightness: _themeMode.value == ThemeMode.dark
            ? Brightness.dark
            : Brightness.light,
      ).withPoppins(),
      child: const ProfileScreen(),
    );
  }

  /// Clicking the header logo acts as a "home" link — back to this
  /// dashboard's own default tab, dismissing "View all notifications"
  /// the same way picking a real tab already does.
  void _goHome() {
    setState(() {
      activeTab = ProfessorDashboardTab.schedule;
      _mailboxView = null;
    });
  }

  void _openProfile() {
    showHeaderPopover(
      context: context,
      cardWidth: 260,
      // Anchor near the Profile icon just above the bottom nav bar on
      // mobile, rather than centering — it stays visually tethered to
      // what opened it.
      anchorAboveBottomNav: context.isMobileWidth,
      contentBuilder: (popoverContext, setPopoverState) {
        return AccountProfileMenu(
          userName: widget.professorName,
          onViewProfile: () {
            Navigator.of(popoverContext).pop();
            Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => _themedProfileScreen()));
          },
          isDarkMode: _themeMode.value == ThemeMode.dark,
          onToggleDarkMode: () {
            _themeMode.value = _themeMode.value == ThemeMode.dark
                ? ThemeMode.light
                : ThemeMode.dark;
            setPopoverState(() {});
          },
          onLogout: () {
            Navigator.of(popoverContext).pop();
            _confirmLogout();
          },
        );
      },
    );
  }

  void _confirmLogout() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return LogoutConfirmationDialog(
          isDarkMode: _themeMode.value == ThemeMode.dark,
          onCancel: () => Navigator.of(dialogContext).pop(),
          onConfirm: () {
            Navigator.of(dialogContext).pop();
            widget.onSignOut?.call();
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: _themeMode,
      builder: (context, mode, child) {
        return Theme(
          data: ThemeData(
            useMaterial3: true,
            colorSchemeSeed: ProfessorColors.navyBlue,
            brightness:
                mode == ThemeMode.dark ? Brightness.dark : Brightness.light,
          ).withPoppins(),
          child: child!,
        );
      },
      // A Builder here hands us a context nested under the Theme built
      // above, so ProfessorColors.* token lookups (which key off
      // Theme.of(context).brightness) see the live dark/light mode instead
      // of whatever theme sits above this whole page.
      child: Builder(
        builder: (context) {
          final isMobile = context.isMobileWidth;

          final header = AppHeaderNavBar(
            title: 'Professor Dashboard',
            subtitle: kSchoolName,
            backgroundColor: ProfessorColors.navyBlue,
            leading: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.onReturnToHub != null) ...[
                  HeaderIconButton(
                    icon: Icons.arrow_back_rounded,
                    tooltip: 'Back to Hub',
                    onTap: widget.onReturnToHub!,
                  ),
                  const SizedBox(width: 12),
                ],
                SchoolLogo(onTap: _goHome),
              ],
            ),
            actions: [
              if (!isMobile) ...[
                HeaderIconButton(
                  icon: Icons.notifications_none_rounded,
                  tooltip: 'Notifications',
                  badgeCount: _notifications.where((n) => !n.isRead).length,
                  onTap: _showNotificationsMenu,
                ),
                if (widget.onReportTechnicalIssue != null)
                  HeaderIconButton(
                    icon: Icons.report_problem_outlined,
                    tooltip: 'Report Technical Issue',
                    iconWidget: const ReportIssueIcon(size: 20),
                    onTap: () => showReportTechnicalIssueDialog(
                      context,
                      isDarkMode: _themeMode.value == ThemeMode.dark,
                      onSubmit: widget.onReportTechnicalIssue!,
                    ),
                  ),
                const SizedBox(width: 4),
                ProfileAvatarButton(
                  onTap: _openProfile,
                  foregroundColor: ProfessorColors.navyBlue,
                ),
              ],
            ],
          );

          // Side-by-side master-detail tabs fill the window exactly (no
          // scroll) and only scroll below kDashboardMinFillHeight; My
          // Schedule, stacked layouts, the mailbox and the skeleton keep
          // their natural, content-sized height.
          final fillViewport = _mailboxView == null &&
              !widget.isLoading &&
              activeTab != ProfessorDashboardTab.schedule &&
              context.showsMasterDetailRow();

          final pageContent = DashboardPageWrapper(
            // Matches student_portal_module's StudentPortalSpacing.pageHorizontal:
            // 16px on mobile (not flush with the screen edge), 24px on desktop.
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 16 : 24,
              vertical: 16,
            ),
            child: Builder(
              builder: (context) {
                // Content-sized tabs (and stacked layouts) scroll as a
                // whole; side-by-side master-detail tabs fill the window
                // instead (see fillViewport).
                final body = _buildBody(context, isMobile: isMobile);
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (fillViewport) Expanded(child: body) else body,
                  ],
                );
              },
            ),
          );

          // Pinned directly under the header as a part of it; never scrolls.
          final subNavBar = _SubNavBar(
            activeTab: activeTab,
            onTabSelected: (tab) => setState(() {
              activeTab = tab;
              _mailboxView = null;
            }),
          );

          return Scaffold(
            backgroundColor: ProfessorColors.background(context),
            bottomNavigationBar: isMobile
                ? AppBottomNavBar(
                    onNotificationTap: _showNotificationsMenu,
                    onProfileTap: _openProfile,
                    notificationBadgeCount:
                        _notifications.where((n) => !n.isRead).length,
                    isDarkMode: _themeMode.value == ThemeMode.dark,
                  )
                : null,
            // The header and sub-nav bar stay fixed at the top; only the tab
            // content below them scrolls, so a short viewport never clips
            // tab content with no way to reach the rest of it.
            body: Column(
              children: [
                header,
                subNavBar,
                Expanded(
                  child: DashboardPageScrollView(
                    fill: fillViewport,
                    child: pageContent,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// [context] is the one from INSIDE the page's own Theme (the caller's
  /// Builder), not the State's bare `context`, which sits above it — so the
  /// loading skeleton follows the dark-mode toggle.
  Widget _buildBody(BuildContext context, {required bool isMobile}) {
    switch (_mailboxView) {
      case _MailboxView.notifications:
        return NotificationsListView(
          notifications: _notifications,
          onOpenNotification: (n) => _markNotificationRead(n.id),
          onReplyToNotification: widget.onReplyToNotification,
          isDarkMode: _themeMode.value == ThemeMode.dark,
        );
      case null:
        if (widget.isLoading) {
          return DashboardSkeletonScreen(
            useScaffold: false,
            wrapInPageFrame: false,
            backgroundColor: ProfessorColors.background(context),
            cardColor: ProfessorColors.card(context),
            cardBorderColor: ProfessorColors.cardBorder(context),
            placeholderColor: ProfessorColors.gray(context),
          );
        }
        return _buildTabContent(activeTab, isMobile: isMobile);
    }
  }

  Widget _buildTabContent(ProfessorDashboardTab tab, {required bool isMobile}) {
    return switch (tab) {
      ProfessorDashboardTab.schedule =>
        _buildScheduleContent(isMobile: isMobile),
      ProfessorDashboardTab.attendance =>
        _buildAttendanceContent(isMobile: isMobile),
      ProfessorDashboardTab.conductReport =>
        _buildConductReportContent(isMobile: isMobile),
    };
  }

  Widget _buildScheduleContent({required bool isMobile}) {
    final entries = widget.initialSchedule ?? const <ProfessorScheduleEntryModel>[];
    // Builder: this State's own `context` sits above the Theme built in
    // build(), so token lookups must use a context nested under it.
    return Builder(
      builder: (context) => BentoCard(
        backgroundColor: ProfessorColors.card(context),
        borderColor: ProfessorColors.cardBorder(context),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'My Schedule',
              style: dashboardCardTitleStyle(context,
                  color: ProfessorColors.rowText(context)),
            ),
            const SizedBox(height: 16),
            if (widget.isScheduleLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (entries.isEmpty)
              Text(
                'No classes scheduled yet.',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  color: ProfessorColors.mutedText(context),
                ),
              )
            else
              for (final entry in entries)
                _ScheduleEntryRow(entry: entry, isMobile: isMobile),
          ],
        ),
      ),
    );
  }

  Widget _buildAttendanceContent({required bool isMobile}) {
    final sectionListCard = _SubjectSectionListCard(
      subjects: _filteredSubjects,
      totalSectionCount: sections.length,
      activeSubjectId: activeSubject?.id,
      activeSectionId: activeSection == null
          ? null
          : (activeSection!.classSectionId ?? activeSection!.id),
      isSearching: _searchQuery.trim().isNotEmpty,
      searchController: _searchController,
      onSearchChanged: (value) => setState(() => _searchQuery = value),
      onSelect: _selectActiveSection,
    );

    if (isMobile) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          sectionListCard,
          const SizedBox(height: 16),
          _AttendanceStatsRow(summary: attendanceSummary),
          const SizedBox(height: 18),
          _StudentAttendanceTableCard(
            records: studentAttendance,
            dates: _datesInWeek,
            weekStart: _weekStart,
            editMode: _editMode,
            onPreviousWeek: () => _changeWeek(-1),
            onNextWeek: () => _changeWeek(1),
            onAddAttendance: () => _addAttendanceDate(context),
            onEnterEditMode: _enterEditMode,
            onSaveChanges: _saveChanges,
            onDiscardChanges: _discardChanges,
            statusFor: _cellFor,
            onCellTap: _handleCellTap,
            onMarkAllForDate: _markAllForDate,
            onDeleteDate: widget.onDeleteAttendance == null ? null : _deleteAttendanceForDate,
            earlierByStudent: _earlierByStudent,
            earlierDate: _focusedDate,
          ),
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final stackColumns = constraints.maxWidth < 900;

        // The table becomes the flexible child — filling the rest of this
        // panel's height — only when an ancestor (the desktop master-detail
        // Row below) actually gives this panel a bounded height to fill.
        final attendancePanel = LayoutBuilder(
          builder: (context, constraints) {
            final bounded = constraints.hasBoundedHeight;
            final table = _StudentAttendanceTableCard(
              records: studentAttendance,
              dates: _datesInWeek,
              weekStart: _weekStart,
              editMode: _editMode,
              onPreviousWeek: () => _changeWeek(-1),
              onNextWeek: () => _changeWeek(1),
              onAddAttendance: () => _addAttendanceDate(context),
              onEnterEditMode: _enterEditMode,
              onSaveChanges: _saveChanges,
              onDiscardChanges: _discardChanges,
              statusFor: _cellFor,
              onCellTap: _handleCellTap,
              onMarkAllForDate: _markAllForDate,
              onDeleteDate: widget.onDeleteAttendance == null ? null : _deleteAttendanceForDate,
            earlierByStudent: _earlierByStudent,
            earlierDate: _focusedDate,
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: bounded ? MainAxisSize.max : MainAxisSize.min,
              children: [
                _AttendanceStatsRow(summary: attendanceSummary),
                const SizedBox(height: 18),
                bounded ? Expanded(child: table) : table,
              ],
            );
          },
        );

        if (stackColumns) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              sectionListCard,
              const SizedBox(height: 16),
              attendancePanel,
            ],
          );
        }

        // Master-detail: the section-list "sidebar" is height-locked to
        // match the attendance panel (CrossAxisAlignment.stretch), capped
        // so the pair never grows past ~one viewport — the section list's
        // own list, and the attendance table, scroll internally within
        // that fixed height instead.
        return MasterDetailRowFrame(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 320, child: sectionListCard),
              const SizedBox(width: 18),
              Expanded(child: attendancePanel),
            ],
          ),
        );
      },
    );
  }

  Widget _buildConductReportContent({required bool isMobile}) {
    return ViolationReportsView(
      reports: reports,
      onSearchStudents: widget.onSearchReportStudents,
      onSubmit: widget.onSubmitReport,
      onDecide: widget.onDecideReport,
    );
  }
}

// ---------------------------------------------------------------------------
// Sub navigation bar (Attendance / Conduct Report / Admission Slip)
// ---------------------------------------------------------------------------

class _SubNavBar extends StatelessWidget {
  const _SubNavBar({required this.activeTab, required this.onTabSelected});

  final ProfessorDashboardTab activeTab;
  final ValueChanged<ProfessorDashboardTab> onTabSelected;

  @override
  Widget build(BuildContext context) {
    // Full-bleed strip pinned directly under the main header (see
    // DashboardSubNavStrip).
    return DashboardSubNavStrip(
      backgroundColor: ProfessorColors.card(context),
      borderColor: ProfessorColors.cardBorder(context),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SubNavItem(
            label: 'My Schedule',
            icon: Icons.calendar_month_outlined,
            isActive: activeTab == ProfessorDashboardTab.schedule,
            onTap: () => onTabSelected(ProfessorDashboardTab.schedule),
          ),
          const SizedBox(width: 45),
          _SubNavItem(
            label: 'Attendance',
            icon: Icons.fact_check_outlined,
            isActive: activeTab == ProfessorDashboardTab.attendance,
            onTap: () => onTabSelected(ProfessorDashboardTab.attendance),
          ),
          const SizedBox(width: 45),
          _SubNavItem(
            label: 'Violation Reports',
            icon: Icons.report_outlined,
            isActive: activeTab == ProfessorDashboardTab.conductReport,
            onTap: () => onTabSelected(ProfessorDashboardTab.conductReport),
          ),
        ],
      ),
    );
  }
}

class _SubNavItem extends StatelessWidget {
  const _SubNavItem({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => NavHoverUnderline(
        isActive: isActive,
        color: subNavActiveColor(context, ProfessorColors.azureBlue),
        child: _tab(context),
      );

  Widget _tab(BuildContext context) {
    final color = isActive
        ? subNavActiveColor(context, ProfessorColors.azureBlue)
        : ProfessorColors.mutedText(context);
    return InkWell(
      onTap: onTap,
      hoverColor: Colors.transparent,
      splashFactory: NoSplash.splashFactory,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              width: 2,
              color: isActive ? subNavActiveColor(context, ProfessorColors.azureBlue) : Colors.transparent,
            ),
          ),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: context.isMobileWidth ? 11 : 13,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// My Schedule tab
// ---------------------------------------------------------------------------

class _ScheduleEntryRow extends StatelessWidget {
  const _ScheduleEntryRow({required this.entry, required this.isMobile});

  final ProfessorScheduleEntryModel entry;
  final bool isMobile;

  @override
  Widget build(BuildContext context) {
    final titleStyle = GoogleFonts.poppins(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: ProfessorColors.rowText(context),
    );
    final subtitleStyle = GoogleFonts.poppins(
      fontSize: 11.5,
      color: ProfessorColors.mutedText(context),
    );
    final componentSuffix = entry.component == null ? '' : ' (${entry.component})';

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: ProfessorColors.cardBorder(context)),
        ),
      ),
      child: isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${entry.subjectTitle}$componentSuffix', style: titleStyle),
                Text(
                  '${entry.sectionName} · ${entry.day} ${formatClockRange12h(entry.startTime, entry.endTime)} · ${entry.room}',
                  style: subtitleStyle,
                ),
              ],
            )
          : Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text('${entry.subjectTitle}$componentSuffix', style: titleStyle),
                ),
                Expanded(flex: 2, child: Text(entry.sectionName, style: subtitleStyle)),
                Expanded(child: Text(entry.day, style: subtitleStyle)),
                Expanded(
                  flex: 2,
                  child: Text(formatClockRange12h(entry.startTime, entry.endTime), style: subtitleStyle),
                ),
                Expanded(child: Text(entry.room, style: subtitleStyle)),
              ],
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Left column — Subject & Section List (hierarchical accordion)
// ---------------------------------------------------------------------------

/// Subject-first sidebar: each [ProfessorSubjectModel] renders as an
/// expandable accordion group ([_SubjectGroup]); tapping one of its nested
/// [ProfessorSectionModel] rows makes it the active attendance context (see
/// [ProfessorDashboardPage.onSectionSelected]/[_selectActiveSection]).
/// [subjects] arrives pre-filtered by the page's search query
/// ([_filteredSubjects]) — this widget only owns which groups are expanded,
/// not the search/filter state itself.
class _SubjectSectionListCard extends StatefulWidget {
  const _SubjectSectionListCard({
    required this.subjects,
    required this.totalSectionCount,
    required this.activeSubjectId,
    required this.activeSectionId,
    required this.isSearching,
    required this.searchController,
    required this.onSearchChanged,
    required this.onSelect,
  });

  final List<ProfessorSubjectModel> subjects;
  final int totalSectionCount;
  final String? activeSubjectId;
  final String? activeSectionId;

  /// True whenever the search query is non-empty — while searching, every
  /// subject in [subjects] (already narrowed to matches) auto-expands so
  /// results are visible without also requiring a manual tap.
  final bool isSearching;

  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final void Function(
    ProfessorSubjectModel subject,
    ProfessorSectionModel section,
  ) onSelect;

  @override
  State<_SubjectSectionListCard> createState() =>
      _SubjectSectionListCardState();
}

class _SubjectSectionListCardState extends State<_SubjectSectionListCard> {
  /// Manually expanded/collapsed subjects, keyed by [ProfessorSubjectModel.id]
  /// — seeded with the active section's subject so it opens pre-expanded.
  late final Set<String> _expandedSubjectIds = {
    if (widget.activeSubjectId != null) widget.activeSubjectId!,
  };

  void _toggleExpanded(String subjectId) {
    setState(() {
      if (!_expandedSubjectIds.add(subjectId)) {
        _expandedSubjectIds.remove(subjectId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final subjects = widget.subjects;

    // Header/search stay fixed; only the list scrolls — as a bounded,
    // real-scrolling Expanded when an ancestor gives this card a fixed
    // height to match its detail-panel sibling (the desktop master-detail
    // Row), or as a Flexible that hugs up to whatever's available when it
    // doesn't (mobile/stacked, where the page itself scrolls instead).
    return LayoutBuilder(
      builder: (context, constraints) {
        final bounded = constraints.hasBoundedHeight;
        final Widget list = subjects.isEmpty
            ? const _SectionListEmptyState()
            : ListView(
                shrinkWrap: !bounded,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                children: [
                  for (final subject in subjects)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _SubjectGroup(
                        subject: subject,
                        expanded: widget.isSearching ||
                            _expandedSubjectIds.contains(subject.id),
                        activeSectionId: widget.activeSectionId,
                        activeSubjectId: widget.activeSubjectId,
                        onToggle: () => _toggleExpanded(subject.id),
                        onSelectSection: (section) =>
                            widget.onSelect(subject, section),
                      ),
                    ),
                ],
              );

        return BentoCard(
          backgroundColor: ProfessorColors.card(context),
          borderColor: ProfessorColors.cardBorder(context),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: bounded ? MainAxisSize.max : MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(29, 24, 29, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Subjects & Sections',
                      style: GoogleFonts.poppins(
                        fontSize: context.isMobileWidth ? 16 : 18,
                        fontWeight: FontWeight.w600,
                        color: ProfessorColors.rowText(context),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${widget.subjects.length} subjects · '
                      '${widget.totalSectionCount} sections',
                      style: GoogleFonts.poppins(
                        fontSize: context.isMobileWidth ? 11 : 13,
                        fontWeight: FontWeight.w400,
                        color: ProfessorColors.placeholderText(context),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(25, 19, 25, 0),
                child: Row(
                  children: [
                    Expanded(
                        child: _SectionSearchField(
                            controller: widget.searchController,
                            onChanged: widget.onSearchChanged)),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              bounded ? Expanded(child: list) : Flexible(child: list),
            ],
          ),
        );
      },
    );
  }
}

/// One expandable Subject accordion panel: a header row (name + total
/// enrolled students across every section, tap to expand/collapse) and,
/// while [expanded], its nested [_SubjectSectionRow]s.
class _SubjectGroup extends StatelessWidget {
  const _SubjectGroup({
    required this.subject,
    required this.expanded,
    required this.activeSectionId,
    required this.activeSubjectId,
    required this.onToggle,
    required this.onSelectSection,
  });

  final ProfessorSubjectModel subject;
  final bool expanded;
  final String? activeSectionId;
  final String? activeSubjectId;
  final VoidCallback onToggle;
  final ValueChanged<ProfessorSectionModel> onSelectSection;

  @override
  Widget build(BuildContext context) {
    // The same section can sit under several subjects, so "active" needs
    // both ids.
    final isActiveSubject = subject.id == activeSubjectId;

    // No highlight border on the group that holds the active section — the
    // selected section row itself already shows which one is active.
    return BentoCard(
      backgroundColor: ProfessorColors.background(context),
      borderColor: ProfessorColors.cardBorder(context),
      borderRadius: 14,
      elevated: false,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onToggle,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                child: Row(
                  children: [
                    AnimatedRotation(
                      turns: expanded ? 0.25 : 0,
                      duration: const Duration(milliseconds: 150),
                      child: Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: ProfessorColors.mutedText(context),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        subject.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                          fontSize: context.isMobileWidth ? 11.5 : 13,
                          fontWeight: FontWeight.w600,
                          color: ProfessorColors.rowText(context),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _SummaryBadge(count: subject.totalStudentCount),
                  ],
                ),
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Column(
                children: [
                  for (final section in subject.sections)
                    _SubjectSectionRow(
                      key: ValueKey(
                          'section-row-${section.classSectionId ?? section.id}'),
                      section: section,
                      isSelected: isActiveSubject &&
                          (section.classSectionId ?? section.id) ==
                              activeSectionId,
                      onTap: () => onSelectSection(section),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Small rounded student-count pill — used for both the subject header's
/// total and (implicitly, via [_SubjectSectionRow]) each section's own
/// count, so the two read as the same kind of summary badge at a glance.
class _SummaryBadge extends StatelessWidget {
  const _SummaryBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: ProfessorColors.selectedRow(context),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$count',
        style: GoogleFonts.poppins(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          // #A9C6FD in dark mode, like every other active-blue accent.
          color: subNavActiveColor(context, ProfessorColors.azureBlue),
        ),
      ),
    );
  }
}

/// One Section row nested under an expanded [_SubjectGroup] — highlighted
/// with [ProfessorColors.selectedRow] (a translucent azure-accent fill,
/// legible in both light and dark mode) whenever it's the active attendance
/// context, matching every other dashboard's selected-row convention
/// instead of a single hardcoded hex that would only suit one theme.
class _SubjectSectionRow extends StatelessWidget {
  const _SubjectSectionRow({
    super.key,
    required this.section,
    required this.isSelected,
    required this.onTap,
  });

  final ProfessorSectionModel section;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected
          ? ProfessorColors.selectedRow(context)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Row(
            children: [
              Icon(
                isSelected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 14,
                color: isSelected
                    ? subNavActiveColor(context, ProfessorColors.azureBlue)
                    : ProfessorColors.mutedText(context),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  section.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: context.isMobileWidth ? 11 : 12.5,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: ProfessorColors.rowText(context),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _SummaryBadge(count: section.studentCount),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionSearchField extends StatelessWidget {
  const _SectionSearchField(
      {required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: kDashboardControlHeight,
      child: TextField(
        expands: true,
        maxLines: null,
        minLines: null,
        textAlignVertical: TextAlignVertical.center,
        keyboardType: TextInputType.text,
        controller: controller,
        onChanged: onChanged,
        style: GoogleFonts.poppins(
          fontSize: context.isMobileWidth ? 11 : 13,
          color: ProfessorColors.rowText(context),
        ),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Search',
          hintStyle: GoogleFonts.poppins(
            fontSize: context.isMobileWidth ? 11 : 13,
            color: ProfessorColors.placeholderText(context),
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            size: 20,
            color: ProfessorColors.placeholderText(context),
          ),
          filled: true,
          fillColor: ProfessorColors.background(context),
          contentPadding: EdgeInsets.zero,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}

class _SectionListEmptyState extends StatelessWidget {
  const _SectionListEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'No subjects or sections found',
        style: GoogleFonts.poppins(
          fontSize: context.isMobileWidth ? 11 : 13,
          fontWeight: FontWeight.w500,
          color: ProfessorColors.mutedText(context),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Right column — attendance stat cards
// ---------------------------------------------------------------------------

class _AttendanceStatsRow extends StatelessWidget {
  const _AttendanceStatsRow({required this.summary});

  final AttendanceSummaryModel summary;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 560;
        final cards = [
          _StatCard(
            label: 'Present',
            value: '${summary.present}',
            icon: Icons.how_to_reg_outlined,
          ),
          _StatCard(
            label: 'Absent',
            value: '${summary.absent}',
            icon: Icons.person_off_outlined,
          ),
          _StatCard(
            label: 'Late',
            value: '${summary.late}',
            icon: Icons.person_remove_outlined,
          ),
          _StatCard(
            label: 'Excuse',
            value: '${summary.excused}',
            icon: Icons.info_outline,
          ),
        ];

        if (isNarrow) {
          return MobileMetricGrid(cards: cards);
        }

        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final card in cards) ...[
                Expanded(child: card),
                if (card != cards.last) const SizedBox(width: 18),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard(
      {required this.label, required this.value, required this.icon});

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return BentoCard(
      backgroundColor: ProfessorColors.card(context),
      borderColor: ProfessorColors.cardBorder(context),
      padding: const EdgeInsets.fromLTRB(27, 16, 20, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  label,
                  style: GoogleFonts.poppins(
                    fontSize: context.isMobileWidth ? 10 : 12,
                    fontWeight: FontWeight.w600,
                    color: ProfessorColors.mutedText(context),
                  ),
                ),
                Text(
                  value,
                  style: GoogleFonts.poppins(
                    fontSize: context.isMobileWidth ? 30 : 32,
                    fontWeight: FontWeight.w600,
                    color: ProfessorColors.statValue(context),
                  ),
                ),
              ],
            ),
          ),
          Icon(icon, size: 24, color: ProfessorColors.mutedText(context)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Right column — student attendance table
// ---------------------------------------------------------------------------

class _StudentAttendanceTableCard extends StatefulWidget {
  const _StudentAttendanceTableCard({
    required this.records,
    required this.dates,
    required this.weekStart,
    required this.editMode,
    required this.onPreviousWeek,
    required this.onNextWeek,
    required this.onAddAttendance,
    required this.onEnterEditMode,
    required this.onSaveChanges,
    required this.onDiscardChanges,
    required this.statusFor,
    required this.onCellTap,
    required this.onMarkAllForDate,
    this.onDeleteDate,
    this.earlierByStudent = const {},
    this.earlierDate,
  });

  /// Each student's other classes on [earlierDate], shown in a popup when a
  /// student's name is clicked.
  final Map<String, List<EarlierClassStatus>> earlierByStudent;
  final DateTime? earlierDate;

  final List<StudentAttendanceRecordModel> records;

  /// This week's session dates, newest first — the matrix's date columns,
  /// left to right.
  final List<DateTime> dates;
  final DateTime weekStart;

  /// True while cells accept taps and the toolbar shows Save/Discard
  /// instead of an Edit toggle.
  final bool editMode;

  final VoidCallback onPreviousWeek;
  final VoidCallback onNextWeek;
  final VoidCallback onAddAttendance;
  final VoidCallback onEnterEditMode;
  final VoidCallback onSaveChanges;
  final VoidCallback onDiscardChanges;

  final AttendanceCellModel? Function(String studentRecordId, DateTime date)
      statusFor;
  final void Function(String studentRecordId, DateTime date) onCellTap;
  final void Function(DateTime date, AttendanceStatus status) onMarkAllForDate;

  /// Deletes a day's attendance; null hides the menu item.
  final void Function(DateTime date)? onDeleteDate;

  @override
  State<_StudentAttendanceTableCard> createState() =>
      _StudentAttendanceTableCardState();
}

class _StudentAttendanceTableCardState
    extends State<_StudentAttendanceTableCard> {
  @override
  Widget build(BuildContext context) {
    // Alphabetical by first name — studentName is "First [Middle] Last", so
    // a plain case-insensitive full-name compare already sorts on the
    // leading first-name token first.
    final records = List<StudentAttendanceRecordModel>.of(widget.records)
      ..sort(
        (a, b) => a.studentName
            .trim()
            .toLowerCase()
            .compareTo(b.studentName.trim().toLowerCase()),
      );

    // Toolbar stays fixed above the matrix, which owns its own sticky
    // column-header + scrollable rows (see _AttendanceMatrix) — every
    // student shows up in that one scrollable table, no pagination.
    return LayoutBuilder(
      builder: (context, constraints) {
        final bounded = constraints.hasBoundedHeight;
        // Even with nothing to list, the table keeps its header band above
        // the empty state, like every other dashboard table.
        final Widget body = records.isEmpty
            ? const _AttendanceEmptyBody(
                child: DashboardTableEmptyState(
                  icon: Icons.groups_outlined,
                  message: 'No attendance records for this section yet',
                ),
              )
            : widget.dates.isEmpty
                ? _AttendanceEmptyBody(
                    child: _EmptyWeekState(
                        onAddAttendance: widget.onAddAttendance),
                  )
                : _AttendanceMatrix(
                    records: records,
                    dates: widget.dates,
                    editMode: widget.editMode,
                    statusFor: widget.statusFor,
                    onCellTap: widget.onCellTap,
                    onMarkAllForDate: widget.onMarkAllForDate,
                    onDeleteDate: widget.onDeleteDate,
                    earlierByStudent: widget.earlierByStudent,
                    earlierDate: widget.earlierDate,
                  );

        return BentoCard(
          backgroundColor: ProfessorColors.card(context),
          borderColor: ProfessorColors.cardBorder(context),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: bounded ? MainAxisSize.max : MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                child: _AttendanceToolbar(
                  weekStart: widget.weekStart,
                  editMode: widget.editMode,
                  onPreviousWeek: widget.onPreviousWeek,
                  onNextWeek: widget.onNextWeek,
                  onAddAttendance: widget.onAddAttendance,
                  onEnterEditMode: widget.onEnterEditMode,
                  onSaveChanges: widget.onSaveChanges,
                  onDiscardChanges: widget.onDiscardChanges,
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: _AttendanceLegend(),
              ),
              // The table runs to the card's bottom edge (no pagination
              // footer, so nothing sits below the last row).
              bounded ? Expanded(child: body) : body,
            ],
          ),
        );
      },
    );
  }
}

/// What each attendance icon means — spelled out so status never relies on
/// colour alone.
class _AttendanceLegend extends StatelessWidget {
  const _AttendanceLegend();

  @override
  Widget build(BuildContext context) {
    const shown = [
      (AttendanceStatus.present, 'Present'),
      (AttendanceStatus.absent, 'Absent'),
      (AttendanceStatus.tardy, 'Late'),
      (AttendanceStatus.excused, 'Excused'),
      (AttendanceStatus.none, 'Not recorded'),
    ];
    return Wrap(
      spacing: 14,
      runSpacing: 4,
      children: [
        for (final (status, label) in shown)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(status.icon, size: 15, color: status.color),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: status.color,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

/// The matrix's header band (just a "Student" column) over [child] — the
/// no-records and no-sessions-this-week states, laid out like any other
/// dashboard table's empty state.
class _AttendanceEmptyBody extends StatelessWidget {
  const _AttendanceEmptyBody({required this.child});

  final Widget child;

  static const _columns = [DashboardTableColumn('Student', minWidth: 220)];

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const DashboardTableHeader(columns: _columns, topBorder: true),
        child,
      ],
    );
  }
}

/// Toolbar above the matrix: week navigation, "+ Add Attendance", and
/// either an Edit toggle or a Save Changes/Discard pair — switches to a
/// two-row stacked layout below [_compactBreakpoint] using its OWN
/// available width ([LayoutBuilder]), not the whole screen's, since this
/// card can sit in either the wide desktop panel or the narrower
/// mobile-stacked column.
class _AttendanceToolbar extends StatelessWidget {
  const _AttendanceToolbar({
    required this.weekStart,
    required this.editMode,
    required this.onPreviousWeek,
    required this.onNextWeek,
    required this.onAddAttendance,
    required this.onEnterEditMode,
    required this.onSaveChanges,
    required this.onDiscardChanges,
  });

  final DateTime weekStart;
  final bool editMode;
  final VoidCallback onPreviousWeek;
  final VoidCallback onNextWeek;
  final VoidCallback onAddAttendance;
  final VoidCallback onEnterEditMode;
  final VoidCallback onSaveChanges;
  final VoidCallback onDiscardChanges;

  static const _compactBreakpoint = 640.0;

  @override
  Widget build(BuildContext context) {
    final title = Text(
      'Student List',
      overflow: TextOverflow.ellipsis,
      style: dashboardCardTitleStyle(context,
          color: ProfessorColors.rowText(context)),
    );

    final weekNav = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ToolbarIconButton(
            icon: Icons.chevron_left_rounded,
            tooltip: 'Previous week',
            onTap: onPreviousWeek),
        Flexible(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              formatWeekRangeLabel(weekStart),
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: ProfessorColors.rowText(context),
              ),
            ),
          ),
        ),
        _ToolbarIconButton(
            icon: Icons.chevron_right_rounded,
            tooltip: 'Next week',
            onTap: onNextWeek),
      ],
    );

    final addButton = _ToolbarActionButton(
      label: '+ Add Attendance',
      onTap: onAddAttendance,
      filled: true,
    );

    final editControls = editMode
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ToolbarActionButton(
                label: 'Discard',
                onTap: onDiscardChanges,
                color: ProfessorColors.dangerRed,
              ),
              const SizedBox(width: 8),
              _ToolbarActionButton(
                label: 'Save Changes',
                onTap: onSaveChanges,
                filled: true,
                color: ProfessorColors.successGreen,
              ),
            ],
          )
        : _ToolbarActionButton(
            label: 'Edit',
            icon: Icons.edit_outlined,
            onTap: onEnterEditMode,
          );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < _compactBreakpoint) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: title),
                  const SizedBox(width: 8),
                  addButton,
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [weekNav, editControls],
              ),
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: title),
            weekNav,
            const SizedBox(width: 14),
            editControls,
            const SizedBox(width: 10),
            addButton,
          ],
        );
      },
    );
  }
}

class _ToolbarIconButton extends StatelessWidget {
  const _ToolbarIconButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: ProfessorColors.background(context),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 28,
          height: 28,
          child:
              Icon(icon, size: 16, color: ProfessorColors.mutedText(context)),
        ),
      ),
    );
    final tooltip = this.tooltip;
    return tooltip == null ? button : Tooltip(message: tooltip, child: button);
  }
}

class _ToolbarActionButton extends StatelessWidget {
  const _ToolbarActionButton({
    required this.label,
    required this.onTap,
    this.icon,
    this.filled = false,
    this.color,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool filled;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    // Unfilled = a secondary action: the app-wide tinted pill (red when it
    // was given the danger color, e.g. "Discard"). Filled stays the solid
    // primary button below.
    if (!filled) {
      return SecondaryPillButton(
        label: label,
        icon: icon,
        onTap: onTap,
        destructive: color == ProfessorColors.dangerRed,
      );
    }
    final accent = color ?? ProfessorColors.azureBlue;
    const foreground = Colors.white;
    return Material(
      color: filled ? accent : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: filled ? null : Border.all(color: accent),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 15, color: foreground),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: foreground,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyWeekState extends StatelessWidget {
  const _EmptyWeekState({required this.onAddAttendance});

  final VoidCallback onAddAttendance;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_busy_rounded,
                size: 32, color: ProfessorColors.mutedText(context)),
            const SizedBox(height: 10),
            Text(
              'No attendance sessions recorded for this week.',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: ProfessorColors.mutedText(context),
              ),
            ),
            const SizedBox(height: 14),
            _ToolbarActionButton(
              label: '+ Add Attendance',
              onTap: onAddAttendance,
              filled: true,
            ),
          ],
        ),
      ),
    );
  }
}

/// The matrix body: a fixed "Student" column (name + ID, never scrolls
/// horizontally) beside the date columns, which scroll horizontally as a
/// unit — the whole `Row` shares one vertical scroll position (from
/// whichever ancestor makes this scroll; see
/// `_StudentAttendanceTableCardState`), so the name column and the date
/// cells always stay lined up row-for-row.
class _AttendanceMatrix extends StatefulWidget {
  const _AttendanceMatrix({
    required this.records,
    required this.dates,
    required this.editMode,
    required this.statusFor,
    required this.onCellTap,
    required this.onMarkAllForDate,
    this.onDeleteDate,
    this.earlierByStudent = const {},
    this.earlierDate,
  });

  final List<StudentAttendanceRecordModel> records;
  final List<DateTime> dates;
  final bool editMode;
  final AttendanceCellModel? Function(String studentRecordId, DateTime date)
      statusFor;
  final void Function(String studentRecordId, DateTime date) onCellTap;
  final void Function(DateTime date, AttendanceStatus status) onMarkAllForDate;

  /// Deletes a day's attendance; null hides the menu item.
  final void Function(DateTime date)? onDeleteDate;

  /// Each student's other same-day classes (per student record id) for
  /// [earlierDate], listed in a popup when the student's name is clicked.
  final Map<String, List<EarlierClassStatus>> earlierByStudent;
  final DateTime? earlierDate;

  @override
  State<_AttendanceMatrix> createState() => _AttendanceMatrixState();
}

class _AttendanceMatrixState extends State<_AttendanceMatrix> {
  // Body rows scroll vertically together (name column + date columns, kept
  // in sync just by being siblings inside one shared SingleChildScrollView)
  // and — on a narrow viewport with more date columns than fit — also
  // horizontally. The header row never scrolls on its own (its
  // NeverScrollableScrollPhysics SingleChildScrollView is only ever
  // repositioned programmatically) — it just mirrors the body's horizontal
  // offset so the date columns stay aligned under their labels.
  final _verticalController = ScrollController();
  final _headerHorizontalController = ScrollController();
  final _bodyHorizontalController = ScrollController();

  static const _minNameColumnWidth = 200.0;
  static const _maxNameColumnShare = 0.55;
  static const _dateColumnWidth = 112.0;

  /// The Student column's current width — see [_measureNameColumnWidth].
  double _nameColumnWidth = _minNameColumnWidth;

  /// The "i" button's own column, to the left of the Student column: the
  /// button's size and the column's fixed width. The Student column has no
  /// left padding of its own, so the column's right edge is where the name
  /// text starts and the "i" sits centered in the space between the card's edge
  /// and the text.
  static const _infoSize = 18.0;
  static const _infoColumnWidth = 56.0;

  // Same chrome as every dashboard table (DashboardTable* in
  // dashboard_layout): a header band of 14px padding around an 11px label
  // inside top + bottom dividers, and rows of 64px inside a 1px divider.
  static const _headerHeight = 46.0;
  static const _rowHeight = 65.0;

  /// Row [i]'s height — one fixed height for every student, used by BOTH the
  /// name column and the date cells so rows stay aligned. (A student's other
  /// classes are no longer listed in the row; they open in a popup.)
  double _rowHeightFor(int i) => _rowHeight;

  /// The Student column's width: wide enough for the WIDEST thing currently in
  /// it — a full name, a student number, or a "Tapped in / In … · Out …" pill
  /// (icon and padding included) — each on ONE line, never wrapped, never
  /// clipped. Never narrower than [_minNameColumnWidth]; capped at
  /// [_maxNameColumnShare] of the window so a freak value can't push the date
  /// columns off screen (past that it ellipsizes). Recomputed at the start of
  /// every build, so it follows the list as students and taps change.
  double _measureNameColumnWidth(BuildContext context) {
    // The same styles the cells' Texts end up with: each style merged over the
    // surrounding DefaultTextStyle, so the measured width matches what is
    // drawn.
    final inherited = DefaultTextStyle.of(context).style;
    final nameStyle = inherited.merge(dashboardTablePrimaryStyle(context));
    final idStyle = inherited.merge(dashboardTableSubStyle(context));
    final pillStyle = inherited.merge(TapInPill.textStyle);
    final scaler = MediaQuery.textScalerOf(context);
    double widthOf(String text, TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final w = painter.width;
      painter.dispose();
      return w;
    }

    var longest = 0.0;
    for (final r in widget.records) {
      longest = math.max(longest, widthOf(r.studentName, nameStyle));
      longest = math.max(longest, widthOf(r.studentId, idStyle));
      // The tap pill: icon + gap + label + its own side padding.
      longest = math.max(
        longest,
        2 * TapInPill.horizontalPadding +
            TapInPill.iconBlockWidth +
            widthOf(
                TapInPill.labelFor(r.kioskTapInAt, r.kioskTapOutAt), pillStyle),
      );
    }
    // + the cell's side padding, and a pixel of slack so a name that exactly
    // fills the column is never clipped by rounding.
    final wanted = longest.ceilToDouble() + DashboardTableMetrics.horizontalPadding + 1;
    final cap = MediaQuery.sizeOf(context).width * _maxNameColumnShare;
    return math.max(_minNameColumnWidth, math.min(wanted, cap));
  }

  /// Opens the popup listing [record]'s other classes on [_AttendanceMatrix.earlierDate].
  void _openOtherClasses(StudentAttendanceRecordModel record) {
    showAppPopup<void>(
      context: context,
      builder: (_) => EarlierClassesPopup(
        studentName: record.studentName,
        studentId: record.studentId,
        date: widget.earlierDate,
        items: widget.earlierByStudent[record.id] ?? const [],
      ),
    );
  }

  /// The row under the mouse, highlighted across both the name column and
  /// the date columns (they are separate widgets, so the hover is shared).
  int? _hoveredRow;

  void _setHoveredRow(int? row) {
    if (_hoveredRow != row) setState(() => _hoveredRow = row);
  }

  /// A body row's background: the table's hover color while hovered, else
  /// the same color at zero alpha (not transparent black — see
  /// DashboardTableRow) so the fade stays clean. Plus its divider, except
  /// under the last row.
  BoxDecoration _rowDecoration(BuildContext context, int index) {
    final hover = DashboardTableColors.rowHover(context);
    return BoxDecoration(
      color: _hoveredRow == index ? hover : hover.withOpacity(0),
      border: index < widget.records.length - 1
          ? Border(
              bottom: BorderSide(color: DashboardTableColors.border(context)))
          : null,
    );
  }

  /// Fallback body height when no ancestor gives this table a bounded
  /// height (mobile/stacked layout, where the page itself also scrolls) —
  /// caps at roughly 6 rows so the table still scrolls internally under its
  /// sticky header instead of growing the whole page to fit every student.
  static const _maxUnboundedBodyRows = 6;

  @override
  void initState() {
    super.initState();
    _bodyHorizontalController.addListener(_syncHeaderScroll);
  }

  void _syncHeaderScroll() {
    if (_headerHorizontalController.hasClients) {
      _headerHorizontalController.jumpTo(_bodyHorizontalController.offset);
    }
  }

  @override
  void dispose() {
    _bodyHorizontalController.removeListener(_syncHeaderScroll);
    _verticalController.dispose();
    _headerHorizontalController.dispose();
    _bodyHorizontalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _nameColumnWidth = _measureNameColumnWidth(context);

    // The "i" column: its own narrow column left of the Student column — a
    // blank header cell, then one centered "i" per row (same row heights and
    // hover as every other cell) that opens that student's other classes.
    const infoHeaderCell = SizedBox(
      width: _infoColumnWidth,
      height: _headerHeight,
    );
    final infoBodyColumn = Column(
      children: [
        for (var i = 0; i < widget.records.length; i++)
          MouseRegion(
            onEnter: (_) => _setHoveredRow(i),
            onExit: (_) => _setHoveredRow(null),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              height: _rowHeightFor(i),
              alignment: Alignment.center,
              decoration: _rowDecoration(context, i),
              child: _OtherClassesButton(
                key: ValueKey('student-info-${widget.records[i].id}'),
                onTap: () => _openOtherClasses(widget.records[i]),
              ),
            ),
          ),
      ],
    );

    final nameHeaderCell = Container(
      width: _nameColumnWidth,
      height: _headerHeight,
      alignment: Alignment.centerLeft,
      // No left padding: the "i" column to its left supplies the gap, so the
      // "i" reads centered between the card edge and the text.
      padding: const EdgeInsets.only(
        right: DashboardTableMetrics.horizontalPadding,
      ),
      child: Text(
        'STUDENT',
        softWrap: false,
        maxLines: 1,
        style: dashboardTableHeaderStyle(context),
      ),
    );

    final nameBodyColumn = Column(
      children: [
        for (var i = 0; i < widget.records.length; i++)
          MouseRegion(
            onEnter: (_) => _setHoveredRow(i),
            onExit: (_) => _setHoveredRow(null),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              height: _rowHeightFor(i),
              padding: const EdgeInsets.only(
                right: DashboardTableMetrics.horizontalPadding,
              ),
              alignment: Alignment.centerLeft,
              decoration: _rowDecoration(context, i),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // One line, always: the column is sized to the longest name
                  // (see _measureNameColumnWidth), so it is not clipped.
                  Text(
                    widget.records[i].studentName,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: dashboardTablePrimaryStyle(context),
                  ),
                  Text(
                    widget.records[i].studentId,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: dashboardTableSubStyle(context),
                  ),
                  TapInPill(
                    tapInAt: widget.records[i].kioskTapInAt,
                    tapOutAt: widget.records[i].kioskTapOutAt,
                  ),
                ],
              ),
            ),
          ),
      ],
    );

    // The whole matrix (header + body) is measured once here so both the
    // fixed header row and the scrollable body rows agree on the exact same
    // "do the date columns fit, or do they scroll horizontally instead"
    // decision — they sit in structurally identical Row(nameColumn,
    // Expanded(dateColumns)) shells, so the width available to each
    // Expanded is identical too.
    return LayoutBuilder(
      builder: (context, outerConstraints) {
        final dateAreaWidth =
            outerConstraints.maxWidth - _infoColumnWidth - _nameColumnWidth;
        final naturalWidth = widget.dates.length * _dateColumnWidth;
        // Date columns fill the rest of the card's width, evenly split,
        // whenever that leaves them at least as wide as _dateColumnWidth —
        // since _datesInWeek caps out at 6 (Monday-Saturday), this is the
        // common case and is what stops the table from leaving whitespace
        // on the right. Below that minimum (many columns on a narrow
        // viewport) columns keep their fixed width and the rows scroll
        // horizontally instead of squeezing them unreadably thin.
        final flexible = naturalWidth <= dateAreaWidth;

        Widget columnCell(Widget child, double height) {
          return flexible
              ? Expanded(child: SizedBox(height: height, child: child))
              : SizedBox(width: _dateColumnWidth, height: height, child: child);
        }

        final headerDatesRow = Row(
          children: [
            for (final date in widget.dates)
              columnCell(
                _DateColumnHeader(
                  date: date,
                  editMode: widget.editMode,
                  onMarkAll: (status) =>
                      widget.onMarkAllForDate(date, status),
                  onDelete: widget.onDeleteDate == null
                      ? null
                      : () => widget.onDeleteDate!(date),
                ),
                _headerHeight,
              ),
          ],
        );

        final bodyDatesColumn = Column(
          children: [
            for (var i = 0; i < widget.records.length; i++)
              MouseRegion(
                onEnter: (_) => _setHoveredRow(i),
                onExit: (_) => _setHoveredRow(null),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  decoration: _rowDecoration(context, i),
                  child: Row(
                    children: [
                      for (final date in widget.dates)
                        columnCell(
                          _AttendanceCellView(
                            key: ValueKey(
                                'attendance-cell-${widget.records[i].id}-${date.year}-${date.month}-${date.day}'),
                            status: widget
                                    .statusFor(widget.records[i].id, date)
                                    ?.status ??
                                AttendanceStatus.none,
                            editMode: widget.editMode,
                            onTap: () =>
                                widget.onCellTap(widget.records[i].id, date),
                          ),
                          // The row's own height less its divider, which the
                          // wrapper above draws.
                          i < widget.records.length - 1
                              ? _rowHeightFor(i) - 1
                              : _rowHeightFor(i),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        );

        // The header band: the table's header fill and top + bottom
        // dividers across the whole width (name column and dates alike).
        final headerBorder =
            BorderSide(color: DashboardTableColors.border(context));
        final headerRow = Container(
          height: _headerHeight,
          decoration: BoxDecoration(
            color: DashboardTableColors.headerBackground(context),
            border: Border(top: headerBorder, bottom: headerBorder),
          ),
          child: Row(
            children: [
              infoHeaderCell,
              nameHeaderCell,
              Expanded(
                child: !flexible
                    ? SingleChildScrollView(
                        controller: _headerHorizontalController,
                        scrollDirection: Axis.horizontal,
                        physics: const NeverScrollableScrollPhysics(),
                        child: headerDatesRow,
                      )
                    : headerDatesRow,
              ),
            ],
          ),
        );

        final scrollableBody = Scrollbar(
          controller: _verticalController,
          child: SingleChildScrollView(
            controller: _verticalController,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: _infoColumnWidth, child: infoBodyColumn),
                SizedBox(width: _nameColumnWidth, child: nameBodyColumn),
                Expanded(
                  child: !flexible
                      ? Scrollbar(
                          controller: _bodyHorizontalController,
                          child: SingleChildScrollView(
                            controller: _bodyHorizontalController,
                            scrollDirection: Axis.horizontal,
                            child: bodyDatesColumn,
                          ),
                        )
                      : bodyDatesColumn,
                ),
              ],
            ),
          ),
        );

        // The header stays fixed at the top; only the rows below it scroll
        // — filling whatever bounded height an ancestor gives this table
        // (the desktop master-detail case), or a fixed fallback height so
        // it still scrolls internally rather than growing the whole page
        // (mobile).
        final bodyArea = outerConstraints.hasBoundedHeight
            ? Expanded(child: scrollableBody)
            : SizedBox(
                height:
                    math.min(widget.records.length, _maxUnboundedBodyRows) *
                        _rowHeight,
                child: scrollableBody,
              );

        return Column(
          mainAxisSize: outerConstraints.hasBoundedHeight
              ? MainAxisSize.max
              : MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [headerRow, bodyArea],
        );
      },
    );
  }
}

/// Today's kiosk tap-in for one student: a green "Tapped in 7:42 AM" pill or
/// a muted "No tap yet" pill — shown under the name in the attendance matrix.
@visibleForTesting
class TapInPill extends StatelessWidget {
  const TapInPill({super.key, required this.tapInAt, this.tapOutAt});

  final DateTime? tapInAt;

  /// Last tap-out today; when set the pill also says the student has left.
  final DateTime? tapOutAt;

  static String _time(DateTime t) {
    final hour = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final minute = t.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${t.hour >= 12 ? 'PM' : 'AM'}';
  }

  /// The pill's text: "Tapped in 8:05 AM", "No tap yet", or — once the student
  /// has left for the day — "In 8:05 AM · Out 3:10 PM".
  static String labelFor(DateTime? tapInAt, DateTime? tapOutAt) {
    final out = tapOutAt;
    if (out != null) {
      return tapInAt != null
          ? 'In ${_time(tapInAt)} · Out ${_time(out)}'
          : 'Tapped out ${_time(out)}';
    }
    return tapInAt != null ? 'Tapped in ${_time(tapInAt)}' : 'No tap yet';
  }

  /// The pill's text style, side padding and icon block — shared with the
  /// attendance matrix, which sizes its Student column to fit the widest pill.
  static const textStyle = TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600);
  static const horizontalPadding = 8.0;
  static const iconBlockWidth = 12.0 + 4.0; // 12px icon + 4px gap

  @override
  Widget build(BuildContext context) {
    final tapped = tapInAt != null;
    final out = tapOutAt;
    // A single pill (the row height is fixed): "Tapped in 8:05 AM", and once
    // the student has left for the day "In 8:05 AM · Out 3:10 PM" in amber.
    final color = out != null
        ? ProfessorColors.warningYellow
        : tapped
            ? ProfessorColors.successGreen
            : ProfessorColors.statusNeutral;
    final label = labelFor(tapInAt, tapOutAt);
    final icon = out != null
        ? Icons.logout_rounded
        : (tapped ? Icons.sensors_rounded : Icons.sensors_off_rounded);
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: horizontalPadding, vertical: 2),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 12,
              color: color,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textStyle.copyWith(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The small "i" to the left of a student's name; tapping it opens that
/// student's other classes for the day.
class _OtherClassesButton extends StatelessWidget {
  const _OtherClassesButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'See other classes',
      child: InkResponse(
        onTap: onTap,
        radius: 14,
        child: SizedBox(
          width: _AttendanceMatrixState._infoSize,
          height: _AttendanceMatrixState._infoSize,
          child: Icon(
            Icons.info_outline_rounded,
            size: 17,
            color: DashboardTableColors.secondaryText(context),
          ),
        ),
      ),
    );
  }
}

/// What each attendance status is called in the other-classes popup.
String earlierClassStatusLabel(AttendanceStatus s) => switch (s) {
      AttendanceStatus.none => 'Not recorded',
      AttendanceStatus.excused => 'Excused',
      AttendanceStatus.tardy => 'Late',
      _ => s.value,
    };

/// The popup opened by clicking a student's name in the attendance matrix: the
/// student's OTHER classes on [date] (earliest first) with how each was
/// recorded — "7:00 AM Network Technology · Not recorded". These used to be
/// chips under the name; the popup keeps the row compact while the tap in/out
/// pill stays visible without opening anything.
@visibleForTesting
class EarlierClassesPopup extends StatelessWidget {
  const EarlierClassesPopup({
    super.key,
    required this.studentName,
    required this.studentId,
    required this.date,
    required this.items,
  });

  final String studentName;
  final String studentId;

  /// The day [items] are for, or null when no date is focused.
  final DateTime? date;
  final List<EarlierClassStatus> items;

  @override
  Widget build(BuildContext context) {
    final c = AppPopupColors.of(context);
    final day = date == null ? null : formatDayMonthDate(date!);
    return AppPopup(
      title: studentName,
      subtitle: day == null ? studentId : '$studentId · Other classes on $day',
      width: 460,
      actions: [
        AppPopupSecondaryButton(
          label: 'Close',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
      body: items.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                date == null
                    ? "Pick a date column to see this student's other classes."
                    : 'No other classes recorded for this day.',
                style: GoogleFonts.poppins(fontSize: 12.5, color: c.muted),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final item in items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: EarlierClassRow(item: item),
                  ),
              ],
            ),
    );
  }
}

/// One line of [EarlierClassesPopup]: the status icon, "7:00 AM Network
/// Technology" over the professor, and the status as a colored pill.
@visibleForTesting
class EarlierClassRow extends StatelessWidget {
  const EarlierClassRow({super.key, required this.item});

  final EarlierClassStatus item;

  /// "7:00 AM Network Technology".
  static String titleFor(EarlierClassStatus item) =>
      '${formatClock12h(item.startTime)} ${item.subjectName}';

  @override
  Widget build(BuildContext context) {
    final c = AppPopupColors.of(context);
    final color = item.status.color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: c.fieldFill,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(item.status.icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titleFor(item),
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: c.text,
                  ),
                ),
                if (item.professorName.trim().isNotEmpty)
                  Text(
                    item.professorName,
                    style: GoogleFonts.poppins(fontSize: 11.5, color: c.muted),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: color.withOpacity(0.14),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              earlierClassStatusLabel(item.status),
              style: GoogleFonts.poppins(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DateColumnHeader extends StatelessWidget {
  const _DateColumnHeader({
    required this.date,
    required this.editMode,
    required this.onMarkAll,
    this.onDelete,
  });

  final DateTime date;
  final bool editMode;
  final ValueChanged<AttendanceStatus> onMarkAll;

  /// "Delete attendance for this day"; null leaves it out of the menu.
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    // UPPERCASE label centered over its column (the status icons below are
    // centered too), on the band's fill (the band itself is painted by
    // _AttendanceMatrixState). In edit mode the bulk-actions menu is pinned to
    // the column's right edge, and the label keeps clear of it, so the label
    // stays centered with or without it.
    return Stack(
      alignment: Alignment.center,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: editMode ? 24 : 4),
          child: Text(
            formatDayMonthDate(date).toUpperCase(),
            textAlign: TextAlign.center,
            softWrap: false,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: dashboardTableHeaderStyle(context),
          ),
        ),
        if (editMode)
          Positioned(
            right: 0,
            child: PopupMenuButton<Object>(
              tooltip: 'Bulk actions for ${formatDayMonthDate(date)}',
              padding: EdgeInsets.zero,
              icon: Icon(Icons.more_vert_rounded,
                  size: 16, color: DashboardTableColors.headerText(context)),
              onSelected: (value) {
                if (value is AttendanceStatus) {
                  onMarkAll(value);
                } else {
                  onDelete?.call();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem<Object>(
                  value: AttendanceStatus.present,
                  child: Text('Mark all Present'),
                ),
                const PopupMenuItem<Object>(
                  value: AttendanceStatus.absent,
                  child: Text('Mark all Absent'),
                ),
                if (onDelete != null) ...[
                  const PopupMenuDivider(),
                  PopupMenuItem<Object>(
                    value: 'delete',
                    child: Text(
                      'Delete attendance for this day',
                      style: TextStyle(color: ProfessorColors.dangerRed),
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _AttendanceCellView extends StatelessWidget {
  const _AttendanceCellView({
    super.key,
    required this.status,
    required this.editMode,
    required this.onTap,
  });

  final AttendanceStatus status;
  final bool editMode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // No cell borders: the row's divider and hover are drawn by the matrix.
    // The icon sits in the middle of its column, under the centered date label.
    return Align(
      alignment: Alignment.center,
      child: Tooltip(
        message: editMode
            ? '${status.value} — tap to mark ${status.next.value}'
            : status.value,
        child: InkResponse(
          onTap: editMode ? onTap : null,
          radius: 20,
          child: Icon(status.icon, size: 22, color: status.color),
        ),
      ),
    );
  }
}
