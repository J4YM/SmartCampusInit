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

import '../../data/conduct_mock_data.dart';
import '../../data/professor_mock_data.dart';
import '../../theme/professor_colors.dart';
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
  });

  final String id;
  final String name;
  final int studentCount;

  factory ProfessorSectionModel.fromJson(Map<String, dynamic> json) {
    return ProfessorSectionModel(
      id: json['id'] as String,
      name: json['name'] as String,
      studentCount: json['student_count'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'name': name, 'student_count': studentCount};
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
    this.status = AttendanceStatus.none,
  });

  final String id;
  final String studentName;

  /// The student's display ID (e.g. institution ID number) — distinct from
  /// [id], the internal row identifier used as the key in
  /// [ProfessorDashboardPage.onSubmitAttendance]'s status map.
  final String studentId;
  final int presentCount;
  final int totalSessions;
  final int absentCount;

  /// This student's status for the in-progress session — see
  /// [AttendanceStatus].
  final AttendanceStatus status;

  StudentAttendanceRecordModel copyWith({AttendanceStatus? status}) {
    return StudentAttendanceRecordModel(
      id: id,
      studentName: studentName,
      studentId: studentId,
      presentCount: presentCount,
      totalSessions: totalSessions,
      absentCount: absentCount,
      status: status ?? this.status,
    );
  }

  factory StudentAttendanceRecordModel.fromJson(Map<String, dynamic> json) {
    return StudentAttendanceRecordModel(
      id: json['id'] as String,
      studentName: json['student_name'] as String,
      studentId: json['student_id'] as String? ?? '',
      presentCount: json['present_count'] as int? ?? 0,
      totalSessions: json['total_sessions'] as int? ?? 0,
      absentCount: json['absent_count'] as int? ?? 0,
      status: AttendanceStatus.fromValue(json['status'] as String?),
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
      'status': status.value,
    };
  }
}

// ---------------------------------------------------------------------------
// Tab navigation state
// ---------------------------------------------------------------------------

