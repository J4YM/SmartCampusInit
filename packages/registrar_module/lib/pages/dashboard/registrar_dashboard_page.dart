import 'package:dashboard_layout/dashboard_layout.dart';
// Reuses the Discipline Officer module's shared header-popover components
// directly rather than duplicating them, matching the same pattern every
// other dashboard module (Professor, Guidance Counselor, …) already uses
// for this widget set.
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
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../data/registrar_mock_data.dart';
import '../../theme/registrar_colors.dart';
import 'add_student_dialog.dart';
import 'class_schedule_view.dart';
import 'grades_view.dart';
import 'rfid_management_view.dart';
import 'rfid_notification_logs_dialog.dart';
import 'student_records_view.dart';

// ---------------------------------------------------------------------------
// Data models — Supabase (`students` / `grade_records` / `class_schedules`)
// ready. fromJson()/toJson() map directly onto snake_case Postgres columns
// so rows can be streamed straight into these models once the backend is
// wired up.
// ---------------------------------------------------------------------------

/// A student's current enrollment status, shown as a colored pill in every
/// student table across the Registrar Dashboard.
enum EnrollmentStatus {
  active,
  inactive;

  String get label =>
      this == EnrollmentStatus.active ? 'Active' : 'Inactive';

  Color get badgeBackground => this == EnrollmentStatus.active
      ? const Color(0xFFE6F4EA)
      : const Color(0x33CD4855); // rgba(205,72,85,0.2)

  Color get badgeText => this == EnrollmentStatus.active
      ? RegistrarColors.successGreen
      : RegistrarColors.dangerRed;

  static EnrollmentStatus fromValue(String? value) =>
      value == 'Inactive' ? EnrollmentStatus.inactive : EnrollmentStatus.active;
}

class RegistrarStudentModel {
  const RegistrarStudentModel({
    required this.id,
    required this.name,
    required this.studentId,
    required this.program,
    required this.section,
    this.gpa,
    required this.status,
    this.hasRfid = true,
    this.isNewStudent = false,
    this.parentGuardian = '',
    this.contactNo = '',
    this.email = '',
    this.enrolledDate = '',
  });

  final String id;
  final String name;
  final String studentId;

  /// Full program name (e.g. "BS Information Technology") — [section] holds
  /// the short "BSIT - 4B" form shown in table columns.
  final String program;
  final String section;

  /// Null when no grade data exists yet for this student (Grades isn't
  /// backed by real data yet — see `class_schedule_view.dart`'s companion
  /// gap). The UI shows "—" rather than a fabricated 0.0, which would read
  /// as a real (failing) grade.
  final double? gpa;
  final EnrollmentStatus status;
  final bool hasRfid;

  /// True for a recently-enrolled student — drives the Overview tab's
  /// "New Students" card.
  final bool isNewStudent;
  final String parentGuardian;
  final String contactNo;
  final String email;
  final String enrolledDate;

  factory RegistrarStudentModel.fromJson(Map<String, dynamic> json) {
    return RegistrarStudentModel(
      id: json['id'] as String,
      name: json['name'] as String,
      studentId: json['student_id'] as String? ?? '',
      program: json['program'] as String? ?? '',
      section: json['section'] as String? ?? '',
      gpa: (json['gpa'] as num?)?.toDouble(),
      status: EnrollmentStatus.fromValue(json['status'] as String?),
      hasRfid: json['has_rfid'] as bool? ?? true,
      isNewStudent: json['is_new_student'] as bool? ?? false,
      parentGuardian: json['parent_guardian'] as String? ?? '',
      contactNo: json['contact_no'] as String? ?? '',
      email: json['email'] as String? ?? '',
      enrolledDate: json['enrolled_date'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'student_id': studentId,
      'program': program,
      'section': section,
      'gpa': gpa,
      'status': status.label,
      'has_rfid': hasRfid,
      'is_new_student': isNewStudent,
      'parent_guardian': parentGuardian,
      'contact_no': contactNo,
      'email': email,
      'enrolled_date': enrolledDate,
    };
  }

  RegistrarStudentModel copyWith({bool? hasRfid}) {
    return RegistrarStudentModel(
      id: id,
      name: name,
      studentId: studentId,
      program: program,
      section: section,
      gpa: gpa,
      status: status,
      hasRfid: hasRfid ?? this.hasRfid,
      isNewStudent: isNewStudent,
      parentGuardian: parentGuardian,
      contactNo: contactNo,
      email: email,
      enrolledDate: enrolledDate,
    );
  }
}

/// Today's tallies for the Overview tab's stat-card row.
class OverviewStatsModel {
  const OverviewStatsModel({
    this.totalStudents = 0,
    this.averageGpa,
    this.rfidPending = 0,
  });

