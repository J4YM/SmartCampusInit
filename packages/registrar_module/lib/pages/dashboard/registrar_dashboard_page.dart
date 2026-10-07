import 'dart:typed_data';

import 'package:dashboard_layout/dashboard_layout.dart';
// Reuses the Discipline Officer module's shared header-popover components
// directly rather than duplicating them, matching the same pattern every
// other dashboard module (Professor, Guidance Counselor, …) already uses
// for this widget set.
import 'package:discipline_officer_module/discipline_officer_module.dart'
    show
        AccountProfileMenu,
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
import 'curriculum_view.dart';
import 'edit_student_dialog.dart';
import 'grades_view.dart';
import 'import_gpa_records_dialog.dart';
import 'import_students_dialog.dart';
import 'rfid_management_view.dart';
import 'rfid_notification_logs_dialog.dart';
import 'student_records_view.dart';
import 'subject_enrollments_view.dart';

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

  String get label => this == EnrollmentStatus.active ? 'Active' : 'Inactive';

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
    this.firstName = '',
    this.middleInitial = '',
    this.lastName = '',
    this.guardianContactNo = '',
  });

  final String id;
  final String name;

  /// [name] split back into its parts, for the "Edit Student Details" form.
  final String firstName;
  final String middleInitial;
  final String lastName;

  /// The guardian's number (`students.guardian_contact_no`) — what SMS alerts
  /// go to. Distinct from [contactNo], which is the student's own phone.
  final String guardianContactNo;
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
    this.newlyEnrolled = 0,
    this.rfidPending = 0,
  });

  final int totalStudents;

  /// Students enrolled this school year — see
  /// [RegistrarStudentModel.isNewStudent].
  final int newlyEnrolled;
  final int rfidPending;

  factory OverviewStatsModel.fromJson(Map<String, dynamic> json) {
    return OverviewStatsModel(
      totalStudents: json['total_students'] as int? ?? 0,
      newlyEnrolled: json['newly_enrolled'] as int? ?? 0,
      rfidPending: json['rfid_pending'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'total_students': totalStudents,
      'newly_enrolled': newlyEnrolled,
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
  curriculum,
  rfidManagement,
}

/// "View all notifications" swap the main content area
/// exactly like a normal sub-nav tab does — header and sub-nav bar stay put
/// — rather than opening a new page/route. Not one of [RegistrarDashboardTab]'s
/// own values since it isn't a real, always-visible tab; tapping any real
/// tab clears this back to null.
enum _MailboxView { notifications }

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
    this.initialSubjectOptions,
    this.initialTeacherOptions,
    this.initialSectionOptions,
    this.initialNotifications,
    this.onMarkNotificationsRead,
    this.onReportTechnicalIssue,
    this.onAddStudent,
    this.onImportStudents,
    this.onImportGpaRecords,
    this.curriculumEntries,
    this.onUploadCurriculum,
    this.onChangeSection,
    this.onEditStudent,
    this.onFetchEnrollments,
    this.onFetchOfferings,
    this.onEnroll,
    this.onDrop,
    this.onSaveClassSchedule,
    this.onImportSchedule,
    this.sectionScheduleOptions = const [],
    this.onSectionScheduleSelected,
    this.onExportSectionSchedulePdf,
    this.onExportSectionScheduleExcel,
    this.onSaveGradeChanges,
    this.onEnrollSection,
    this.onSubmitNotify,
    this.initialRfidNotificationLogs,
    this.isLoading = false,
  });

  /// `true` while the host is still fetching this dashboard's data — the
  /// header and sub-nav render immediately and only the tab content below
  /// them shows a skeleton, instead of the host blocking the whole screen.
  final bool isLoading;

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

  /// Real `subjects`/`profiles`(role `Teacher`)/`sections` options for the
  /// Class Schedule tab's Subject/Teacher/Section dropdowns. Falls back to
  /// [RegistrarMockData] when omitted, same as the lists above.
  final List<SubjectOption>? initialSubjectOptions;
  final List<TeacherOption>? initialTeacherOptions;
  final List<SectionOption>? initialSectionOptions;

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

  /// Runs a batch enrollment upload — see EnrollmentImportRunner
  /// (lib/data/enrollment_import_runner.dart). Each student's section is
  /// chosen automatically from their own row's Program/Level. Falls back
  /// to no "Import Students" button at all when omitted.
  final Future<ImportStudentsResult> Function({
    required PlatformFile file,
  })? onImportStudents;

  /// Runs a GPA-records batch upload from the Grades tab's own upload
  /// button — see GradeImportRunner (lib/data/grade_import_runner.dart).
  /// Falls back to the upload button's generic demo snackbar when omitted.
  final Future<ImportGpaRecordsResult> Function({
    required PlatformFile file,
  })? onImportGpaRecords;

  /// Curriculum tab: every course on file per program, and the action that
  /// uploads a curriculum CSV/Excel file (see CurriculumImportRunner).
  final List<CurriculumEntryModel>? curriculumEntries;
  final Future<CurriculumUploadResult> Function(PlatformFile file)?
      onUploadCurriculum;

  /// Persists a section override from the Student Records tab's profile
  /// panel — see ChangeSectionDialog's own doc comment. Falls back to no
  /// "Change Section" button when omitted.
  final Future<void> Function(String studentId, SectionOption section)?
      onChangeSection;

  /// Persists corrected personal/parent-guardian details from the Student
  /// Profile panel's "Edit Details" button — see EditStudentDialog. Falls
  /// back to no such button when omitted (demo behavior — nowhere to save).
  final Future<void> Function(String studentId, EditStudentForm form)?
      onEditStudent;

  /// Loads the selected student's active subject enrollments — see
  /// SubjectEnrollmentsSection's own doc comment. Falls back to hiding
  /// that whole section when omitted.
  final Future<List<StudentEnrollmentModel>> Function(String studentId)?
      onFetchEnrollments;

  /// Loads every class_sections offering (any section) for a chosen
  /// subject — the "Enroll in Subject" dialog's second picker.
  final Future<List<ClassSectionOffering>> Function(String subjectId)?
      onFetchOfferings;

  /// Enrolls a student in a chosen offering, including one belonging to a
  /// different section than their own — the irregular-enrollment action.
  final Future<void> Function(String studentId, String classSectionId)?
      onEnroll;

  /// Drops one of a student's existing enrollments.
  final Future<void> Function(String enrollmentId)? onDrop;

  /// Persists a new `class_sections` offering from the Class Schedule tab's
  /// "Add Class Schedule" card. Falls back to a "Class schedule changes
  /// saved." demo snackbar (no persistence) when omitted.
  final void Function({
    required String subjectId,
    required String professorId,
    required String sectionId,
    required String schoolYear,
    required String term,
    required String room,
    required List<String> days,
    required String startTime,
    required String endTime,
  })? onSaveClassSchedule;

  /// Runs an uploaded Excel schedule file through the import pipeline —
  /// see class_schedule_view.dart's ClassScheduleView.onImportSchedule.
  /// Falls back to a confirmation snackbar (no import) when omitted.
  final Future<void> Function({
    required Uint8List bytes,
    required String schoolYear,
    required String term,
  })? onImportSchedule;

  /// (id, name) pairs backing the generated-schedule section picker below
  /// the Class Schedule tab's existing form/table. Falls back to an empty
  /// (inert) picker when omitted.
  final List<({String id, String name})> sectionScheduleOptions;

  /// Fetches every meeting for the picked section's id — see
  /// SectionScheduleRepository.fetchSectionSchedule. Null disables the
  /// picker entirely (e.g. Supabase not configured).
  final Future<List<SectionScheduleRowModel>> Function(String sectionId)?
      onSectionScheduleSelected;

  /// Exports the currently-shown section's generated schedule as a PDF.
  /// Null hides the "Export PDF" button.
  final Future<void> Function(String sectionName, List<SectionScheduleRowModel> rows)?
      onExportSectionSchedulePdf;

  /// Exports the currently-shown section's generated schedule as an
  /// editable spreadsheet. Null hides the "Export Excel" button.
  final Future<void> Function(String sectionName, List<SectionScheduleRowModel> rows)?
      onExportSectionScheduleExcel;

  /// Called with every currently-visible edited grade record when "Save
  /// Changes" is tapped on the Grades tab. Falls back to a local demo
  /// snackbar when omitted (demo behavior) — matches onSaveClassSchedule's
  /// established null-fallback shape exactly.
  final Future<void> Function(List<GradeRecordModel> records)?
      onSaveGradeChanges;

  /// Bulk-enrolls a `class_sections` offering's home section into it — see
  /// RegistrarRepository.enrollSectionStudents. Falls back to a disabled
  /// "Enroll" button when omitted (demo behavior — nowhere to persist it).
  final ValueChanged<String>? onEnrollSection;

  /// Called with the selected students' ids when "Submit & Notify" is
  /// tapped on the RFID Notify tab. Falls back to purely-local demo
  /// behavior (flips hasRfid in memory, no persistence) when omitted.
  final Future<void> Function(List<String> studentIds)? onSubmitNotify;

  /// The signed-in registrar's own past RFID-notify submissions — backs
  /// "View Logs". Null/omitted falls back to an empty list (no curated
  /// mock data exists for this — matches the demo behavior this tab
  /// already had before this task).
  final List<RfidNotificationLogModel>? initialRfidNotificationLogs;

  @override
  State<RegistrarDashboardPage> createState() => _RegistrarDashboardPageState();
}

