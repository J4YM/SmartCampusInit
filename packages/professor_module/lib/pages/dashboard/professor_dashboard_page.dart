import 'package:dashboard_layout/dashboard_layout.dart';
// Reuses the Discipline Officer module's shared header-popover components
// directly rather than duplicating them, matching the same pattern the
// Guidance Counselor module already uses for this widget set.
import 'package:discipline_officer_module/discipline_officer_module.dart'
    show
        AccountProfileMenu,
        EmailPopover,
        LogoutConfirmationDialog,
        NotificationItemModel,
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
  });

  final int present;
  final int absent;
  final int late;

  factory AttendanceSummaryModel.fromJson(Map<String, dynamic> json) {
    return AttendanceSummaryModel(
      present: json['present'] as int? ?? 0,
      absent: json['absent'] as int? ?? 0,
      late: json['late'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {'present': present, 'absent': absent, 'late': late};
  }
}

class StudentAttendanceRecordModel {
  const StudentAttendanceRecordModel({
    required this.id,
    required this.studentName,
    required this.presentCount,
    required this.totalSessions,
    required this.absentCount,
  });

  final String id;
  final String studentName;
  final int presentCount;
  final int totalSessions;
  final int absentCount;

  factory StudentAttendanceRecordModel.fromJson(Map<String, dynamic> json) {
    return StudentAttendanceRecordModel(
      id: json['id'] as String,
      studentName: json['student_name'] as String,
      presentCount: json['present_count'] as int? ?? 0,
      totalSessions: json['total_sessions'] as int? ?? 0,
      absentCount: json['absent_count'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'student_name': studentName,
      'present_count': presentCount,
      'total_sessions': totalSessions,
      'absent_count': absentCount,
    };
  }
}

// ---------------------------------------------------------------------------
// Tab navigation state
// ---------------------------------------------------------------------------

enum ProfessorDashboardTab { attendance, conductReport, admissionSlip }

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

  /// Persists today's attendance for [selectedSection] — one status per
  /// student id (`'Present'`/`'Absent'`/`'Late'`), from the "Take
  /// Attendance" dialog. When omitted, the action is unavailable (demo
  /// behavior — there's nowhere to persist it).
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

  /// Opens the Present/Absent/Late picker for every student in
  /// [selectedSection] and, on Submit, persists it via
  /// [ProfessorDashboardPage.onSubmitAttendance]. [studentAttendance]
  /// already lists one row per enrolled student (present/absent counts
  /// default to 0 for a student with no prior sessions), so it doubles as
  /// the roster for this dialog.
  Future<void> _handleTakeAttendance() async {
    final section = selectedSection;
    if (section == null) return;

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => _TakeAttendanceDialog(
        sectionName: section.name,
        roster: studentAttendance,
      ),
    );
    if (result == null || result.isEmpty || !mounted) return;

    try {
      await widget.onSubmitAttendance?.call(section, result);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Attendance saved for ${section.name}.')),
      );
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
          isDarkMode: _themeMode.value == ThemeMode.dark,
          onViewAll: () => Navigator.of(popoverContext).pop(),
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
                Container(
                  width: 60,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    'STI',
                    style: GoogleFonts.poppins(
                      fontSize: context.isMobileWidth ? 12 : 14,
                      fontWeight: FontWeight.w800,
                      color: ProfessorColors.navyBlue,
                    ),
                  ),
                ),
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
                    icon: Icons.build_outlined,
                    onTap: () => showReportTechnicalIssueDialog(
                      context,
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
                  onTabSelected: (tab) => setState(() => activeTab = tab),
                );

                // On mobile every card sizes to its own content instead
                // of being squeezed into a fixed Expanded share of the
                // viewport — that's what caused the overflow. The whole
                // page — including the header now, see body below —
                // scrolls instead, so nothing has to shrink past its
                // natural size.
                if (isMobile) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      subNavBar,
                      const SizedBox(height: 16),
                      _buildTabContent(activeTab, isMobile: true),
                    ],
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    subNavBar,
                    const SizedBox(height: 16),
                    Expanded(
                      child: _buildTabContent(activeTab, isMobile: false),
                    ),
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
            // On mobile the header scrolls away with the rest of the
            // page instead of staying pinned — the whole body is one
            // scrollable column. On desktop the header stays fixed and
            // only the tab content scrolls.
            body: isMobile
                ? SingleChildScrollView(
                    child: Column(children: [header, pageContent]),
                  )
                : Column(
                    children: [header, Expanded(child: pageContent)],
                  ),
          );
        },
      ),
    );
  }

  Widget _buildTabContent(ProfessorDashboardTab tab, {required bool isMobile}) {
    return switch (tab) {
      ProfessorDashboardTab.attendance =>
        _buildAttendanceContent(isMobile: isMobile),
      ProfessorDashboardTab.conductReport =>
        _buildConductReportContent(isMobile: isMobile),
      ProfessorDashboardTab.admissionSlip => _emptySection(
          isMobile: isMobile,
          icon: Icons.assignment_outlined,
          title: 'Admission Slip',
          subtitle: 'Admission slip records are not available yet',
        ),
    };
  }

  Widget _emptySection({
    required bool isMobile,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final section = _EmptySectionView(icon: icon, title: title, subtitle: subtitle);
    // On desktop this fills the Expanded space above it; on mobile there's
    // no Expanded ancestor to fill (the page scrolls instead), so it needs
    // its own bounded height.
    return isMobile ? SizedBox(height: 300, child: section) : section;
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

    final takeAttendanceButton = Align(
      alignment: Alignment.centerRight,
      child: FilledButton.icon(
        onPressed: widget.onSubmitAttendance == null || selectedSection == null
            ? null
            : _handleTakeAttendance,
        icon: const Icon(Icons.fact_check_outlined, size: 18),
        label: const Text('Take Attendance'),
      ),
    );

    if (isMobile) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: 420, child: sectionListCard),
          const SizedBox(height: 16),
          takeAttendanceButton,
          const SizedBox(height: 12),
          _AttendanceStatsRow(summary: attendanceSummary),
          const SizedBox(height: 18),
          // The table has its own internal ListView, so a fixed height
          // (matching the section list card) lets it scroll on its own
          // rather than being asked to size to unbounded content.
          SizedBox(
            height: 420,
            child: _StudentAttendanceTableCard(records: studentAttendance),
          ),
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final stackColumns = constraints.maxWidth < 900;

        final attendancePanel = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            takeAttendanceButton,
            const SizedBox(height: 12),
            _AttendanceStatsRow(summary: attendanceSummary),
            const SizedBox(height: 18),
            Expanded(
              child: _StudentAttendanceTableCard(records: studentAttendance),
            ),
          ],
        );

        if (stackColumns) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: 420, child: sectionListCard),
              const SizedBox(height: 16),
              Expanded(child: attendancePanel),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: 320, child: sectionListCard),
            const SizedBox(width: 18),
            Expanded(child: attendancePanel),
          ],
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
      expandContent: !isMobile,
    );

    if (isMobile) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: 420, child: studentListCard),
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

        final reportPanel = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ConductOffenseStatsRow(summary: offenseSummary),
            const SizedBox(height: 18),
            Expanded(child: reportCard),
          ],
        );

        if (stackColumns) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: 420, child: studentListCard),
              const SizedBox(height: 16),
              Expanded(child: reportPanel),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: 320, child: studentListCard),
            const SizedBox(width: 18),
            Expanded(child: reportPanel),
          ],
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
                isActive: activeTab == ProfessorDashboardTab.attendance,
                onTap: () => onTabSelected(ProfessorDashboardTab.attendance),
              ),
              const SizedBox(width: 45),
              _SubNavItem(
                label: 'Conduct Report',
                isActive: activeTab == ProfessorDashboardTab.conductReport,
                onTap: () =>
                    onTabSelected(ProfessorDashboardTab.conductReport),
              ),
              const SizedBox(width: 45),
              _SubNavItem(
                label: 'Admission Slip',
                isActive: activeTab == ProfessorDashboardTab.admissionSlip,
                onTap: () =>
                    onTabSelected(ProfessorDashboardTab.admissionSlip),
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
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
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
        child: Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: context.isMobileWidth ? 11 : 13,
            fontWeight: FontWeight.w600,
            color: isActive
                ? ProfessorColors.azureBlue
                : ProfessorColors.mutedText(context),
          ),
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