  final int totalStudents;

  /// Null when no student has a recorded [RegistrarStudentModel.gpa] yet.
  final double? averageGpa;
  final int rfidPending;

  factory OverviewStatsModel.fromJson(Map<String, dynamic> json) {
    return OverviewStatsModel(
      totalStudents: json['total_students'] as int? ?? 0,
      averageGpa: (json['average_gpa'] as num?)?.toDouble(),
      rfidPending: json['rfid_pending'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'total_students': totalStudents,
      'average_gpa': averageGpa,
      'rfid_pending': rfidPending,
    };
  }
}

// ---------------------------------------------------------------------------
// Tab navigation state
// ---------------------------------------------------------------------------

enum RegistrarDashboardTab {
  overview,
  studentRecords,
  grades,
  classSchedule,
  rfidManagement,
}

/// "View all notifications"/"View all emails" swap the main content area
/// exactly like a normal sub-nav tab does — header and sub-nav bar stay put
/// — rather than opening a new page/route. Not one of [RegistrarDashboardTab]'s
/// own values since it isn't a real, always-visible tab; tapping any real
/// tab clears this back to null.
enum _MailboxView { notifications, email }

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

class RegistrarDashboardPage extends StatefulWidget {
  const RegistrarDashboardPage({
    super.key,
    this.registrarName = 'Juan Dela Cruz',
    this.onReturnToHub,
    this.onSignOut,
    this.initialStudents,
    this.initialOverviewStats,
    this.initialGradeRecords,
    this.initialScheduleEntries,
    this.initialNotifications,
    this.onMarkNotificationsRead,
    this.onReportTechnicalIssue,
    this.onAddStudent,
  });

  final String registrarName;

  /// Set when Admin opens this page from the hub as a preview; renders a
  /// back button in the header. Null for a Registrar's own direct login
  /// route, where there is no hub to return to.
  final VoidCallback? onReturnToHub;

  /// Renders a sign-out action in the header when set.
  final VoidCallback? onSignOut;

  /// Supplies live-data initial state (e.g. wired to Supabase from the host
  /// app). Each falls back to [RegistrarMockData] when omitted, so this
  /// package stays independently runnable/demoable without a backend.
  final List<RegistrarStudentModel>? initialStudents;
  final OverviewStatsModel? initialOverviewStats;
  final List<GradeRecordModel>? initialGradeRecords;
  final List<ScheduleEntryModel>? initialScheduleEntries;

  /// Notifications targeted at this dashboard from the centralized
  /// notification system (Admin's Notifications page). Falls back to an
  /// empty bell when omitted (demo behavior).
  final List<NotificationItemModel>? initialNotifications;

  /// Marks every currently-unread notification read — invoked by the bell's
  /// "View all notifications" action.
  final Future<void> Function()? onMarkNotificationsRead;

  /// Opens the shared technical-issue report dialog when supplied. Falls
  /// back to no header icon at all when omitted (demo behavior — nowhere to
  /// send the report).
  final Future<void> Function({
    required ReportTechnicalIssueCategory category,
    required String description,
    String? location,
  })? onReportTechnicalIssue;

  /// Persists a new student. Falls back to no "Add New Student" button at
  /// all when omitted (demo behavior — nowhere to save it).
  final Future<void> Function(NewStudentForm form)? onAddStudent;