enum ProfessorDashboardTab { attendance, conductReport, admissionSlip }

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
    this.initialAttendanceSummary,
    this.initialStudentAttendance,
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
  final AttendanceSummaryModel? initialAttendanceSummary;
  final List<StudentAttendanceRecordModel>? initialStudentAttendance;

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
  /// [selectedSection] — called once per student, each time their Status
  /// icon is clicked in the Student List table (see [_handleStatusCycle]),
  /// with a single-entry map for just that student. When omitted, the
  /// action is unavailable (demo behavior — there's nowhere to persist it).
  final Future<void> Function(
    ProfessorSectionModel selectedSection,
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

  ProfessorSectionModel? selectedSection;
  ProfessorDashboardTab activeTab = ProfessorDashboardTab.attendance;

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

  final _themeMode = ValueNotifier(ThemeMode.light);

  late List<NotificationItemModel> _notifications;

  @override
  void initState() {
    super.initState();
    sections = widget.initialSections ?? ProfessorMockData.getSections();
    attendanceSummary = widget.initialAttendanceSummary ??
        ProfessorMockData.getAttendanceSummary();
    studentAttendance = widget.initialStudentAttendance ??
        ProfessorMockData.getStudentAttendance();
    if (sections.isNotEmpty) selectedSection = sections.first;

    conductStudents =
        widget.initialConductStudents ?? ConductMockData.getStudents();
    offenseSummary =
        widget.initialOffenseSummary ?? ConductMockData.getOffenseSummary();
    violationOptions =
        widget.initialViolationOptions ?? ConductMockData.getViolationOptions();
    if (conductStudents.isNotEmpty)
      selectedConductStudent = conductStudents.first;
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
    _commentsController.dispose();
    _themeMode.dispose();
    super.dispose();
  }

  List<ProfessorSectionModel> get _filteredSections {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return sections;
    return sections.where((s) => s.name.toLowerCase().contains(query)).toList();
  }

  Future<void> _selectSection(ProfessorSectionModel section) async {
    setState(() => selectedSection = section);
    await widget.onSectionSelected?.call(section);
  }

  /// Cycles [record]'s status to the next one (unmarked → present → absent
  /// → late → excused → present → …) when its Status icon is tapped in the Student
  /// List table, and persists just that one change via
  /// [ProfessorDashboardPage.onSubmitAttendance] — this replaces the old
  /// "Take Attendance" dialog's bulk picker with an inline per-student
  /// toggle.
  Future<void> _handleStatusCycle(StudentAttendanceRecordModel record) async {
    final section = selectedSection;
    final nextStatus = record.status.next;

    setState(() {
      studentAttendance = [
        for (final r in studentAttendance)
          if (r.id == record.id) r.copyWith(status: nextStatus) else r,
      ];
    });

    if (section == null) return;

    try {
      await widget.onSubmitAttendance
          ?.call(section, {record.id: nextStatus.value});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save attendance: $e')),
      );
    }
  }

  List<ConductStudentModel> get _filteredConductStudents {
    final query = _conductSearchQuery.trim().toLowerCase();
    if (query.isEmpty) return conductStudents;
    return conductStudents
        .where((s) => s.name.toLowerCase().contains(query))
        .toList();
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
                    onTap: widget.onReturnToHub!,
                  ),
                  const SizedBox(width: 12),
                ],
                const SchoolLogo(),
              ],
            ),
            actions: [
              if (!isMobile) ...[
                HeaderIconButton(
                  icon: Icons.mail_outline_rounded,
                  onTap: _showEmailMenu,
                ),
                HeaderIconButton(
                  icon: Icons.notifications_none_rounded,
                  badgeCount: _notifications.where((n) => !n.isRead).length,
                  onTap: _showNotificationsMenu,
                ),
                if (widget.onReportTechnicalIssue != null)
                  HeaderIconButton(
                    icon: Icons.report_problem_outlined,
                    iconWidget: const ReportIssueIcon(size: 20),
                    onTap: () => showReportTechnicalIssueDialog(
                      context,
                      isDarkMode: _themeMode.value == ThemeMode.dark,
                      onSubmit: widget.onReportTechnicalIssue!,
                    ),
                  ),
                const SizedBox(width: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InkWell(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => _themedProfileScreen()),
                      ),
                      child: Text(
                        widget.professorName,
                        style: GoogleFonts.poppins(
                          fontSize: context.isMobileWidth ? 14 : 16,
                          fontWeight: FontWeight.w600,
                          color: ProfessorColors.gray,
                        ),
                      ),
                    ),
                    const SizedBox(width: 15),
                    ProfileAvatarButton(
                      onTap: _openProfile,
                      foregroundColor: ProfessorColors.navyBlue,
                    ),
                    if (widget.onSignOut != null) ...[
                      const SizedBox(width: 10),
                      HeaderIconButton(
                        icon: Icons.logout_rounded,
                        onTap: widget.onSignOut!,
                      ),
                    ],
                  ],
                ),
              ] else if (widget.onSignOut != null)
                HeaderIconButton(
                  icon: Icons.logout_rounded,
                  onTap: widget.onSignOut!,
                ),
            ],
          );

          final pageContent = DashboardPageWrapper(
            // On mobile the cards should use nearly the full screen width
            // instead of losing 48px total to the desktop's 24px side
            // margins.
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 5 : 24,
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
            // The whole body is one scrollable column so a short viewport
            // never clips tab content with no way to reach the rest of it.
            body: SingleChildScrollView(
              child: Column(children: [header, pageContent]),
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
        return _buildTabContent(activeTab, isMobile: isMobile);
    }
  }

  Widget _buildTabContent(ProfessorDashboardTab tab, {required bool isMobile}) {
    return switch (tab) {
      ProfessorDashboardTab.attendance =>
        _buildAttendanceContent(isMobile: isMobile),
      ProfessorDashboardTab.conductReport =>
        _buildConductReportContent(isMobile: isMobile),
      ProfessorDashboardTab.admissionSlip => _emptySection(
          icon: Icons.assignment_outlined,
          title: 'Admission Slip',
          subtitle: 'Admission slip records are not available yet',
        ),
    };
  }

  Widget _emptySection({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return _EmptySectionView(icon: icon, title: title, subtitle: subtitle);
  }

  Widget _buildAttendanceContent({required bool isMobile}) {
    final sectionListCard = _SectionListCard(
      sections: _filteredSections,
      totalSectionCount: sections.length,
      selectedSectionId: selectedSection?.id,
      searchController: _searchController,
      onSearchChanged: (value) => setState(() => _searchQuery = value),
      onSelect: _selectSection,
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
            onStatusTap: _handleStatusCycle,
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
              onStatusTap: _handleStatusCycle,
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
    return Container(
      width: double.infinity,
      height: 48,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: ProfessorColors.card(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: ProfessorColors.cardBorder(context)),
      ),
      // Horizontally scrollable — at mobile widths the tab labels plus
      // spacing don't fit the viewport, and this bar has no business
      // shrinking or wrapping them (matches Figma's own `overflow-x-auto`
      // on this bar). The Container's own fixed height:48 still bounds the
      // Row's cross axis, so nothing overflows vertically either.
      // ScrollConfiguration: Flutter's default ScrollBehavior excludes
      // mouse from dragDevices, which would otherwise leave the overflowing
      // tabs unreachable for a desktop mouse user (touch/trackpad drag
      // still worked; a plain click-drag or scroll didn't).
      child: ScrollConfiguration(
        behavior: mouseDraggableScrollBehavior,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
                onTap: () => onTabSelected(ProfessorDashboardTab.conductReport),
              ),
              const SizedBox(width: 45),
              _SubNavItem(
                label: 'Admission Slip',
                icon: Icons.receipt_long_outlined,
                isActive: activeTab == ProfessorDashboardTab.admissionSlip,
                onTap: () => onTabSelected(ProfessorDashboardTab.admissionSlip),
              ),
            ],
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
  Widget build(BuildContext context) {
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
// Empty placeholder section (Conduct Report / Admission Slip)
// ---------------------------------------------------------------------------

class _EmptySectionView extends StatelessWidget {
  const _EmptySectionView({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: ProfessorColors.card(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: ProfessorColors.cardBorder(context)),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: ProfessorColors.background(context),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon,
                  size: 32, color: ProfessorColors.placeholderText(context)),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: GoogleFonts.poppins(
                fontSize: context.isMobileWidth ? 16 : 18,
                fontWeight: FontWeight.w600,
                color: ProfessorColors.rowText(context),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: GoogleFonts.poppins(
                fontSize: context.isMobileWidth ? 11 : 13,
                fontWeight: FontWeight.w400,
                color: ProfessorColors.mutedText(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Left column — Section List
// ---------------------------------------------------------------------------

class _SectionListCard extends StatefulWidget {
  const _SectionListCard({
    required this.sections,
    required this.totalSectionCount,
    required this.selectedSectionId,
    required this.searchController,
    required this.onSearchChanged,
    required this.onSelect,
  });

  final List<ProfessorSectionModel> sections;
  final int totalSectionCount;
  final String? selectedSectionId;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<ProfessorSectionModel> onSelect;

  @override
  State<_SectionListCard> createState() => _SectionListCardState();
}

class _SectionListCardState extends State<_SectionListCard> {
  int get _pageSize => context.isMobileWidth ? 10 : 20;

  int _currentPage = 1;

  @override
  Widget build(BuildContext context) {
    final sections = widget.sections;
    final totalPages =
        sections.isEmpty ? 1 : (sections.length / _pageSize).ceil();
    final currentPage = _currentPage.clamp(1, totalPages);
    final pageSections =
        sections.skip((currentPage - 1) * _pageSize).take(_pageSize).toList();

    // Header/search stay fixed; only the list scrolls — as a bounded,
    // real-scrolling Expanded when an ancestor gives this card a fixed
    // height to match its detail-panel sibling (the desktop master-detail
    // Row), or as a Flexible that hugs up to whatever's available when it
    // doesn't (mobile/stacked, where the page itself scrolls instead).
    return LayoutBuilder(
      builder: (context, constraints) {
        final bounded = constraints.hasBoundedHeight;
        final Widget list = sections.isEmpty
            ? const _SectionListEmptyState()
            : ListView(
                shrinkWrap: !bounded,
                padding: const EdgeInsets.fromLTRB(25, 0, 25, 10),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Sections',
                            style: GoogleFonts.poppins(
                              fontSize: context.isMobileWidth ? 11 : 13,
                              fontWeight: FontWeight.w500,
                              color: ProfessorColors.mutedText(context),
                            ),
                          ),
                        ),
                        Text(
                          'No. of Students',
                          style: GoogleFonts.poppins(
                            fontSize: context.isMobileWidth ? 11 : 13,
                            fontWeight: FontWeight.w500,
                            color: ProfessorColors.mutedText(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  for (final section in pageSections)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _SectionRow(
                        section: section,
                        isSelected: section.id == widget.selectedSectionId,
                        onTap: () => widget.onSelect(section),
                      ),
                    ),
                ],
              );

        return Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: ProfessorColors.card(context),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: ProfessorColors.cardBorder(context)),
          ),
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
                      'Section List',
                      style: GoogleFonts.poppins(
                        fontSize: context.isMobileWidth ? 16 : 18,
                        fontWeight: FontWeight.w600,
                        color: ProfessorColors.rowText(context),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Total section: ${widget.totalSectionCount}',
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
                            onChanged: (value) {
                              setState(() => _currentPage = 1);
                              widget.onSearchChanged(value);
                            })),
                    const SizedBox(width: 10),
                    _FilterButton(onTap: () {}),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              bounded ? Expanded(child: list) : Flexible(child: list),
              if (sections.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(25, 8, 25, 14),
                  child: CardPaginationFooter(
                    currentPage: currentPage,
                    totalPages: totalPages,
                    totalCount: sections.length,
                    textColor: ProfessorColors.placeholderText(context),
                    accentColor: ProfessorColors.azureBlue,
                    mutedBackground: ProfessorColors.background(context),
                    onPrevious: () =>
                        setState(() => _currentPage = currentPage - 1),
                    onNext: () =>
                        setState(() => _currentPage = currentPage + 1),
                  ),
                ),
            ],
          ),
        );
      },
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

class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: ProfessorColors.background(context),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 32,
          width: 107,
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.filter_list_rounded,
                size: 16,
                color: ProfessorColors.placeholderText(context),
              ),
              const SizedBox(width: 6),
              Text(
                'Filter',
                style: GoogleFonts.poppins(
                  fontSize: context.isMobileWidth ? 11 : 13,
                  fontWeight: FontWeight.w400,
                  color: ProfessorColors.placeholderText(context),
                ),
              ),
            ],
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
        'No sections found',
        style: GoogleFonts.poppins(
          fontSize: context.isMobileWidth ? 11 : 13,
          fontWeight: FontWeight.w500,
          color: ProfessorColors.mutedText(context),
        ),
      ),
    );
  }
}