class _SectionListCard extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: ProfessorColors.card(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: ProfessorColors.cardBorder(context)),
      ),
      child: Column(
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
                  'Total section: $totalSectionCount',
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
                        controller: searchController,
                        onChanged: onSearchChanged)),
                const SizedBox(width: 10),
                _FilterButton(onTap: () {}),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Expanded(
            child: sections.isEmpty
                ? const _SectionListEmptyState()
                : ListView(
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
                      for (final section in sections)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _SectionRow(
                            section: section,
                            isSelected: section.id == selectedSectionId,
                            onTap: () => onSelect(section),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
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
        ];

        if (isNarrow) {
          return MobileMetricGrid(cards: cards);
        }

        return SizedBox(
          height: 124,
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

class _StudentAttendanceTableCard extends StatelessWidget {
  const _StudentAttendanceTableCard({required this.records});

  final List<StudentAttendanceRecordModel> records;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: ProfessorColors.card(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: ProfessorColors.cardBorder(context)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                border: Border(
                    bottom:
                        BorderSide(color: ProfessorColors.cardBorder(context))),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(
                      'Name',
                      style: GoogleFonts.poppins(
                        fontSize: context.isMobileWidth ? 11 : 13,
                        fontWeight: FontWeight.w500,
                        color: ProfessorColors.mutedText(context),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      'No. of Present',
                      textAlign: TextAlign.right,
                      style: GoogleFonts.poppins(
                        fontSize: context.isMobileWidth ? 11 : 13,
                        fontWeight: FontWeight.w500,
                        color: ProfessorColors.mutedText(context),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      'No. of Absent',
                      textAlign: TextAlign.right,
                      style: GoogleFonts.poppins(
                        fontSize: context.isMobileWidth ? 11 : 13,
                        fontWeight: FontWeight.w500,
                        color: ProfessorColors.mutedText(context),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: records.isEmpty
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
                      padding: const EdgeInsets.only(top: 10),
                      itemCount: records.length,
                      itemBuilder: (context, index) {
                        final record = records[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _StudentAttendanceRow(record: record),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StudentAttendanceRow extends StatelessWidget {
  const _StudentAttendanceRow({required this.record});

  final StudentAttendanceRecordModel record;

  @override
  Widget build(BuildContext context) {
    final style = GoogleFonts.poppins(
      fontSize: context.isMobileWidth ? 11 : 13,
      fontWeight: FontWeight.w500,
      color: ProfessorColors.rowText(context),
    );
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border(
            bottom: BorderSide(color: ProfessorColors.cardBorder(context))),
      ),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text(record.studentName, style: style)),
          Expanded(
            child: Text(
              '${record.presentCount}/${record.totalSessions}',
              textAlign: TextAlign.right,
              style: style,
            ),
          ),
          Expanded(
            child: Text(
              '${record.absentCount}',
              textAlign: TextAlign.right,
              style: style,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Take Attendance dialog
// ---------------------------------------------------------------------------

/// Present/Absent/Late picker for every student in [roster], opened by the
/// Attendance tab's "Take Attendance" button (see `_handleTakeAttendance`).
/// Every row defaults to Present — marking a whole section absent-by-default
/// would be a worse default for the common case (most students present most
/// days). Returns a student-id -> status map via `Navigator.pop`, or `null`
/// if cancelled.
class _TakeAttendanceDialog extends StatefulWidget {
  const _TakeAttendanceDialog({
    required this.sectionName,
    required this.roster,
  });

  final String sectionName;
  final List<StudentAttendanceRecordModel> roster;

  @override
  State<_TakeAttendanceDialog> createState() => _TakeAttendanceDialogState();
}

class _TakeAttendanceDialogState extends State<_TakeAttendanceDialog> {
  late final Map<String, String> _statusByStudentId = {
    for (final student in widget.roster) student.id: 'Present',
  };

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        'Take Attendance — ${widget.sectionName}',
        style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
      ),
      content: SizedBox(
        width: 480,
        height: 420,
        child: widget.roster.isEmpty
            ? const Center(child: Text('No students enrolled in this section.'))
            : ListView.separated(
                itemCount: widget.roster.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final student = widget.roster[index];
                  return _AttendancePickerRow(
                    studentName: student.studentName,
                    value: _statusByStudentId[student.id] ?? 'Present',
                    onChanged: (status) => setState(
                      () => _statusByStudentId[student.id] = status,
                    ),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: widget.roster.isEmpty
              ? null
              : () => Navigator.of(context).pop(_statusByStudentId),
          child: const Text('Submit'),
        ),
      ],
    );
  }
}

class _AttendancePickerRow extends StatelessWidget {
  const _AttendancePickerRow({
    required this.studentName,
    required this.value,
    required this.onChanged,
  });

  final String studentName;
  final String value;
  final ValueChanged<String> onChanged;

  static const _options = ['Present', 'Absent', 'Late'];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              studentName,
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: ProfessorColors.rowText(context),
              ),
            ),
          ),
          SegmentedButton<String>(
            segments: [
              for (final option in _options)
                ButtonSegment(value: option, label: Text(option)),
            ],
            selected: {value},
            onSelectionChanged: (selection) => onChanged(selection.first),
            showSelectedIcon: false,
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }
}