  @override
  State<RegistrarDashboardPage> createState() =>
      _RegistrarDashboardPageState();
}

class _RegistrarDashboardPageState extends State<RegistrarDashboardPage> {
  late List<RegistrarStudentModel> students;
  late OverviewStatsModel overviewStats;
  late List<GradeRecordModel> gradeRecords;
  late List<ScheduleEntryModel> scheduleEntries;

  RegistrarDashboardTab activeTab = RegistrarDashboardTab.overview;
  RegistrarStudentModel? selectedStudent;

  /// Non-null while "View all notifications"/"View all emails" is showing
  /// in place of the normal tab content. See [_MailboxView].
  _MailboxView? _mailboxView;
  final List<RfidNotificationLogModel> _rfidNotificationLogs = [];

  final _themeMode = ValueNotifier(ThemeMode.light);
  late List<NotificationItemModel> _notifications;

  @override
  void initState() {
    super.initState();
    students = widget.initialStudents ?? RegistrarMockData.getStudents();
    overviewStats =
        widget.initialOverviewStats ?? RegistrarMockData.getOverviewStats();
    gradeRecords =
        widget.initialGradeRecords ?? RegistrarMockData.getGradeRecords();
    scheduleEntries = widget.initialScheduleEntries ??
        RegistrarMockData.getScheduleEntries();
    if (students.isNotEmpty) selectedStudent = students.first;
    _notifications = List.of(widget.initialNotifications ?? const []);
  }

  @override
  void dispose() {
    _themeMode.dispose();
    super.dispose();
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
      centered: context.isMobileWidth,
      contentBuilder: (popoverContext, setPopoverState) {
        return NotificationsPopover(
          notifications: _notifications,
          accentColor: RegistrarColors.azureBlue,
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

  Widget _themedProfileScreen() {
    return Theme(
      data: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: RegistrarColors.navyBlue,
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
      anchorAboveBottomNav: context.isMobileWidth,
      contentBuilder: (popoverContext, setPopoverState) {
        return AccountProfileMenu(
          userName: widget.registrarName,
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
            colorSchemeSeed: RegistrarColors.navyBlue,
            brightness:
                mode == ThemeMode.dark ? Brightness.dark : Brightness.light,
          ),
          child: child!,
        );
      },
      child: Builder(
        builder: (context) {
          final isMobile = context.isMobileWidth;

          final header = AppHeaderNavBar(
            title: 'Registrar Dashboard',
            backgroundColor: RegistrarColors.navyBlue,
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
                        widget.registrarName,
                        style: GoogleFonts.poppins(
                          fontSize: context.isMobileWidth ? 14 : 16,
                          fontWeight: FontWeight.w600,
                          color: RegistrarColors.gray,
                        ),
                      ),
                    ),
                    const SizedBox(width: 15),
                    ProfileAvatarButton(
                      onTap: _openProfile,
                      foregroundColor: RegistrarColors.navyBlue,
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
            backgroundColor: RegistrarColors.background(context),
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
        return _buildTabContent(isMobile: isMobile);
    }
  }

  Widget _buildTabContent({required bool isMobile}) {
    return switch (activeTab) {
      RegistrarDashboardTab.overview => _buildOverviewContent(
          isMobile: isMobile,
        ),
      RegistrarDashboardTab.studentRecords => StudentRecordsView(
          students: students,
          selectedStudent: selectedStudent,
          onSelect: (student) => setState(() => selectedStudent = student),
          onAddStudent: widget.onAddStudent,
        ),
      RegistrarDashboardTab.grades => GradesView(
          records: gradeRecords,
          onGradeChanged: _updateGradeRecord,
          onSaveChanges: _saveGradeChanges,
        ),
      RegistrarDashboardTab.classSchedule => ClassScheduleView(
          entries: scheduleEntries,
          onSaveChanges: _saveScheduleChanges,
        ),
      RegistrarDashboardTab.rfidManagement => RfidManagementView(
          students: students.where((s) => !s.hasRfid).toList(),
          onSubmitNotify: _submitRfidNotifications,
          onViewLogs: _showRfidNotificationLogs,
        ),
    };
  }

  void _submitRfidNotifications(List<String> selectedIds) {
    final notified =
        students.where((s) => selectedIds.contains(s.id)).toList();
    setState(() {
      students = students
          .map((s) => selectedIds.contains(s.id)
              ? s.copyWith(hasRfid: true)
              : s)
          .toList();
      _rfidNotificationLogs.insertAll(
        0,
        notified.map((s) => RfidNotificationLogModel(
              studentName: s.name,
              studentId: s.studentId,
              section: s.section,
            )),
      );
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'RFID assignment notice sent for ${selectedIds.length} student(s).',
        ),
      ),
    );
  }

  void _updateGradeRecord(String id, double grade) {
    setState(() {
      gradeRecords = gradeRecords
          .map((r) => r.id == id ? r.copyWith(grade: grade) : r)
          .toList();
    });
  }

  void _saveGradeChanges() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Grade changes saved.')),
    );
  }

  void _saveScheduleChanges() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Class schedule changes saved.')),
    );
  }