class _RegistrarDashboardPageState extends State<RegistrarDashboardPage> {
  late List<RegistrarStudentModel> students;
  late OverviewStatsModel overviewStats;
  late List<GradeRecordModel> gradeRecords;
  final Set<String> _dirtyGradeIds = {};
  late List<ScheduleEntryModel> scheduleEntries;
  late List<SubjectOption> subjectOptions;
  late List<TeacherOption> teacherOptions;
  late List<SectionOption> sectionOptions;

  RegistrarDashboardTab activeTab = RegistrarDashboardTab.overview;
  RegistrarStudentModel? selectedStudent;

  /// Non-null while "View all notifications" is showing
  /// in place of the normal tab content. See [_MailboxView].
  _MailboxView? _mailboxView;
  late List<RfidNotificationLogModel> _rfidNotificationLogs;

  final _themeMode = ValueNotifier(ThemeMode.light);
  late List<NotificationItemModel> _notifications;

  @override
  void initState() {
    super.initState();
    _seedFromWidget();
  }

  void _seedFromWidget() {
    students = widget.initialStudents ?? RegistrarMockData.getStudents();
    overviewStats =
        widget.initialOverviewStats ?? RegistrarMockData.getOverviewStats();
    gradeRecords =
        widget.initialGradeRecords ?? RegistrarMockData.getGradeRecords();
    scheduleEntries =
        widget.initialScheduleEntries ?? RegistrarMockData.getScheduleEntries();
    subjectOptions =
        widget.initialSubjectOptions ?? RegistrarMockData.getSubjectOptions();
    teacherOptions =
        widget.initialTeacherOptions ?? RegistrarMockData.getTeacherOptions();
    sectionOptions =
        widget.initialSectionOptions ?? RegistrarMockData.getSectionOptions();
    selectedStudent = students.isNotEmpty ? students.first : null;
    _notifications = List.of(widget.initialNotifications ?? const []);
    _rfidNotificationLogs = widget.initialRfidNotificationLogs ?? [];
  }