class _SectionRow extends StatelessWidget {
  const _SectionRow({
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
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            border: Border(
                bottom: BorderSide(color: ProfessorColors.cardBorder(context))),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  section.name,
                  style: GoogleFonts.poppins(
                    fontSize: context.isMobileWidth ? 11 : 13,
                    fontWeight: FontWeight.w500,
                    color: ProfessorColors.rowText(context),
                  ),
                ),
              ),
              Text(
                '${section.studentCount}',
                style: GoogleFonts.poppins(
                  fontSize: context.isMobileWidth ? 11 : 13,
                  fontWeight: FontWeight.w500,
                  color: ProfessorColors.rowText(context),
                ),
              ),
            ],
          ),
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
    return Container(
      padding: const EdgeInsets.fromLTRB(27, 16, 20, 16),
      decoration: BoxDecoration(
        color: ProfessorColors.card(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: ProfessorColors.cardBorder(context)),
      ),
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
    required this.onStatusTap,
  });

  final List<StudentAttendanceRecordModel> records;

  /// Called with the tapped row's record when its Status icon is clicked —
  /// the caller cycles that student's status and persists the change.
  final ValueChanged<StudentAttendanceRecordModel> onStatusTap;

  @override
  State<_StudentAttendanceTableCard> createState() =>
      _StudentAttendanceTableCardState();
}