  void _showRfidNotificationLogs() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) =>
          RfidNotificationLogsDialog(logs: _rfidNotificationLogs),
    );
  }

  Widget _buildOverviewContent({required bool isMobile}) {
    final statsRow = LayoutBuilder(
      builder: (context, constraints) {
        final cards = [
          _StatCard(
            label: 'Total Students',
            value: '${overviewStats.totalStudents}',
            icon: Icons.groups_outlined,
          ),
          _StatCard(
            label: 'Average GPA',
            value: overviewStats.averageGpa?.toStringAsFixed(1) ?? '—',
            icon: Icons.trending_up_rounded,
          ),
          _StatCard(
            label: 'RFID Pending',
            value: '${overviewStats.rfidPending}',
            icon: Icons.warning_amber_rounded,
          ),
        ];

        if (isMobile) return MobileMetricGrid(cards: cards);

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

    final needRfidStudents = students.where((s) => !s.hasRfid).toList();
    final newStudents = students.where((s) => s.isNewStudent).toList();
    void goToStudentRecords() =>
        setState(() => activeTab = RegistrarDashboardTab.studentRecords);

    if (isMobile) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          statsRow,
          const SizedBox(height: 18),
          _OverviewStudentListCard(
            students: newStudents,
            onViewAllStudents: goToStudentRecords,
          ),
          const SizedBox(height: 18),
          _StudentNeedRfidCard(students: needRfidStudents),
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final stackColumns = constraints.maxWidth < 900;

        final listCard = _OverviewStudentListCard(
          students: newStudents,
          onViewAllStudents: goToStudentRecords,
        );
        final rfidCard = _StudentNeedRfidCard(students: needRfidStudents);

        if (stackColumns) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              statsRow,
              const SizedBox(height: 18),
              listCard,
              const SizedBox(height: 18),
              rfidCard,
            ],
          );
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            statsRow,
            const SizedBox(height: 18),
            ConstrainedBox(
              constraints:
                  BoxConstraints(maxHeight: context.masterDetailRowMaxHeight()),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: listCard),
                  const SizedBox(width: 18),
                  SizedBox(width: 320, child: rfidCard),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Sub navigation bar
// ---------------------------------------------------------------------------

class _SubNavBar extends StatelessWidget {
  const _SubNavBar({required this.activeTab, required this.onTabSelected});

  final RegistrarDashboardTab activeTab;
  final ValueChanged<RegistrarDashboardTab> onTabSelected;

  static const _tabs = [
    (RegistrarDashboardTab.overview, 'Overview', Icons.dashboard_outlined),
    (RegistrarDashboardTab.studentRecords, 'Student Records',
        Icons.folder_shared_outlined),
    (RegistrarDashboardTab.grades, 'Grades', Icons.grade_outlined),
    (RegistrarDashboardTab.classSchedule, 'Class Schedule',
        Icons.calendar_month_outlined),
    (RegistrarDashboardTab.rfidManagement, 'RFID Notify',
        Icons.contactless_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 48,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: RegistrarColors.card(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: RegistrarColors.cardBorder(context)),
      ),
      child: ScrollConfiguration(
        behavior: mouseDraggableScrollBehavior,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (tab, label, icon) in _tabs) ...[
                if (tab != _tabs.first.$1) const SizedBox(width: 45),
                _SubNavItem(
                  label: label,
                  icon: icon,
                  isActive: activeTab == tab,
                  onTap: () => onTabSelected(tab),
                ),
              ],
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
        ? RegistrarColors.azureBlue
        : RegistrarColors.mutedText(context);
    return InkWell(
      onTap: onTap,
      hoverColor: Colors.transparent,
      splashFactory: NoSplash.splashFactory,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              width: 2,
              color: isActive ? RegistrarColors.azureBlue : Colors.transparent,
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
// Overview — stat card
// ---------------------------------------------------------------------------

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
        color: RegistrarColors.card(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: RegistrarColors.cardBorder(context)),
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
                    color: RegistrarColors.mutedText(context),
                  ),
                ),
                Text(
                  value,
                  style: GoogleFonts.poppins(
                    fontSize: context.isMobileWidth ? 30 : 32,
                    fontWeight: FontWeight.w600,
                    color: RegistrarColors.statValue(context),
                  ),
                ),
              ],
            ),
          ),
          Icon(icon, size: 24, color: RegistrarColors.mutedText(context)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Overview — New Students card
// ---------------------------------------------------------------------------

class _OverviewStudentListCard extends StatefulWidget {
  const _OverviewStudentListCard({
    required this.students,
    this.onViewAllStudents,
  });

  final List<RegistrarStudentModel> students;

  /// Opens the Student Records tab. Falls back to no-op when omitted (demo
  /// behavior).
  final VoidCallback? onViewAllStudents;

  @override
  State<_OverviewStudentListCard> createState() =>
      _OverviewStudentListCardState();
}

class _OverviewStudentListCardState extends State<_OverviewStudentListCard> {
  int get _pageSize => context.cardPageSize;
  int _currentPage = 1;

  @override
  Widget build(BuildContext context) {
    final students = widget.students;
    final totalPages =
        students.isEmpty ? 1 : (students.length / _pageSize).ceil();
    final currentPage = _currentPage.clamp(1, totalPages);
    final pageStudents =
        students.skip((currentPage - 1) * _pageSize).take(_pageSize).toList();
    final headerStyle = GoogleFonts.poppins(
      fontSize: context.isMobileWidth ? 10 : 12,
      fontWeight: FontWeight.w600,
      color: Colors.white,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final bounded = constraints.hasBoundedHeight;
        final Widget list = students.isEmpty
            ? Center(
                child: Text(
                  'No new students yet',
                  style: GoogleFonts.poppins(
                    fontSize: context.isMobileWidth ? 11 : 13,
                    fontWeight: FontWeight.w500,
                    color: RegistrarColors.mutedText(context),
                  ),
                ),
              )
            : ListView.builder(
                shrinkWrap: !bounded,
                itemCount: pageStudents.length,
                itemBuilder: (context, index) =>
                    _StudentRow(student: pageStudents[index]),
              );

        return Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: RegistrarColors.card(context),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: RegistrarColors.cardBorder(context)),
          ),
          child: Column(
            mainAxisSize: bounded ? MainAxisSize.max : MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'New Students',
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                          fontSize: context.isMobileWidth ? 16 : 18,
                          fontWeight: FontWeight.w600,
                          color: RegistrarColors.rowText(context),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: widget.onViewAllStudents ?? () {},
                      borderRadius: BorderRadius.circular(6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'View All Students',
                            style: GoogleFonts.poppins(
                              fontSize: context.isMobileWidth ? 12 : 14,
                              fontWeight: FontWeight.w600,
                              color: RegistrarColors.azureBlue,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.arrow_forward_rounded,
                            size: 16,
                            color: RegistrarColors.azureBlue,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                color: RegistrarColors.navyBlue,
                child: Row(
                  children: [
                    Expanded(flex: 2, child: Text('Student', style: headerStyle)),
                    Expanded(
                        flex: 2,
                        child: Text('Student ID', style: headerStyle)),
                    Expanded(
                        flex: 2,
                        child: Text('Grade & Section', style: headerStyle)),
                    SizedBox(
                      width: 70,
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
              if (students.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                  child: PillPaginationFooter(
                    shownCount: pageStudents.length,
                    totalCount: students.length,
                    label: 'total new students',
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

class _StudentRow extends StatelessWidget {
  const _StudentRow({required this.student});

  final RegistrarStudentModel student;

  @override
  Widget build(BuildContext context) {
    final style = GoogleFonts.poppins(
      fontSize: context.isMobileWidth ? 11 : 13,
      fontWeight: FontWeight.w500,
      color: RegistrarColors.rowText(context),
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        border: Border(
            bottom: BorderSide(color: RegistrarColors.cardBorder(context))),
      ),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text(student.name, style: style)),
          Expanded(flex: 2, child: Text(student.studentId, style: style)),
          Expanded(flex: 2, child: Text(student.section, style: style)),
          SizedBox(
            width: 70,
            child: Center(child: StatusBadge(status: student.status)),
          ),
        ],
      ),
    );
  }
}

/// Colored enrollment-status pill shown in every student table.
class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.status});

  final EnrollmentStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: status.badgeBackground,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.label,
        style: GoogleFonts.poppins(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: status.badgeText,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Overview — Student Need RFID card
// ---------------------------------------------------------------------------

class _StudentNeedRfidCard extends StatefulWidget {
  const _StudentNeedRfidCard({required this.students});

  final List<RegistrarStudentModel> students;

  @override
  State<_StudentNeedRfidCard> createState() => _StudentNeedRfidCardState();
}

class _StudentNeedRfidCardState extends State<_StudentNeedRfidCard> {
  final _searchController = TextEditingController();
  String _query = '';

  /// 5 rows on a narrow phone, 10 at tablet width and up (see
  /// [ResponsiveX.cardPageSize]) — matches every sibling Overview card
  /// (e.g. [_OverviewStudentListCard]) instead of dumping every matching
  /// student into one unpaginated, internally-scrolling list.
  int get _pageSize => context.cardPageSize;
  int _currentPage = 1;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final filtered = query.isEmpty
        ? widget.students
        : widget.students
            .where((s) => s.name.toLowerCase().contains(query))
            .toList();
    final totalPages =
        filtered.isEmpty ? 1 : (filtered.length / _pageSize).ceil();
    final currentPage = _currentPage.clamp(1, totalPages);
    final pageStudents = filtered
        .skip((currentPage - 1) * _pageSize)
        .take(_pageSize)
        .toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final bounded = constraints.hasBoundedHeight;
        final Widget list = filtered.isEmpty
            ? Center(
                child: Text(
                  'No students need an RFID card',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: RegistrarColors.mutedText(context),
                  ),
                ),
              )
            : ListView.builder(
                shrinkWrap: !bounded,
                itemCount: pageStudents.length,
                itemBuilder: (context, index) {
                  final student = pageStudents[index];
                  return Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 29, vertical: 20),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                            color: RegistrarColors.cardBorder(context)),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          student.name,
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: RegistrarColors.rowText(context),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          student.section,
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: RegistrarColors.mutedText(context),
                          ),
                        ),
                        Text(
                          student.studentId,
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: RegistrarColors.mutedText(context),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );

        return Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: RegistrarColors.card(context),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: RegistrarColors.cardBorder(context)),
          ),
          child: Column(
            mainAxisSize: bounded ? MainAxisSize.max : MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(29, 24, 29, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Student Need RFID',
                            style: GoogleFonts.poppins(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: RegistrarColors.rowText(context),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Total students: ${widget.students.length}',
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              color: RegistrarColors.placeholderText(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'View All',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: RegistrarColors.azureBlue,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.arrow_forward_rounded,
                          size: 16,
                          color: RegistrarColors.azureBlue,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(29, 19, 29, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: SearchField(
                        controller: _searchController,
                        onChanged: (value) => setState(() {
                          _query = value;
                          _currentPage = 1;
                        }),
                      ),
                    ),
                    const SizedBox(width: 10),
                    const FilterButton(),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              bounded ? Expanded(child: list) : Flexible(child: list),
              if (filtered.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(29, 12, 29, 16),
                  child: PillPaginationFooter(
                    shownCount: pageStudents.length,
                    totalCount: filtered.length,
                    label: 'students needing RFID',
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

// ---------------------------------------------------------------------------
// Shared small building blocks — reused by the other tab views in this
// package (Student Records, Grades, Class Schedule, RFID Management).
// ---------------------------------------------------------------------------

/// "Showing X of Y {label}" plus light-Previous/navy-Next pill buttons —
/// exact match for the Figma "REG | *" frames' pagination footer.
class PillPaginationFooter extends StatelessWidget {
  const PillPaginationFooter({
    super.key,
    required this.shownCount,
    required this.totalCount,
    required this.label,
    required this.canGoPrevious,
    required this.canGoNext,
    required this.onPrevious,
    required this.onNext,
  });

  final int shownCount;
  final int totalCount;
  final String label;
  final bool canGoPrevious;
  final bool canGoNext;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final buttons = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _PillButton(
          text: 'Previous',
          background: RegistrarColors.background(context),
          foreground: RegistrarColors.azureBlue,
          onTap: canGoPrevious ? onPrevious : null,
        ),
        const SizedBox(width: 8),
        _PillButton(
          text: 'Next',
          background: RegistrarColors.azureBlue,
          foreground: Colors.white,
          onTap: canGoNext ? onNext : null,
        ),
      ],
    );

    final text = Text(
      'Showing $shownCount of $totalCount $label',
      style: GoogleFonts.poppins(
        fontSize: context.isMobileWidth ? 10 : 12,
        color: RegistrarColors.mutedText(context),
      ),
    );

    if (context.isMobileWidth) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          text,
          const SizedBox(height: 8),
          Align(alignment: Alignment.centerRight, child: buttons),
        ],
      );
    }

    return Row(
      children: [
        Expanded(child: text),
        const SizedBox(width: 12),
        buttons,
      ],
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.text,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  final String text;
  final Color background;
  final Color foreground;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            text,
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: onTap == null ? foreground.withOpacity(0.4) : foreground,
            ),
          ),
        ),
      ),
    );
  }
}

