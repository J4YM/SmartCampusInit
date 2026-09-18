import 'dart:async';
import 'dart:typed_data';

import 'package:dashboard_layout/dashboard_layout.dart'
    show DashboardSkeletonScreen, ReportTechnicalIssueCategory;
import 'package:discipline_officer_module/discipline_officer_module.dart'
    show NotificationItemModel;
import 'package:flutter/material.dart';
import 'package:registrar_module/registrar_module.dart';
import 'package:registrar_module/theme/registrar_colors.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/app_role.dart';
import '../data/notifications_repository.dart';
import '../data/registrar_repository.dart';
import '../data/rfid_requests_repository.dart';
import '../data/schedule_import_repository.dart';
import '../data/schedule_import_runner.dart';
import '../data/students_repository.dart';
import '../data/technical_issues_repository.dart';
import '../env.dart';

/// Wires [RegistrarDashboardPage] into the app's navigation. Overview,
/// Student Records, RFID Management, Class Schedule, and Grades are all real
/// (via [RegistrarRepository] — `students`/`profiles`/`sections`/`subjects`/
/// `class_sections`/`grades`). RFID Notify's submit/view-logs flow is real
/// too (via [RfidRequestsRepository] — `rfid_assignment_requests`). The
/// shared notification bell and Report Technical Issue action reuse the
/// same [NotificationsRepository]/[TechnicalIssuesRepository] every other
/// dashboard already uses.
class RegistrarConnectedPage extends StatefulWidget {
  const RegistrarConnectedPage({
    super.key,
    this.registrarName,
    this.registrarProfileId,
    this.onReturnToHub,
    this.onSignOut,
  });

  final String? registrarName;

  /// The signed-in user's `profiles.id`. The static `registrar.demo`
  /// account (lib/auth/static_demo_accounts.dart) has no real Supabase Auth
  /// identity (its id starts with `u_`), so notifications fall back to
  /// role-only broadcasts for it — see [_notifiableUserId].
  final String? registrarProfileId;

  final VoidCallback? onReturnToHub;
  final VoidCallback? onSignOut;

  @override
  State<RegistrarConnectedPage> createState() =>
      _RegistrarConnectedPageState();
}

class _RegistrarConnectedPageState extends State<RegistrarConnectedPage> {
  List<NotificationItemModel>? _notifications;
  List<RegistrarStudentModel>? _students;
  OverviewStatsModel? _overviewStats;
  List<ScheduleEntryModel>? _scheduleEntries;
  List<SubjectOption>? _subjectOptions;
  List<TeacherOption>? _teacherOptions;
  List<SectionOption>? _sectionOptions;
  List<GradeRecordModel>? _gradeRecords;
  List<RfidNotificationLogModel>? _myRfidRequests;
  bool _loading = true;
  String? _error;

  RealtimeChannel? _notificationsChannel;
  RealtimeChannel? _studentsChannel;
  Timer? _reloadDebounce;
  Timer? _studentsReloadDebounce;

  NotificationsRepository? get _notifRepo {
    if (!AppEnv.supabaseConfigured) return null;
    return NotificationsRepository(Supabase.instance.client);
  }

  TechnicalIssuesRepository? get _issuesRepo {
    if (!AppEnv.supabaseConfigured) return null;
    return TechnicalIssuesRepository(Supabase.instance.client);
  }

  RegistrarRepository? get _registrarRepo {
    if (!AppEnv.supabaseConfigured) return null;
    return RegistrarRepository(Supabase.instance.client);
  }

  ScheduleImportRunner? get _scheduleImportRunner {
    final registrarRepo = _registrarRepo;
    if (!AppEnv.supabaseConfigured || registrarRepo == null) return null;
    return ScheduleImportRunner(
      scheduleImportRepository: ScheduleImportRepository(Supabase.instance.client),
      registrarRepository: registrarRepo,
    );
  }

  StudentsRepository? get _studentsRepo {
    if (!AppEnv.supabaseConfigured) return null;
    return StudentsRepository(Supabase.instance.client);
  }

  RfidRequestsRepository? get _rfidRequestsRepo {
    if (!AppEnv.supabaseConfigured) return null;
    return RfidRequestsRepository(Supabase.instance.client);
  }

