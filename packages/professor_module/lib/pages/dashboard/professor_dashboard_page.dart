import 'dart:math' as math;

import 'package:dashboard_layout/dashboard_layout.dart';
// Reuses the Discipline Officer module's shared header-popover components
// directly rather than duplicating them, matching the same pattern the
// Guidance Counselor module already uses for this widget set.
import 'package:discipline_officer_module/discipline_officer_module.dart'
    show
        AccountProfileMenu,
        EmailListView,
        EmailPopover,
        LogoutConfirmationDialog,
        NotificationItemModel,
        NotificationsListView,
        NotificationsPopover,
        ProfileScreen,
        showHeaderPopover;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../data/admission_slip_mock_data.dart';
import '../../data/conduct_mock_data.dart';
import '../../data/professor_mock_data.dart';
import '../../theme/professor_colors.dart';
import 'admission_slip_view.dart';
import 'conduct_report_view.dart';

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
  });

  final String id;
  final String name;
  final int studentCount;

  /// The parent [ProfessorSubjectModel] this section is offered under, for
  /// grouping in the Section List sidebar's accordion. Nullable because the
  /// live `fetchAssignedSections` query (lib/data/professor_repository.dart)
  /// doesn't join subject data yet — see [ProfessorDashboardPage._subjects],
  /// which falls every section with a null [subjectName] back into one
  /// synthetic "General" group rather than failing to render.
  final String? subjectId;
  final String? subjectName;

  factory ProfessorSectionModel.fromJson(Map<String, dynamic> json) {
    return ProfessorSectionModel(
      id: json['id'] as String,
      name: json['name'] as String,
      studentCount: json['student_count'] as int? ?? 0,
      subjectId: json['subject_id'] as String?,
      subjectName: json['subject_name'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'student_count': studentCount,
      'subject_id': subjectId,
      'subject_name': subjectName,
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

  /// 24-hour "HH:MM".
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
  });

  final String id;
  final String studentName;

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
            todayForegroundColor:
                WidgetStatePropertyAll(ProfessorColors.azureBlue),
            todayBorder:
                BorderSide(color: ProfessorColors.azureBlue, width: 1),
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
              foregroundColor: ProfessorColors.azureBlue,
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

enum ProfessorDashboardTab { schedule, attendance, conductReport, admissionSlip }

/// "View all notifications"/"View all emails" swap the main content area
/// exactly like a normal sub-nav tab does — header and sub-nav bar stay put
/// — rather than opening a new page/route. Not one of [ProfessorDashboardTab]'s
/// own values since it isn't a real, always-visible tab; tapping any real
/// tab clears this back to null.
enum _MailboxView { notifications, email }

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
    this.initialConductStudents,
    this.initialOffenseSummary,
    this.initialViolationOptions,
    this.onConductStudentSelected,
    this.onSubmitConductReport,
    this.initialNotifications,
    this.onMarkNotificationsRead,
    this.onSubmitAttendance,
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

  /// Supplies live-data initial state for the Conduct Report tab. Each falls
  /// back to [ConductMockData] when omitted.
  final List<ConductStudentModel>? initialConductStudents;
  final ConductOffenseSummaryModel? initialOffenseSummary;
  final List<ConductViolationOption>? initialViolationOptions;

  /// Called when a different student is picked from the Student List.
  final Future<void> Function(ConductStudentModel student)?
      onConductStudentSelected;

  /// Called when the professor submits a conduct report from the Report
  /// panel. When omitted, Submit only clears the local draft (demo
  /// behavior) — matches how [onResolveCase] works in the Discipline
  /// Officer module.
  final Future<void> Function(ConductReportSubmission submission)?
      onSubmitConductReport;

  /// Notifications targeted at this dashboard from the centralized
  /// notification system (Admin's Notifications page). Falls back to an
  /// empty bell when omitted (demo behavior).
  final List<NotificationItemModel>? initialNotifications;

  /// Marks every currently-unread notification read — invoked by the bell's
  /// "View all notifications" action.
  final Future<void> Function()? onMarkNotificationsRead;

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

  /// The Section List sidebar's active attendance context — the Attendance
  /// tab's matrix always reflects whichever section is active here, and
  /// [_SubjectSectionListCard] highlights it under its parent subject.
  /// [activeSubject] is kept in sync with [activeSection] (see
  /// [_selectActiveSection]) rather than tracked independently — a section
  /// can only ever belong to one subject group at a time.
  ProfessorSectionModel? activeSection;
  ProfessorSubjectModel? activeSubject;
  ProfessorDashboardTab activeTab = ProfessorDashboardTab.schedule;

  /// Non-null while "View all notifications"/"View all emails" is showing
  /// in place of the normal tab content. See [_MailboxView].
  _MailboxView? _mailboxView;

  final _searchController = TextEditingController();
  String _searchQuery = '';

  late List<ConductStudentModel> conductStudents;
  late ConductOffenseSummaryModel offenseSummary;
  late List<ConductViolationOption> violationOptions;

  ConductStudentModel? selectedConductStudent;
  ConductViolationOption? selectedViolation;
  DateTime reportDateTime = DateTime.now();

  final _conductSearchController = TextEditingController();
  final _commentsController = TextEditingController();
  String _conductSearchQuery = '';
  String? _conductSectionFilter;

  late List<AdmissionSlipModel> admissionSlips;
  AdmissionSlipModel? selectedAdmissionSlip;
  final _admissionSlipSearchController = TextEditingController();
  String _admissionSlipSearchQuery = '';
  String? _admissionSlipSectionFilter;

  final _themeMode = ValueNotifier(ThemeMode.light);

  late List<NotificationItemModel> _notifications;

  @override
  void initState() {
    super.initState();
    _seedFromWidget();
    admissionSlips = AdmissionSlipMockData.getSlips();
    if (admissionSlips.isNotEmpty) selectedAdmissionSlip = admissionSlips.first;
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

    conductStudents =
        widget.initialConductStudents ?? ConductMockData.getStudents();
    offenseSummary =
        widget.initialOffenseSummary ?? ConductMockData.getOffenseSummary();
    violationOptions =
        widget.initialViolationOptions ?? ConductMockData.getViolationOptions();
    selectedConductStudent =
        conductStudents.isNotEmpty ? conductStudents.first : null;

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
    }

    final freshCells = widget.initialAttendanceCells;
    if (freshCells != null &&
        !identical(freshCells, oldWidget.initialAttendanceCells)) {
      setState(() => attendanceCells = freshCells);
    }

    final freshConductStudents = widget.initialConductStudents;
    if (freshConductStudents != null &&
        !identical(freshConductStudents, oldWidget.initialConductStudents)) {
      setState(() => conductStudents = freshConductStudents);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _conductSearchController.dispose();
    _admissionSlipSearchController.dispose();
    _commentsController.dispose();
    _themeMode.dispose();
    super.dispose();
  }

  /// Groups [sections] under their parent subject, in first-seen order —
  /// the Section List sidebar's accordion structure. Every section whose
  /// [ProfessorSectionModel.subjectName] is null (always true today, since
  /// the live Supabase query doesn't join subject data yet — see
  /// [ProfessorSectionModel.subjectId]) falls into one synthetic "General"
  /// group instead of being dropped, so the accordion still renders
  /// sensibly against real data.
  List<ProfessorSubjectModel> get _subjects {
    final sectionsBySubjectId = <String, List<ProfessorSectionModel>>{};
    final nameBySubjectId = <String, String>{};
    for (final section in sections) {
      final id = section.subjectId ?? section.subjectName ?? 'general';
      final name = section.subjectName ?? 'General';
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
      if (subject.sections.any((s) => s.id == section.id)) return subject;
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
    setState(() {
      activeSubject = subject;
      activeSection = section;
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

  /// This week's columns (Monday through Saturday), in date order — only
  /// dates a session was actually recorded/added for, not every weekday.
  /// Sunday is intentionally excluded from the cycle (see
  /// [formatWeekRangeLabel]).
  List<DateTime> get _datesInWeek {
    final weekEnd = _weekStart.add(const Duration(days: 5));
    return _allSessionDates
        .where((d) => !d.isBefore(_weekStart) && !d.isAfter(weekEnd))
        .toList();
  }

  void _changeWeek(int deltaWeeks) {
    setState(() => _weekStart = _weekStart.add(Duration(days: 7 * deltaWeeks)));
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
    });
  }

  void _enterEditMode() {
    setState(() {
      _editMode = true;
      _cellsBeforeEdit = List.of(attendanceCells);
    });
  }

  void _discardChanges() {
    setState(() {
      attendanceCells = _cellsBeforeEdit ?? attendanceCells;
      _cellsBeforeEdit = null;
      _editMode = false;
    });
  }

  /// Persists every cell that changed since [_enterEditMode], grouped into
  /// one [ProfessorDashboardPage.onSubmitAttendance] call per date (so a
  /// multi-day edit session doesn't need one call per cell).
  Future<void> _saveChanges() async {
    final section = activeSection;
    final before = _cellsBeforeEdit;
    setState(() {
      _editMode = false;
      _cellsBeforeEdit = null;
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

  /// Only the sections actually present in [conductStudents] — an empty
  /// bucket in the dropdown would just be a dead end.
  List<String> get _availableConductSections {
    final sections = {for (final s in conductStudents) s.section}.toList();
    sections.sort();
    return sections;
  }

  List<ConductStudentModel> get _filteredConductStudents {
    final query = _conductSearchQuery.trim().toLowerCase();
    return conductStudents.where((s) {
      final matchesQuery =
          query.isEmpty || s.name.toLowerCase().contains(query);
      final matchesSection =
          _conductSectionFilter == null || s.section == _conductSectionFilter;
      return matchesQuery && matchesSection;
    }).toList();
  }

  Future<void> _selectConductStudent(ConductStudentModel student) async {
    setState(() => selectedConductStudent = student);
    await widget.onConductStudentSelected?.call(student);
  }

  void _resetConductDraft() {
    setState(() {
      selectedViolation = null;
      _commentsController.clear();
    });
  }

  Future<void> _submitConductReport() async {
    final student = selectedConductStudent;
    final violation = selectedViolation;
    if (student == null || violation == null) return;

    await widget.onSubmitConductReport?.call(
      ConductReportSubmission(
        studentId: student.id,
        violationOptionId: violation.id,
        comments: _commentsController.text.trim(),
      ),
    );
    if (!mounted) return;
    _resetConductDraft();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Conduct report submitted for ${student.name}.')),
    );
  }

  /// Only the sections actually present in [admissionSlips] — an empty
  /// bucket in the dropdown would just be a dead end.
  List<String> get _availableAdmissionSlipSections {
    final sections = {for (final s in admissionSlips) s.section}.toList();
    sections.sort();
    return sections;
  }

  List<AdmissionSlipModel> get _filteredAdmissionSlips {
    final query = _admissionSlipSearchQuery.trim().toLowerCase();
    return admissionSlips.where((s) {
      final matchesQuery =
          query.isEmpty || s.studentName.toLowerCase().contains(query);
      final matchesSection = _admissionSlipSectionFilter == null ||
          s.section == _admissionSlipSectionFilter;
      return matchesQuery && matchesSection;
    }).toList();
  }

  void _selectAdmissionSlip(AdmissionSlipModel slip) {
    setState(() => selectedAdmissionSlip = slip);
  }

  void _decideAdmissionSlip(AdmissionSlipStatus status) {
    final slip = selectedAdmissionSlip;
    if (slip == null) return;
    final updated = slip.copyWith(status: status);
    setState(() {
      admissionSlips = [
        for (final s in admissionSlips) s.id == slip.id ? updated : s,
      ];
      selectedAdmissionSlip = updated;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${status == AdmissionSlipStatus.approved ? 'Approved' : 'Declined'} '
          "${slip.studentName}'s admission slip.",
        ),
      ),
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

  void _showEmailMenu() {
    showHeaderPopover(
      context: context,
      cardWidth: 400,
      centered: context.isMobileWidth,
      contentBuilder: (popoverContext, setPopoverState) {
        return EmailPopover(
          emails: const [], // no email backend yet — see EmailPopover doc comment
          isDarkMode: _themeMode.value == ThemeMode.dark,
          onViewAll: () {
            Navigator.of(popoverContext).pop();
            setState(() => _mailboxView = _MailboxView.email);
          },
          onMarkAllRead: () =>
              Navigator.of(popoverContext).pop(), // nothing to mark yet
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
      ),
      child: const ProfileScreen(),
    );
  }

  /// Clicking the header logo acts as a "home" link — back to this
  /// dashboard's own default tab, dismissing "View all notifications/email"
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
          ),
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
            subtitle: 'Mission Control',
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
                  icon: Icons.mail_outline_rounded,
                  tooltip: 'Email',
                  onTap: _showEmailMenu,
                ),
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

          final pageContent = DashboardPageWrapper(
            // Matches student_portal_module's StudentPortalSpacing.pageHorizontal:
            // 16px on mobile (not flush with the screen edge), 24px on desktop.
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 16 : 24,
              vertical: 16,
            ),
            child: Builder(
              builder: (context) {
                final subNavBar = _SubNavBar(
                  activeTab: activeTab,
                  onTabSelected: (tab) => setState(() {
                    activeTab = tab;
                    _mailboxView = null;
                  }),
                );

                // Every card sizes to its own content instead of being
                // squeezed into a fixed Expanded share of the viewport —
                // that's what caused the overflow. The whole page —
                // including the header, see body below — scrolls instead,
                // so nothing has to shrink past its natural size.
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    subNavBar,
                    const SizedBox(height: 16),
                    _buildBody(isMobile: isMobile),
                  ],
                );
              },
            ),
          );

          return Scaffold(
            backgroundColor: ProfessorColors.background(context),
            bottomNavigationBar: isMobile
                ? AppBottomNavBar(
                    onEmailTap: _showEmailMenu,
                    onNotificationTap: _showNotificationsMenu,
                    onProfileTap: _openProfile,
                    notificationBadgeCount:
                        _notifications.where((n) => !n.isRead).length,
                    isDarkMode: _themeMode.value == ThemeMode.dark,
                  )
                : null,
            // The header stays fixed at the top; only the tab content below
            // it scrolls, so a short viewport never clips tab content with
            // no way to reach the rest of it.
            body: Column(
              children: [
                header,
                Expanded(child: SingleChildScrollView(child: pageContent)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildBody({required bool isMobile}) {
    switch (_mailboxView) {
      case _MailboxView.notifications:
        return NotificationsListView(
          notifications: _notifications,
          isDarkMode: _themeMode.value == ThemeMode.dark,
        );
      case _MailboxView.email:
        return EmailListView(isDarkMode: _themeMode.value == ThemeMode.dark);
      case null:
        if (widget.isLoading) {
          return DashboardSkeletonScreen(
            useScaffold: false,
            wrapInPageFrame: false,
            backgroundColor: ProfessorColors.background(context),
            cardColor: ProfessorColors.card(context),
            cardBorderColor: ProfessorColors.cardBorder(context),
            placeholderColor: ProfessorColors.gray,
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
      ProfessorDashboardTab.admissionSlip =>
        _buildAdmissionSlipContent(isMobile: isMobile),
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
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: ProfessorColors.rowText(context),
              ),
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
                style: GoogleFonts.inter(
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
      activeSectionId: activeSection?.id,
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
        return ConstrainedBox(
          constraints:
              BoxConstraints(maxHeight: context.masterDetailRowMaxHeight()),
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
    final studentListCard = ConductStudentListCard(
      students: _filteredConductStudents,
      totalStudentCount: conductStudents.length,
      selectedStudentId: selectedConductStudent?.id,
      searchController: _conductSearchController,
      onSearchChanged: (value) => setState(() => _conductSearchQuery = value),
      onSelect: _selectConductStudent,
      availableSections: _availableConductSections,
      sectionFilter: _conductSectionFilter,
      onSectionFilterChanged: (value) =>
          setState(() => _conductSectionFilter = value),
    );

    final reportCard = ConductReportCard(
      selectedStudent: selectedConductStudent,
      violationOptions: violationOptions,
      selectedViolation: selectedViolation,
      submittedByName: widget.professorName,
      submittedByRole: 'Faculty Member',
      reportDateTime: reportDateTime,
      commentsController: _commentsController,
      onViolationSelected: (option) =>
          setState(() => selectedViolation = option),
      onCancel: _resetConductDraft,
      onSubmit: _submitConductReport,
    );

    if (isMobile) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          studentListCard,
          const SizedBox(height: 16),
          ConductOffenseStatsRow(summary: offenseSummary),
          const SizedBox(height: 18),
          reportCard,
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final stackColumns = constraints.maxWidth < 900;

        // reportCard becomes the flexible child — filling the rest of this
        // panel's height — only when an ancestor (the desktop
        // master-detail Row below) actually gives this panel a bounded
        // height to fill.
        final reportPanel = LayoutBuilder(
          builder: (context, constraints) {
            final bounded = constraints.hasBoundedHeight;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: bounded ? MainAxisSize.max : MainAxisSize.min,
              children: [
                ConductOffenseStatsRow(summary: offenseSummary),
                const SizedBox(height: 18),
                bounded ? Expanded(child: reportCard) : reportCard,
              ],
            );
          },
        );

        if (stackColumns) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              studentListCard,
              const SizedBox(height: 16),
              reportPanel,
            ],
          );
        }

        // Master-detail: the student-list "sidebar" is height-locked to
        // match the report panel (CrossAxisAlignment.stretch), capped so
        // the pair never grows past ~one viewport — the student list's own
        // list, and the report card, scroll internally within that fixed
        // height instead.
        return ConstrainedBox(
          constraints:
              BoxConstraints(maxHeight: context.masterDetailRowMaxHeight()),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 320, child: studentListCard),
              const SizedBox(width: 18),
              Expanded(child: reportPanel),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAdmissionSlipContent({required bool isMobile}) {
    final slipListCard = AdmissionSlipListCard(
      slips: _filteredAdmissionSlips,
      totalSlipCount: admissionSlips.length,
      selectedSlipId: selectedAdmissionSlip?.id,
      searchController: _admissionSlipSearchController,
      onSearchChanged: (value) =>
          setState(() => _admissionSlipSearchQuery = value),
      onSelect: _selectAdmissionSlip,
      availableSections: _availableAdmissionSlipSections,
      sectionFilter: _admissionSlipSectionFilter,
      onSectionFilterChanged: (value) =>
          setState(() => _admissionSlipSectionFilter = value),
    );

    final canDecide = selectedAdmissionSlip != null;
    final detailCard = AdmissionSlipDetailCard(
      selectedSlip: selectedAdmissionSlip,
      onApprove: canDecide
          ? () => _decideAdmissionSlip(AdmissionSlipStatus.approved)
          : null,
      onDecline: canDecide
          ? () => _decideAdmissionSlip(AdmissionSlipStatus.declined)
          : null,
    );

    if (isMobile) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          slipListCard,
          const SizedBox(height: 18),
          detailCard,
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final stackColumns = constraints.maxWidth < 900;

        if (stackColumns) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              slipListCard,
              const SizedBox(height: 18),
              detailCard,
            ],
          );
        }

        // Master-detail: the slip-list "sidebar" is height-locked to match
        // the detail panel (CrossAxisAlignment.stretch), capped so the pair
        // never grows past ~one viewport — same layout as the Conduct
        // Report tab's student list + report card.
        return ConstrainedBox(
          constraints:
              BoxConstraints(maxHeight: context.masterDetailRowMaxHeight()),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 320, child: slipListCard),
              const SizedBox(width: 18),
              Expanded(child: detailCard),
            ],
          ),
        );
      },
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
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: BentoCard(
        backgroundColor: ProfessorColors.card(context),
        borderColor: ProfessorColors.cardBorder(context),
        clipBehavior: Clip.antiAlias,
        // Horizontally scrollable — at mobile widths the tab labels plus
        // spacing don't fit the viewport, and this bar has no business
        // shrinking or wrapping them (matches Figma's own `overflow-x-auto`
        // on this bar). The SizedBox's own fixed height:48 still bounds the
        // Row's cross axis, so nothing overflows vertically either.
        // ScrollConfiguration: Flutter's default ScrollBehavior excludes
        // mouse from dragDevices, which would otherwise leave the
        // overflowing tabs unreachable for a desktop mouse user
        // (touch/trackpad drag still worked; a plain click-drag or scroll
        // didn't).
        child: ScrollConfiguration(
          behavior: mouseDraggableScrollBehavior,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 40),
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
                  label: 'Conduct Report',
                  icon: Icons.report_outlined,
                  isActive: activeTab == ProfessorDashboardTab.conductReport,
                  onTap: () =>
                      onTabSelected(ProfessorDashboardTab.conductReport),
                ),
                const SizedBox(width: 45),
                _SubNavItem(
                  label: 'Admission Slip',
                  icon: Icons.receipt_long_outlined,
                  isActive: activeTab == ProfessorDashboardTab.admissionSlip,
                  onTap: () =>
                      onTabSelected(ProfessorDashboardTab.admissionSlip),
                ),
              ],
            ),
          ),
        ),
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
        color: ProfessorColors.azureBlue,
        child: _tab(context),
      );

  Widget _tab(BuildContext context) {
    final color = isActive
        ? ProfessorColors.azureBlue
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
              color: isActive ? ProfessorColors.azureBlue : Colors.transparent,
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
    final titleStyle = GoogleFonts.inter(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: ProfessorColors.rowText(context),
    );
    final subtitleStyle = GoogleFonts.inter(
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
                  '${entry.sectionName} · ${entry.day} ${entry.startTime}-${entry.endTime} · ${entry.room}',
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
                  child: Text('${entry.startTime}-${entry.endTime}', style: subtitleStyle),
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
    required this.onToggle,
    required this.onSelectSection,
  });

  final ProfessorSubjectModel subject;
  final bool expanded;
  final String? activeSectionId;
  final VoidCallback onToggle;
  final ValueChanged<ProfessorSectionModel> onSelectSection;

  @override
  Widget build(BuildContext context) {
    final containsActiveSection =
        subject.sections.any((s) => s.id == activeSectionId);

    return BentoCard(
      backgroundColor: ProfessorColors.background(context),
      borderColor: containsActiveSection
          ? ProfessorColors.azureBlue
          : ProfessorColors.cardBorder(context),
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
                      section: section,
                      isSelected: section.id == activeSectionId,
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
          color: ProfessorColors.azureBlue,
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
                    ? ProfessorColors.azureBlue
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
      height: 32,
      child: TextField(
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
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
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
  });

  final List<StudentAttendanceRecordModel> records;

  /// This week's session dates, in order — the matrix's date columns.
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
        final Widget body = records.isEmpty
            ? Center(
                child: Text(
                  'No attendance records for this section yet',
                  style: GoogleFonts.poppins(
                    fontSize: context.isMobileWidth ? 11 : 13,
                    fontWeight: FontWeight.w500,
                    color: ProfessorColors.mutedText(context),
                  ),
                ),
              )
            : widget.dates.isEmpty
                ? _EmptyWeekState(onAddAttendance: widget.onAddAttendance)
                : _AttendanceMatrix(
                    records: records,
                    dates: widget.dates,
                    editMode: widget.editMode,
                    statusFor: widget.statusFor,
                    onCellTap: widget.onCellTap,
                    onMarkAllForDate: widget.onMarkAllForDate,
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
              bounded ? Expanded(child: body) : body,
              if (records.isNotEmpty && widget.dates.isNotEmpty)
                const SizedBox(height: 16),
            ],
          ),
        );
      },
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
      style: GoogleFonts.poppins(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: ProfessorColors.rowText(context),
      ),
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
                  editControls,
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [weekNav, addButton],
              ),
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: title),
            weekNav,
            const SizedBox(width: 14),
            addButton,
            const SizedBox(width: 10),
            editControls,
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
    final accent = color ?? ProfessorColors.azureBlue;
    final foreground = filled ? Colors.white : accent;
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
  });

  final List<StudentAttendanceRecordModel> records;
  final List<DateTime> dates;
  final bool editMode;
  final AttendanceCellModel? Function(String studentRecordId, DateTime date)
      statusFor;
  final void Function(String studentRecordId, DateTime date) onCellTap;
  final void Function(DateTime date, AttendanceStatus status) onMarkAllForDate;

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

  static const _nameColumnWidth = 180.0;
  static const _dateColumnWidth = 112.0;
  static const _headerHeight = 44.0;
  static const _rowHeight = 56.0;

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
    final headerStyle = GoogleFonts.poppins(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: Colors.white,
    );

    final nameHeaderCell = Container(
      width: _nameColumnWidth,
      height: _headerHeight,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: ProfessorColors.navyBlue,
      child: Text('Student', style: headerStyle),
    );

    final nameBodyColumn = Column(
      children: [
        for (final record in widget.records)
          Container(
            height: _rowHeight,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              border: Border(
                  bottom:
                      BorderSide(color: ProfessorColors.cardBorder(context))),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  record.studentName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: ProfessorColors.rowText(context),
                  ),
                ),
                Text(
                  record.studentId,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w400,
                    color: ProfessorColors.mutedText(context),
                  ),
                ),
              ],
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
        final dateAreaWidth = outerConstraints.maxWidth - _nameColumnWidth;
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
                ),
                _headerHeight,
              ),
          ],
        );

        final bodyDatesColumn = Column(
          children: [
            for (final record in widget.records)
              Row(
                children: [
                  for (final date in widget.dates)
                    columnCell(
                      _AttendanceCellView(
                        status:
                            widget.statusFor(record.id, date)?.status ??
                                AttendanceStatus.none,
                        editMode: widget.editMode,
                        onTap: () => widget.onCellTap(record.id, date),
                      ),
                      _rowHeight,
                    ),
                ],
              ),
          ],
        );

        final headerRow = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
        );

        final scrollableBody = Scrollbar(
          controller: _verticalController,
          child: SingleChildScrollView(
            controller: _verticalController,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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

class _DateColumnHeader extends StatelessWidget {
  const _DateColumnHeader({
    required this.date,
    required this.editMode,
    required this.onMarkAll,
  });

  final DateTime date;
  final bool editMode;
  final ValueChanged<AttendanceStatus> onMarkAll;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: ProfessorColors.navyBlue,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: Text(
              formatDayMonthDate(date),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
          if (editMode)
            PopupMenuButton<AttendanceStatus>(
              tooltip: 'Bulk actions for ${formatDayMonthDate(date)}',
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.more_vert_rounded,
                  size: 16, color: Colors.white70),
              onSelected: onMarkAll,
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: AttendanceStatus.present,
                  child: Text('Mark all Present'),
                ),
                PopupMenuItem(
                  value: AttendanceStatus.absent,
                  child: Text('Mark all Absent'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _AttendanceCellView extends StatelessWidget {
  const _AttendanceCellView({
    required this.status,
    required this.editMode,
    required this.onTap,
  });

  final AttendanceStatus status;
  final bool editMode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: ProfessorColors.cardBorder(context)),
          left: BorderSide(color: ProfessorColors.cardBorder(context)),
        ),
      ),
      child: Center(
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
      ),
    );
  }
}