  @override
  void didUpdateWidget(covariant RegistrarDashboardPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The shell is built before the host's data arrives (only the tab
    // content shows a skeleton meanwhile), so the one-time seeds in
    // initState were mock data — re-seed from the real data once it lands.
    if (oldWidget.isLoading && !widget.isLoading) _seedFromWidget();
    // Only the Class Schedule tab's lists are kept in sync with new
    // `initial*` props after the first build — the host app re-fetches
    // `class_sections` after a successful "Save Changes" (see
    // RegistrarConnectedPage) and needs the new row to show up immediately
    // without a full remount. Other tabs' `initial*` lists are one-time
    // seeds only, matching this page's existing (pre-Task-4) behavior.
    // Students too: edit/change-section/import in the Student Records tab
    // re-fetch the list and must show without a page reload. The selected
    // student is re-pointed at its refreshed row (by id) so the profile
    // panel doesn't keep showing the stale copy.
    final newStudents = widget.initialStudents;
    if (newStudents != null && newStudents != oldWidget.initialStudents) {
      students = newStudents;
      final selectedId = selectedStudent?.id;
      RegistrarStudentModel? refreshed;
      for (final s in newStudents) {
        if (s.id == selectedId) {
          refreshed = s;
          break;
        }
      }
      selectedStudent =
          refreshed ?? (newStudents.isNotEmpty ? newStudents.first : null);
    }
    final newStats = widget.initialOverviewStats;
    if (newStats != null && newStats != oldWidget.initialOverviewStats) {
      overviewStats = newStats;
    }
    final newEntries = widget.initialScheduleEntries;
    if (newEntries != null && newEntries != oldWidget.initialScheduleEntries) {
      scheduleEntries = newEntries;
    }
    final newSubjects = widget.initialSubjectOptions;
    if (newSubjects != null && newSubjects != oldWidget.initialSubjectOptions) {
      subjectOptions = newSubjects;
    }
    final newTeachers = widget.initialTeacherOptions;
    if (newTeachers != null && newTeachers != oldWidget.initialTeacherOptions) {
      teacherOptions = newTeachers;
    }
    final newSections = widget.initialSectionOptions;
    if (newSections != null && newSections != oldWidget.initialSectionOptions) {
      sectionOptions = newSections;
    }
    final newGrades = widget.initialGradeRecords;
    if (newGrades != null && newGrades != oldWidget.initialGradeRecords) {
      gradeRecords = newGrades;
    }
    final newRfidLogs = widget.initialRfidNotificationLogs;
    if (newRfidLogs != null &&
        newRfidLogs != oldWidget.initialRfidNotificationLogs) {
      _rfidNotificationLogs = newRfidLogs;
    }
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

  Widget _themedProfileScreen() {
    return Theme(
      data: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: RegistrarColors.navyBlue,
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
      activeTab = RegistrarDashboardTab.overview;
      _mailboxView = null;
    });
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
          ).withPoppins(),
          child: child!,
        );
      },
      child: Builder(
        builder: (context) {
          final isMobile = context.isMobileWidth;
          // Overview and Student Records put a list card beside a side card;
          // when those sit side by side the page fills the window exactly
          // (no scroll) and only scrolls below kDashboardMinFillHeight.
          // Stacked (narrow) layouts, the mailbox and the skeleton keep
          // their natural, content-sized height.
          final fillViewport = _mailboxView == null &&
              !widget.isLoading &&
              (activeTab == RegistrarDashboardTab.overview ||
                  activeTab == RegistrarDashboardTab.studentRecords) &&
              context.showsMasterDetailRow();

          final header = AppHeaderNavBar(
            title: 'Registrar Dashboard',
            subtitle: kSchoolName,
            backgroundColor: RegistrarColors.navyBlue,
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
                  foregroundColor: RegistrarColors.navyBlue,
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
                final body = _buildBody(isMobile: isMobile);
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
            backgroundColor: RegistrarColors.background(context),
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
            // content below them scrolls.
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

  Widget _buildBody({required bool isMobile}) {
    switch (_mailboxView) {
      case _MailboxView.notifications:
        return NotificationsListView(
          notifications: _notifications,
          isDarkMode: _themeMode.value == ThemeMode.dark,
        );
      case null:
        if (widget.isLoading) {
          return DashboardSkeletonScreen(
            useScaffold: false,
            wrapInPageFrame: false,
            backgroundColor: RegistrarColors.background(context),
            cardColor: RegistrarColors.card(context),
            cardBorderColor: RegistrarColors.cardBorder(context),
            placeholderColor: RegistrarColors.gray,
          );
        }
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
          sectionOptions: sectionOptions,
          onImportStudents: widget.onImportStudents,
          onChangeSection: widget.onChangeSection,
          onEditStudent: widget.onEditStudent,
          subjectOptions: subjectOptions,
          onFetchEnrollments: widget.onFetchEnrollments,
          onFetchOfferings: widget.onFetchOfferings,
          onEnroll: widget.onEnroll,
          onDrop: widget.onDrop,
        ),
      RegistrarDashboardTab.grades => GradesView(
          records: gradeRecords,
          onGradeChanged: _updateGradeRecord,
          onSaveChanges: _saveGradeChanges,
          onImportGpaRecords: widget.onImportGpaRecords,
        ),
      RegistrarDashboardTab.classSchedule => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Builder: the dialog must capture this page's self-built
            // Theme, which the State's own `context` sits above.
            Builder(
              builder: (tabContext) => SectionScheduleCard(
                sectionOptions: widget.sectionScheduleOptions,
                onSectionSelected: widget.onSectionScheduleSelected,
                onExportPdf: widget.onExportSectionSchedulePdf,
                onExportExcel: widget.onExportSectionScheduleExcel,
                onAddSchedule: () => showAddClassScheduleDialog(
                  tabContext,
                  subjectOptions: subjectOptions,
                  teacherOptions: teacherOptions,
                  sectionOptions: sectionOptions,
                  onSaveChanges: _saveScheduleChanges,
                  onImportSchedule: widget.onImportSchedule,
                ),
                accentColor: RegistrarColors.azureBlue,
              ),
            ),
            const SizedBox(height: 16),
            ClassScheduleView(
              entries: scheduleEntries,
              onEnrollSection: widget.onEnrollSection,
            ),
          ],
        ),
      RegistrarDashboardTab.curriculum => CurriculumView(
          entries: widget.curriculumEntries ?? const [],
          onUpload: widget.onUploadCurriculum,
        ),
      RegistrarDashboardTab.rfidManagement => RfidManagementView(
          students: students.where((s) => !s.hasRfid).toList(),
          onSubmitNotify: _submitRfidNotifications,
          onViewLogs: _showRfidNotificationLogs,
        ),
    };
  }

  void _submitRfidNotifications(List<String> selectedIds) {
    final onSubmitNotify = widget.onSubmitNotify;
    if (onSubmitNotify == null) {
      final notified =
          students.where((s) => selectedIds.contains(s.id)).toList();
      setState(() {
        students = students
            .map((s) =>
                selectedIds.contains(s.id) ? s.copyWith(hasRfid: true) : s)
            .toList();
        _rfidNotificationLogs = [
          ...notified.map((s) => RfidNotificationLogModel(
                studentName: s.name,
                studentId: s.studentId,
                section: s.section,
              )),
          ..._rfidNotificationLogs,
        ];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'RFID assignment notice sent for ${selectedIds.length} student(s).',
          ),
        ),
      );
      return;
    }
    onSubmitNotify(selectedIds);
  }

  void _updateGradeRecord(String id, double grade) {
    setState(() {
      gradeRecords = gradeRecords
          .map((r) => r.id == id ? r.copyWith(grade: grade) : r)
          .toList();
      _dirtyGradeIds.add(id);
    });
  }

  void _saveGradeChanges() {
    final onSaveGradeChanges = widget.onSaveGradeChanges;
    if (onSaveGradeChanges == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Grade changes saved.')),
      );
      return;
    }
    final dirtyRecords =
        gradeRecords.where((r) => _dirtyGradeIds.contains(r.id)).toList();
    _dirtyGradeIds.clear();
    onSaveGradeChanges(dirtyRecords);
  }

  void _saveScheduleChanges({
    required String subjectId,
    required String professorId,
    required String sectionId,
    required String schoolYear,
    required String term,
    required String room,
    required List<String> days,
    required String startTime,
    required String endTime,
  }) {
    final onSaveClassSchedule = widget.onSaveClassSchedule;
    if (onSaveClassSchedule == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Class schedule changes saved.')),
      );
      return;
    }
    onSaveClassSchedule(
      subjectId: subjectId,
      professorId: professorId,
      sectionId: sectionId,
      schoolYear: schoolYear,
      term: term,
      room: room,
      days: days,
      startTime: startTime,
      endTime: endTime,
    );
  }

  void _showRfidNotificationLogs() {
    // showDialog renders in the root Overlay, outside this page's own Theme,
    // so the dialog needs the page's theme re-applied. Built from the page's
    // dark-mode toggle rather than `Theme.of(context)`: this State's own
    // `context` sits ABOVE the Theme build() creates, so it would always
    // resolve to the app's ambient (light) theme.
    final theme = ThemeData(
      useMaterial3: true,
      colorSchemeSeed: RegistrarColors.navyBlue,
      brightness:
          _themeMode.value == ThemeMode.dark ? Brightness.dark : Brightness.light,
    ).withPoppins();
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Theme(
        data: theme,
        child: RfidNotificationLogsDialog(logs: _rfidNotificationLogs),
      ),
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
            label: 'Newly Enrolled Students',
            value: '${overviewStats.newlyEnrolled}',
            icon: Icons.person_add_alt_1_outlined,
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
    void goToRfidNotify() =>
        setState(() => activeTab = RegistrarDashboardTab.rfidManagement);

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
          _StudentNeedRfidCard(
              students: needRfidStudents, onViewAll: goToRfidNotify),
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final stackColumns = constraints.maxWidth < kMasterDetailStackBreakpoint;

        final listCard = _OverviewStudentListCard(
          students: newStudents,
          onViewAllStudents: goToStudentRecords,
        );
        final rfidCard = _StudentNeedRfidCard(
              students: needRfidStudents, onViewAll: goToRfidNotify);

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

        final cardsRow = Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: listCard),
            const SizedBox(width: 18),
            SizedBox(width: 320, child: rfidCard),
          ],
        );

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            statsRow,
            const SizedBox(height: 18),
            // Bounded = the page is filling the window (see fillViewport),
            // so the cards take exactly the height left under the stats.
            if (constraints.hasBoundedHeight)
              Expanded(child: cardsRow)
            else
              ConstrainedBox(
                constraints: BoxConstraints(
                    maxHeight: context.masterDetailRowMaxHeight()),
                child: cardsRow,
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
    (
      RegistrarDashboardTab.studentRecords,
      'Student Records',
      Icons.folder_shared_outlined
    ),
    (RegistrarDashboardTab.grades, 'Grades', Icons.grade_outlined),
    (RegistrarDashboardTab.curriculum, 'Curriculum', Icons.menu_book_outlined),
    (
      RegistrarDashboardTab.classSchedule,
      'Class Schedule',
      Icons.calendar_month_outlined
    ),
    (
      RegistrarDashboardTab.rfidManagement,
      'RFID Notify',
      Icons.contactless_outlined
    ),
  ];

  @override
  Widget build(BuildContext context) {
    // Full-bleed strip pinned directly under the main header (see
    // DashboardSubNavStrip).
    return DashboardSubNavStrip(
      backgroundColor: RegistrarColors.card(context),
      borderColor: RegistrarColors.cardBorder(context),
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
        color: subNavActiveColor(context, RegistrarColors.azureBlue),
        child: _tab(context),
      );

  Widget _tab(BuildContext context) {
    final color = isActive
        ? subNavActiveColor(context, RegistrarColors.azureBlue)
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
              color: isActive ? subNavActiveColor(context, RegistrarColors.azureBlue) : Colors.transparent,
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
    return BentoCard(
      backgroundColor: RegistrarColors.card(context),
      borderColor: RegistrarColors.cardBorder(context),
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
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final students = [
      for (final s in widget.students)
        if (matchesSearchQuery(_query, [s.name, s.studentId, s.section])) s,
    ];
    final totalPages =
        students.isEmpty ? 1 : (students.length / _pageSize).ceil();
    final currentPage = _currentPage.clamp(1, totalPages);
    final pageStudents =
        students.skip((currentPage - 1) * _pageSize).take(_pageSize).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final bounded = constraints.hasBoundedHeight;
        final Widget list = students.isEmpty
            ? DashboardTableEmptyState(
                message: widget.students.isEmpty
                    ? 'No new students yet'
                    : 'No students match your search',
              )
            : ListView.builder(
                shrinkWrap: !bounded,
                padding: EdgeInsets.zero,
                itemCount: pageStudents.length,
                itemBuilder: (context, index) => _StudentRow(
                  student: pageStudents[index],
                  showDivider: index < pageStudents.length - 1,
                ),
              );

        return BentoCard(
          backgroundColor: RegistrarColors.card(context),
          borderColor: RegistrarColors.cardBorder(context),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: bounded ? MainAxisSize.max : MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Builder(builder: (context) {
                final title = Text(
                  'New Students',
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: context.isMobileWidth ? 16 : 18,
                    fontWeight: FontWeight.w600,
                    color: RegistrarColors.rowText(context),
                  ),
                );
                final viewAll = SecondaryPillButton(
                  key: const Key('view-all-students'),
                  icon: Icons.arrow_forward_rounded,
                  iconAtEnd: true,
                  label: 'View All Students',
                  onTap: widget.onViewAllStudents ?? () {},
                );
                final search = SearchField(
                  controller: _searchController,
                  hintText: 'Search students',
                  onChanged: (value) => setState(() {
                    _query = value;
                    _currentPage = 1;
                  }),
                );

                // Wide card: title, then the search bar and "View All
                // Students" on the same row, the search to the LEFT of the
                // link. A narrow card can't hold all three side by side, so
                // the search drops to its own row under the title.
                if (constraints.maxWidth >= _kNewStudentsInlineSearchWidth) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                    child: Row(
                      children: [
                        // Not Flexible: a flex slot would split the spare width
                        // with the search and strand a gap on the right. The
                        // title keeps its own width, on the card's left.
                        title,
                        const SizedBox(width: 16),
                        Expanded(
                          child: MaxWidthAligned(
                            alignment: Alignment.centerRight,
                            child: search,
                          ),
                        ),
                        const SizedBox(width: 16),
                        viewAll,
                      ],
                    ),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                      child: Row(
                        children: [
                          Expanded(child: title),
                          const SizedBox(width: 8),
                          viewAll,
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                      child: MaxWidthAligned(child: search),
                    ),
                  ],
                );
              }),
              DashboardTableSection(
                columns: _newStudentColumns,
                expandBody: bounded,
                body: list,
              ),
              if (students.isNotEmpty)
                DashboardTableFooter(
                  child: CardPaginationFooter(
                    currentPage: currentPage,
                    totalPages: totalPages,
                    totalCount: students.length,
                    textColor: RegistrarColors.mutedText(context),
                    accentColor: RegistrarColors.azureBlue,
                    mutedBackground: RegistrarColors.background(context),
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

const _newStudentColumns = <DashboardTableColumn>[
  DashboardTableColumn('Student', flex: 2),
  DashboardTableColumn('Student ID', flex: 2),
  DashboardTableColumn('Grade & Section', flex: 2),
  DashboardTableColumn('Status', flex: 1, compact: true),
];

class _StudentRow extends StatelessWidget {
  const _StudentRow({required this.student, required this.showDivider});

  final RegistrarStudentModel student;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return DashboardTableRow(
      columns: _newStudentColumns,
      showDivider: showDivider,
      cells: [
        Text(
          student.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: dashboardTablePrimaryStyle(context),
        ),
        Text(
          student.studentId,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: dashboardTableIdStyle(context),
        ),
        Text(
          student.section,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: dashboardTableBodyStyle(context),
        ),
        StatusBadge(status: student.status),
      ],
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
  const _StudentNeedRfidCard({required this.students, this.onViewAll});

  /// Opens the full RFID Notify list.
  final VoidCallback? onViewAll;

  final List<RegistrarStudentModel> students;

  @override
  State<_StudentNeedRfidCard> createState() => _StudentNeedRfidCardState();
}

class _StudentNeedRfidCardState extends State<_StudentNeedRfidCard> {
  final _searchController = TextEditingController();
  String _query = '';

  /// The one section picked in the Filter popup, or null for "All sections"
  /// (widget.students already arrives narrowed to students needing an RFID
  /// card, so section is what helps plan the physical rollout).
  String? _sectionFilter;

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

  FilterSectionPicker get _sectionPicker => FilterSectionPicker(
        entries: sectionFilterEntries(
            [for (final s in widget.students) (s.section, s.program)]),
        selectedId: _sectionFilter,
        onChanged: (id) => setState(() {
          _sectionFilter = id;
          _currentPage = 1;
        }),
      );

  @override
  Widget build(BuildContext context) {
    final filtered = widget.students.where((s) {
      final matchesQuery =
          matchesSearchQuery(_query, [s.name, s.studentId, s.section]);
      return matchesQuery && matchesSectionFilter(_sectionFilter, s.section);
    }).toList();
    final totalPages =
        filtered.isEmpty ? 1 : (filtered.length / _pageSize).ceil();
    final currentPage = _currentPage.clamp(1, totalPages);
    final pageStudents =
        filtered.skip((currentPage - 1) * _pageSize).take(_pageSize).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final bounded = constraints.hasBoundedHeight;
        final Widget list = filtered.isEmpty
            ? Center(
                child: Text(
                  'No students need an RFID card',
                  style: GoogleFonts.poppins(
                    fontSize: context.isMobileWidth ? 11 : 13,
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
                            fontSize: context.isMobileWidth ? 12 : 14,
                            fontWeight: FontWeight.w600,
                            color: RegistrarColors.rowText(context),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          student.section,
                          style: GoogleFonts.poppins(
                            fontSize: context.isMobileWidth ? 10 : 12,
                            color: RegistrarColors.mutedText(context),
                          ),
                        ),
                        Text(
                          student.studentId,
                          style: GoogleFonts.poppins(
                            fontSize: context.isMobileWidth ? 10 : 12,
                            color: RegistrarColors.mutedText(context),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );

        return BentoCard(
          backgroundColor: RegistrarColors.card(context),
          borderColor: RegistrarColors.cardBorder(context),
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
                      'Student Need RFID',
                      style: GoogleFonts.poppins(
                        fontSize: context.isMobileWidth ? 16 : 18,
                        fontWeight: FontWeight.w600,
                        color: RegistrarColors.rowText(context),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Total students: ${widget.students.length}',
                      style: GoogleFonts.poppins(
                        fontSize: context.isMobileWidth ? 11 : 13,
                        color: RegistrarColors.placeholderText(context),
                      ),
                    ),
                  ],
                ),
              ),
              // Between the title block and the search bar, the card's full
              // width: the app's standard secondary pill button.
              Padding(
                padding: const EdgeInsets.fromLTRB(29, 16, 29, 0),
                child: SecondaryPillButton(
                  key: const Key('view-all-rfid'),
                  icon: Icons.arrow_forward_rounded,
                  iconAtEnd: true,
                  label: 'View All',
                  expand: true,
                  onTap: widget.onViewAll,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(29, 19, 29, 0),
                child: Row(
                  children: [
                    // Flexible (not Expanded) so the filter button hugs the
                    // search once it hits its maximum width.
                    Flexible(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                            maxWidth: kRegistrarSearchMaxWidth),
                        child: SearchField(
                          controller: _searchController,
                          onChanged: (value) => setState(() {
                            _query = value;
                            _currentPage = 1;
                          }),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilterMenuButton(
                      compact: true,
                      backgroundColor: RegistrarColors.background(context),
                      menuColor: RegistrarColors.card(context),
                      borderColor: RegistrarColors.cardBorder(context),
                      iconColor: RegistrarColors.placeholderText(context),
                      textColor: RegistrarColors.rowText(context),
                      mutedTextColor: RegistrarColors.mutedText(context),
                      accentColor: RegistrarColors.azureBlue,
                      sectionFilter: _sectionPicker,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              bounded ? Expanded(child: list) : Flexible(child: list),
              if (filtered.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(29, 12, 29, 16),
                  child: CardPaginationFooter(
                    currentPage: currentPage,
                    totalPages: totalPages,
                    totalCount: filtered.length,
                    textColor: RegistrarColors.mutedText(context),
                    accentColor: RegistrarColors.azureBlue,
                    mutedBackground: RegistrarColors.background(context),
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

/// The widest a Registrar search box ever gets, however wide its card is
/// (Student Records caps its search at the same 440).
const double kRegistrarSearchMaxWidth = 440;

/// Card width from which the New Students card puts its search bar in the
/// title row, beside "View All Students" — room for the title, a usable
/// search field and the link on one line. Narrower, the search sits below.
const double _kNewStudentsInlineSearchWidth = 640;

/// Lays [child] out no wider than [maxWidth], pinned to [alignment] inside
/// whatever width it is given — unlike a bare [ConstrainedBox], which a
/// tight incoming width (an [Expanded] slot, a stretched [Column]) overrides.
class MaxWidthAligned extends StatelessWidget {
  const MaxWidthAligned({
    super.key,
    required this.child,
    this.maxWidth = kRegistrarSearchMaxWidth,
    this.alignment = Alignment.centerLeft,
  });

  final Widget child;
  final double maxWidth;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

/// Case-insensitive "does any of [fields] contain [query]" — the match every
/// Registrar search box uses. A blank [query] matches everything.
bool matchesSearchQuery(String query, Iterable<String> fields) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  return fields.any((f) => f.toLowerCase().contains(q));
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
      height: kDashboardControlHeight,
      child: TextField(
        expands: true,
        maxLines: null,
        minLines: null,
        textAlignVertical: TextAlignVertical.center,
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
        // Never shorter than the toolbar controls beside it.
        child: ConstrainedBox(
          constraints:
              const BoxConstraints(minHeight: kDashboardControlHeight),
          child: Align(
            widthFactor: 1,
            heightFactor: 1,
            child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.save_outlined,
                  size: 16,
                  color: Colors.white.withOpacity(disabled ? 0.6 : 1)),
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
        ),
      ),
    );
  }
}

/// Tinted action pill — the same look as "View Logs" / "Add Schedule" /
/// "Upload GPA Records": pale background, azure label and 16px icon, 12px
/// w600 text, 12x8 padding, 10px radius. With [expand] it stretches to the
/// width its parent gives it (label centered) instead of wrapping its text.
class RegistrarPillButton extends StatelessWidget {
  const RegistrarPillButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.expand = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    return SecondaryPillButton(
      label: label,
      icon: icon,
      onTap: onTap,
      expand: expand,
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
          height: kDashboardControlHeight,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          child: Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              color:
                  isSelected ? Colors.white : RegistrarColors.rowText(context),
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