  /// Matches the fixed profile seeded by
  /// supabase/add_rfid_assignment_requests_schema.sql — keep the two in
  /// sync if it ever changes. Static demo account ids all use the `u_`
  /// prefix (see SessionController.canVerifyPassword), which is how this
  /// tells "demo account, no real profile row" apart from a real Supabase
  /// Auth UUID. Used only for the RFID notify flow's `requested_by` FK —
  /// [_notifiableUserId] stays null for the demo account on purpose, for
  /// the shared notification bell's role-only-broadcast behavior.
  static const _demoRegistrarProfileId =
      '00000000-0000-4000-8000-000000000003';

  String get _effectiveRegistrarId {
    final id = widget.registrarProfileId;
    if (id == null || id.startsWith('u_')) return _demoRegistrarProfileId;
    return id;
  }

  /// Onboards a new student — the same `students`/`profiles` tables IT
  /// Technician's own Student Records tab already reads and writes, so a
  /// student Registrar adds here shows up there immediately (and vice
  /// versa) with no extra plumbing.
  Future<void> _addStudent(NewStudentForm form) async {
    final repo = _studentsRepo;
    if (repo == null) {
      throw Exception('Supabase is not configured.');
    }
    await repo.create(
      studentNumber: form.studentNumber,
      rfidUid: '',
      firstName: form.firstName,
      middleInitial: form.middleInitial,
      lastName: form.lastName,
      course: form.course,
      yearLevel: _yearLevelLabelToInt(form.yearLevel),
      sectionName: form.section,
      guardianContactNo: '',
      email: form.email,
      phoneNumber: form.contactNo,
    );
    await _loadStudents();
  }

  int _yearLevelLabelToInt(String label) =>
      ['1st Year', '2nd Year', '3rd Year', '4th Year'].indexOf(label) + 1;