class _StudentAttendanceTableCardState
    extends State<_StudentAttendanceTableCard> {
  int get _pageSize => context.isMobileWidth ? 10 : 20;

  int _currentPage = 1;

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
    final totalPages =
        records.isEmpty ? 1 : (records.length / _pageSize).ceil();
    final currentPage = _currentPage.clamp(1, totalPages);
    final pageRecords =
        records.skip((currentPage - 1) * _pageSize).take(_pageSize).toList();
    final headerStyle = GoogleFonts.poppins(
      fontSize: context.isMobileWidth ? 10 : 12,
      fontWeight: FontWeight.w600,
      color: Colors.white,
    );

    // Header row stays fixed; only the list scrolls — as a bounded,
    // real-scrolling Expanded when an ancestor gives this card a fixed
    // height to match its sidebar sibling (the desktop master-detail Row),
    // or as a Flexible that hugs up to whatever's available when it
    // doesn't (mobile/stacked, where the page itself scrolls instead).
    return LayoutBuilder(
      builder: (context, constraints) {
        final bounded = constraints.hasBoundedHeight;
        final Widget list = records.isEmpty
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
            : ListView.builder(
                shrinkWrap: !bounded,
                itemCount: pageRecords.length,
                itemBuilder: (context, index) {
                  final record = pageRecords[index];
                  return _StudentAttendanceRow(
                    record: record,
                    onStatusTap: () => widget.onStatusTap(record),
                  );
                },
              );

        return Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: ProfessorColors.card(context),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: ProfessorColors.cardBorder(context)),
          ),
          child: Column(
            mainAxisSize: bounded ? MainAxisSize.max : MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                child: Text(
                  'Student List',
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: context.isMobileWidth ? 16 : 18,
                    fontWeight: FontWeight.w600,
                    color: ProfessorColors.rowText(context),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                color: ProfessorColors.navyBlue,
                child: Row(
                  children: [
                    Expanded(flex: 2, child: Text('Student', style: headerStyle)),
                    Expanded(
                        flex: 2, child: Text('Student ID', style: headerStyle)),
                    Expanded(
                      child: Text('No. of Present', style: headerStyle),
                    ),
                    Expanded(
                      child: Text('No. of Absent', style: headerStyle),
                    ),
                    SizedBox(
                      width: 60,
                      child: Text(
                        'Status',
                        textAlign: TextAlign.center,
                        style: headerStyle,
                      ),
                    ),
                  ],
                ),
              ),
              bounded ? Expanded(child: list) : Flexible(child: list),
              if (records.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                  child: _StudentAttendanceFooter(
                    shownCount: pageRecords.length,
                    totalCount: records.length,
                    canGoPrevious: currentPage > 1,
                    canGoNext: currentPage < totalPages,
                    onPrevious: () =>
                        setState(() => _currentPage = currentPage - 1),
                    onNext: () =>
                        setState(() => _currentPage = currentPage + 1),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _StudentAttendanceRow extends StatelessWidget {
  const _StudentAttendanceRow({
    required this.record,
    required this.onStatusTap,
  });

  final StudentAttendanceRecordModel record;
  final VoidCallback onStatusTap;

  @override
  Widget build(BuildContext context) {
    final style = GoogleFonts.poppins(
      fontSize: context.isMobileWidth ? 11 : 13,
      fontWeight: FontWeight.w500,
      color: ProfessorColors.rowText(context),
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        border: Border(
            bottom: BorderSide(color: ProfessorColors.cardBorder(context))),
      ),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text(record.studentName, style: style)),
          Expanded(flex: 2, child: Text(record.studentId, style: style)),
          Expanded(
            child: Text(
              '${record.presentCount}/${record.totalSessions}',
              style: style,
            ),
          ),
          Expanded(
            child: Text('${record.absentCount}', style: style),
          ),
          SizedBox(
            width: 60,
            child: Center(
              child: Tooltip(
                message:
                    '${record.status.value} — tap to mark ${record.status.next.value}',
                child: InkResponse(
                  onTap: onStatusTap,
                  radius: 20,
                  child: Icon(
                    record.status.icon,
                    size: 22,
                    color: record.status.color,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StudentAttendanceFooter extends StatelessWidget {
  const _StudentAttendanceFooter({
    required this.shownCount,
    required this.totalCount,
    required this.canGoPrevious,
    required this.canGoNext,
    required this.onPrevious,
    required this.onNext,
  });

  final int shownCount;
  final int totalCount;
  final bool canGoPrevious;
  final bool canGoNext;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final label = Text(
      'Showing $shownCount of $totalCount total student grade records',
      style: GoogleFonts.poppins(
        fontSize: context.isMobileWidth ? 10 : 12,
        color: ProfessorColors.mutedText(context),
      ),
    );
    // Pill buttons, matching the Registrar Dashboard's Student List
    // pagination convention used across every dashboard's card-level
    // pagination.
    final buttons = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PaginationPillButton(
          label: 'Previous',
          background: ProfessorColors.background(context),
          foreground: ProfessorColors.azureBlue,
          onTap: canGoPrevious ? onPrevious : null,
        ),
        const SizedBox(width: 8),
        PaginationPillButton(
          label: 'Next',
          background: ProfessorColors.azureBlue,
          foreground: Colors.white,
          onTap: canGoNext ? onNext : null,
        ),
      ],
    );

    return Row(
      children: [
        Expanded(child: label),
        buttons,
      ],
    );
  }
}