/// Pale, rounded search box used above several student/grade tables.
class SearchField extends StatelessWidget {
  const SearchField({
    super.key,
    required this.controller,
    required this.onChanged,
    this.hintText = 'Search',
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String hintText;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: GoogleFonts.poppins(
          fontSize: context.isMobileWidth ? 11 : 13,
          color: RegistrarColors.rowText(context),
        ),
        decoration: InputDecoration(
          isDense: true,
          hintText: hintText,
          hintStyle: GoogleFonts.poppins(
            fontSize: context.isMobileWidth ? 11 : 13,
            color: RegistrarColors.placeholderText(context),
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            size: 20,
            color: RegistrarColors.placeholderText(context),
          ),
          filled: true,
          fillColor: RegistrarColors.background(context),
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

/// Plain "Filter" button — decorative placeholder matching the Figma design;
/// no filter sheet is wired up yet.
class FilterButton extends StatelessWidget {
  const FilterButton({super.key, this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: RegistrarColors.background(context),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap ?? () {},
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
                color: RegistrarColors.placeholderText(context),
              ),
              const SizedBox(width: 6),
              Text(
                'Filter',
                style: GoogleFonts.poppins(
                  fontSize: context.isMobileWidth ? 11 : 13,
                  fontWeight: FontWeight.w400,
                  color: RegistrarColors.placeholderText(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact "Upload" trigger shared by the Class Schedule and Grades > Filter
/// cards — icon on the left, short label on the right; a hover/long-press
/// tooltip still spells out the full "Upload Spreadsheet" action. Tapping it
/// always opens the OS file explorer via `file_picker`.
class UploadSpreadsheetButton extends StatelessWidget {
  const UploadSpreadsheetButton({super.key, this.onFileSelected});

  /// Called with the file the user picked. Falls back to a confirmation
  /// snackbar when omitted (demo behavior — no import pipeline wired up
  /// yet). Not called at all when the picker is dismissed without a pick.
  final ValueChanged<PlatformFile>? onFileSelected;

  Future<void> _pickFile(BuildContext context) async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv', 'xlsx', 'xls'],
    );
    final picked = result?.files.single;
    if (picked == null) return;
    if (onFileSelected != null) {
      onFileSelected!(picked);
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Selected "${picked.name}".')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Upload Spreadsheet',
      child: Material(
        color: RegistrarColors.background(context),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: () => _pickFile(context),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.upload_rounded,
                  size: 16,
                  color: RegistrarColors.azureBlue,
                ),
                const SizedBox(width: 6),
                Text(
                  'Upload',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: RegistrarColors.azureBlue,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Solid "Save Changes" pill shared by the Class Schedule and Grades tabs.
/// [enabled] defaults to true (Class Schedule's form has no dirty-tracking
/// yet); Grades passes it explicitly so the button stays disabled until a
/// grade has actually been edited.
class SaveChangesButton extends StatelessWidget {
  const SaveChangesButton({super.key, this.enabled = true, this.onTap});

  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final disabled = !enabled || onTap == null;
    return Material(
      color: disabled
          ? RegistrarColors.azureBlue.withOpacity(0.5)
          : RegistrarColors.azureBlue,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: disabled ? null : onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.save_outlined,
                  size: 16, color: Colors.white.withOpacity(disabled ? 0.6 : 1)),
              const SizedBox(width: 5),
              Text(
                'Save Changes',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withOpacity(disabled ? 0.6 : 1),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Senior High School" / "College" toggle used by the Education Level
/// field in both the Class Schedule and Grades > Filter tabs. Shrinks the
/// long label down to "SHS" instead of letting it wrap onto a second line
/// when its pill doesn't have room for the full text.
class EducationLevelToggle extends StatelessWidget {
  const EducationLevelToggle({
    super.key,
    required this.value,
    required this.onChanged,
    this.spacing = 8,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final double spacing;

  static const _longLabel = 'Senior High School';
  static const _shortLabel = 'SHS';

  // Poppins @ 12px averages roughly this many px per character — avoids
  // depending on the real font having finished loading (GoogleFonts fetches
  // it asynchronously) just to decide whether the label fits on one line.
  static const _estimatedCharWidth = 7.8;

  bool _fitsLongLabel(double maxWidth) {
    const estimatedWidth = _longLabel.length * _estimatedCharWidth;
    // SelectionPill pads 14px on each side.
    return estimatedWidth <= maxWidth - 28;
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final label = _fitsLongLabel(constraints.maxWidth)
                  ? _longLabel
                  : _shortLabel;
              return SelectionPill(
                label: label,
                isSelected: value == _longLabel,
                onTap: () => onChanged(_longLabel),
              );
            },
          ),
        ),
        SizedBox(width: spacing),
        Expanded(
          child: SelectionPill(
            label: 'College',
            isSelected: value == 'College',
            onTap: () => onChanged('College'),
          ),
        ),
      ],
    );
  }
}

/// Selectable pill used for the Education Level / Year Level / Section /
/// Semester / Days single- or multi-select rows in the Grades and Class
/// Schedule tabs.
class SelectionPill extends StatelessWidget {
  const SelectionPill({
    super.key,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected
          ? RegistrarColors.azureBlue
          : RegistrarColors.background(context),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 35,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          child: Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              color: isSelected ? Colors.white : RegistrarColors.rowText(context),
            ),
          ),
        ),
      ),
    );
  }
}

/// Plain "Field Label" + dropdown-styled box — decorative placeholder
/// matching the Figma design; no picker is wired up yet.
class DropdownField extends StatelessWidget {
  const DropdownField({super.key, required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 35,
      padding: const EdgeInsets.symmetric(horizontal: 17),
      decoration: BoxDecoration(
        color: RegistrarColors.background(context),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: RegistrarColors.rowText(context),
              ),
            ),
          ),
          Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 20,
            color: RegistrarColors.mutedText(context),
          ),
        ],
      ),
    );
  }
}

class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: GoogleFonts.poppins(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: RegistrarColors.rowText(context),
        ),
      ),
    );
  }
}