  Future<void> _loadStudents() async {
    final repo = _registrarRepo;
    if (repo == null) {
      setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final students = await repo.fetchStudents();
      final overviewStats = await repo.fetchOverviewStats();
      if (!mounted) return;
      setState(() {
        _students = students;
        _overviewStats = overviewStats;
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not load students: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _loadClassScheduleOptions() async {
    final repo = _registrarRepo;
    if (repo == null) return;
    try {
      final subjects = await repo.fetchSubjects();
      final teachers = await repo.fetchTeachers();
      if (!mounted) return;
      setState(() {
        _subjectOptions = subjects;
        _teacherOptions = teachers;
      });
    } catch (e) {
      _toast('Could not load subjects/teachers: $e');
    }
  }

  Future<void> _loadSections() async {
    final repo = _registrarRepo;
    if (repo == null) return;
    try {
      final sections = await repo.fetchSections();
      if (!mounted) return;
      setState(() => _sectionOptions = sections);
    } catch (e) {
      _toast('Could not load sections: $e');
    }
  }

  Future<void> _loadScheduleEntries() async {
    final repo = _registrarRepo;
    if (repo == null) return;
    try {
      final entries = await repo.fetchClassSections();
      if (!mounted) return;
      setState(() => _scheduleEntries = entries);
    } catch (e) {
      _toast('Could not load class schedule: $e');
    }
  }

  /// Persists a new `class_sections` offering from the Class Schedule tab's
  /// "Add Class Schedule" card, then refreshes the table so the new row
  /// shows up immediately. The section/school year/term are the form's own
  /// real values now — see class_schedule_view.dart's Section dropdown and
  /// School Year/Term fields.
  Future<void> _saveClassSchedule({
    required String subjectId,
    required String professorId,
    required String sectionId,
    required String schoolYear,
    required String term,
    required String room,
    required List<String> days,
    required String startTime,
    required String endTime,
  }) async {
    final repo = _registrarRepo;
    if (repo == null) return;
    try {
      await repo.createClassSection(
        subjectId: subjectId,
        sectionId: sectionId,
        professorId: professorId,
        room: room,
        days: days,
        startTime: startTime,
        endTime: endTime,
        schoolYear: schoolYear,
        term: term,
      );
      await _loadScheduleEntries();
      _toast('Class section created.');
    } catch (e) {
      _toast('Could not create class section: $e');
    }
  }

  /// Runs an uploaded Excel schedule export through the import pipeline —
  /// see ScheduleImportRunner. Never rethrows: ClassScheduleView's own
  /// `_handleImportFile` awaits this only to know when to clear its busy
  /// spinner, matching `_saveClassSchedule`'s own catch-and-toast shape.
  Future<void> _handleImportSchedule({
    required Uint8List bytes,
    required String schoolYear,
    required String term,
  }) async {
    final runner = _scheduleImportRunner;
    if (runner == null) return;
    try {
      final summary = await runner.run(
        xlsxBytes: bytes,
        schoolYear: schoolYear,
        term: term,
      );
      await _loadScheduleEntries();
      final parts = [
        '${summary.offeringsCommitted} offering(s) imported',
        if (summary.meetingsCommitted > 0)
          '${summary.meetingsCommitted} meeting(s) scheduled',
        if (summary.errors.isNotEmpty) '${summary.errors.length} skipped',
      ];
      _toast(parts.join(', '));
      if (summary.errors.isNotEmpty && mounted) {
        showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Some rows could not be imported'),
            content: SingleChildScrollView(
              child: Text(summary.errors.join('\n\n')),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      _toast('Could not import schedule file: $e');
    }
  }

  Future<void> _loadGradeRecords() async {
    final repo = _registrarRepo;
    if (repo == null) return;
    try {
      final records = await repo.fetchGradeRecords();
      if (!mounted) return;
      setState(() => _gradeRecords = records);
    } catch (e) {
      _toast('Could not load grades: $e');
    }
  }

  /// Saves every currently-visible grade record (Task 2's saveGrade is an
  /// upsert, so re-saving unchanged rows alongside edited ones is
  /// harmless), then reloads so the table reflects server-confirmed state
  /// (including the freshly-recomputed GradeRemark for anything that just
  /// crossed a threshold).
  Future<void> _saveGradeChanges(List<GradeRecordModel> records) async {
    final repo = _registrarRepo;
    if (repo == null) return;
    try {
      for (final record in records) {
        final parts = record.id.split('|');
        if (parts.length != 2) continue;
        await repo.saveGrade(
          studentId: parts[0],
          classSectionId: parts[1],
          grade: record.grade,
        );
      }
      await _loadGradeRecords();
      _toast('Grade changes saved.');
    } catch (e) {
      _toast('Could not save grade changes: $e');
    }
  }

  /// Bulk-enrolls a `class_sections` offering's home section into it (see
  /// RegistrarRepository.enrollSectionStudents), from the Class Schedule
  /// tab's "Enroll this section's students" row action.
  Future<void> _enrollSection(String classSectionId) async {
    final repo = _registrarRepo;
    if (repo == null) return;
    try {
      final count = await repo.enrollSectionStudents(classSectionId);
      _toast('$count student(s) enrolled.');
    } catch (e) {
      _toast('Enrollment failed: $e');
    }
  }

  Future<void> _loadMyRfidRequests() async {
    final repo = _rfidRequestsRepo;
    if (repo == null) return;
    try {
      final requests = await repo.fetchMyRequests(_effectiveRegistrarId);
      if (!mounted) return;
      setState(() {
        _myRfidRequests = requests
            .map((r) => RfidNotificationLogModel(
                  studentName: r.studentName,
                  studentId: r.studentNumber,
                  section: r.section,
                ))
            .toList();
      });
    } catch (e) {
      _toast('Could not load RFID request history: $e');
    }
  }

  Future<void> _submitRfidNotifications(List<String> studentIds) async {
    final repo = _rfidRequestsRepo;
    if (repo == null) return;
    try {
      final count = await repo.notifyRfidMissing(
        studentIds: studentIds,
        registrarId: _effectiveRegistrarId,
      );
      await _loadMyRfidRequests();
      _toast(
        count > 0
            ? 'RFID assignment notice sent for $count student(s).'
            : 'Selected student(s) already have a pending request.',
      );
    } catch (e) {
      _toast('Could not send RFID notice: $e');
    }
  }

  /// Live-refreshes Overview/Student Records/RFID Management when the
  /// underlying `students` table changes elsewhere (e.g. a new
  /// registration, an RFID card getting linked).
  void _subscribeToStudentChanges() {
    if (!AppEnv.supabaseConfigured) return;
    _studentsChannel = Supabase.instance.client
        .channel('public:students:registrar')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'students',
          callback: (_) => _scheduleStudentsReload(),
        )
        .subscribe();
  }

  void _scheduleStudentsReload() {
    _studentsReloadDebounce?.cancel();
    _studentsReloadDebounce =
        Timer(const Duration(milliseconds: 500), _loadStudents);
  }

  String? get _notifiableUserId {
    final id = widget.registrarProfileId;
    if (id == null || id.startsWith('u_')) return null;
    return id;
  }

  Future<void> _loadNotifications() async {
    final notifications = await _notifRepo?.fetchForRole(
      AppRole.registrar,
      userId: _notifiableUserId,
    );
    if (!mounted || notifications == null) return;
    setState(() => _notifications = notifications);
  }

  Future<void> _markNotificationsRead() async {
    final repo = _notifRepo;
    if (repo == null) return;
    await repo.markAllReadForRole(AppRole.registrar, userId: _notifiableUserId);
  }

  Future<void> _reportTechnicalIssue({
    required ReportTechnicalIssueCategory category,
    required String description,
    String? location,
  }) async {
    final repo = _issuesRepo;
    if (repo == null) return;
    await repo.report(
      category: _mapCategory(category),
      description: description,
      location: location,
      reporterId: widget.registrarProfileId ?? 'unknown',
      reporterRole: 'Registrar',
    );
  }

  TechnicalIssueCategory _mapCategory(ReportTechnicalIssueCategory category) {
    switch (category) {
      case ReportTechnicalIssueCategory.offlineDevice:
        return TechnicalIssueCategory.offlineDevice;
      case ReportTechnicalIssueCategory.offlineKiosk:
        return TechnicalIssueCategory.offlineKiosk;
      case ReportTechnicalIssueCategory.classroomPc:
        return TechnicalIssueCategory.classroomPc;
      case ReportTechnicalIssueCategory.other:
        return TechnicalIssueCategory.other;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadNotifications());
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadStudents());
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _loadClassScheduleOptions());
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSections());
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadScheduleEntries());
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadGradeRecords());
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _loadMyRfidRequests());
    _subscribeToNotificationChanges();
    _subscribeToStudentChanges();
  }

  /// Live-refreshes the bell when a new notification lands for this
  /// dashboard. Requires `notifications` to be in the `supabase_realtime`
  /// publication (see supabase/add_notifications_schema.sql).
  void _subscribeToNotificationChanges() {
    if (!AppEnv.supabaseConfigured) return;
    _notificationsChannel = Supabase.instance.client
        .channel('public:notifications:registrar')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'notifications',
          callback: (_) {
            _reloadDebounce?.cancel();
            _reloadDebounce =
                Timer(const Duration(milliseconds: 400), _loadNotifications);
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    _reloadDebounce?.cancel();
    _studentsReloadDebounce?.cancel();
    final channel = _notificationsChannel;
    if (channel != null) {
      Supabase.instance.client.removeChannel(channel);
    }
    final studentsChannel = _studentsChannel;
    if (studentsChannel != null) {
      Supabase.instance.client.removeChannel(studentsChannel);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _students == null) {
      return DashboardSkeletonScreen(
        useScaffold: false,
        backgroundColor: RegistrarColors.background(context),
        cardColor: RegistrarColors.card(context),
        cardBorderColor: RegistrarColors.cardBorder(context),
        placeholderColor: RegistrarColors.gray,
      );
    }

    if (_error != null && _students == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: _loadStudents, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    return RegistrarDashboardPage(
      registrarName: widget.registrarName ?? 'Juan Dela Cruz',
      onReturnToHub: widget.onReturnToHub,
      onSignOut: widget.onSignOut,
      initialStudents: _students,
      initialOverviewStats: _overviewStats,
      initialScheduleEntries: _scheduleEntries,
      initialSubjectOptions: _subjectOptions,
      initialTeacherOptions: _teacherOptions,
      initialSectionOptions: _sectionOptions,
      initialGradeRecords: _gradeRecords,
      initialNotifications: _notifications,
      onMarkNotificationsRead:
          _notifRepo == null ? null : _markNotificationsRead,
      onReportTechnicalIssue:
          _issuesRepo == null ? null : _reportTechnicalIssue,
      onAddStudent: _studentsRepo == null ? null : _addStudent,
      onSaveClassSchedule: _registrarRepo == null ? null : _saveClassSchedule,
      onImportSchedule:
          _scheduleImportRunner == null ? null : _handleImportSchedule,
      onSaveGradeChanges: _registrarRepo == null ? null : _saveGradeChanges,
      onEnrollSection: _registrarRepo == null ? null : _enrollSection,
      initialRfidNotificationLogs: _myRfidRequests,
      onSubmitNotify:
          _rfidRequestsRepo == null ? null : _submitRfidNotifications,
    );
  }
}
