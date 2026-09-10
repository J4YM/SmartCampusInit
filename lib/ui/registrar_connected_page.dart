import 'dart:async';

import 'package:dashboard_layout/dashboard_layout.dart'
    show ReportTechnicalIssueCategory;
import 'package:discipline_officer_module/discipline_officer_module.dart'
    show NotificationItemModel;
import 'package:flutter/material.dart';
import 'package:registrar_module/registrar_module.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/app_role.dart';
import '../data/notifications_repository.dart';
import '../data/registrar_repository.dart';
import '../data/students_repository.dart';
import '../data/technical_issues_repository.dart';
import '../env.dart';

/// Wires [RegistrarDashboardPage] into the app's navigation. Overview,
/// Student Records, RFID Management, and Class Schedule are real (via
/// [RegistrarRepository] — `students`/`profiles`/`sections`/`subjects`/
/// `class_sections`); Grades still runs on the dashboard's own built-in
/// mock data since there's no `grade_records` table yet (a bigger schema
/// piece, tracked separately). The shared notification bell and Report
/// Technical Issue action reuse the same [NotificationsRepository]/
/// [TechnicalIssuesRepository] every other dashboard already uses.
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

  StudentsRepository? get _studentsRepo {
    if (!AppEnv.supabaseConfigured) return null;
    return StudentsRepository(Supabase.instance.client);
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

  /// School year label (e.g. `2026-2027`) for a newly [createClassSection]d
  /// row — the Class Schedule form has no School Year field yet, so this
  /// derives it from today's date the way registrars conventionally do
  /// (new school year starts in June).
  String _currentSchoolYear() {
    final now = DateTime.now();
    final startYear = now.month >= 6 ? now.year : now.year - 1;
    return '$startYear-${startYear + 1}';
  }

  /// Term for every newly created `class_sections` row — the Class
  /// Schedule form has no Term field yet, same reason [_saveClassSchedule]
  /// falls back to [RegistrarRepository.fetchDefaultSection] for the
  /// section. Named here so the success toast can quote the exact value
  /// used rather than the save silently picking one.
  static const _defaultTerm = '1st Semester';

  /// Persists a new `class_sections` offering from the Class Schedule tab's
  /// "Add Class Schedule" card, then refreshes the table so the new row
  /// shows up immediately. Since the form doesn't yet collect a real
  /// section (see class_schedule_view.dart's Education Level/Year
  /// Level/Section captions), this always saves against
  /// [RegistrarRepository.fetchDefaultSection]'s pick — the success toast
  /// names exactly which section and term were used so that's never a
  /// silent, undetectable write.
  Future<void> _saveClassSchedule({
    required String subjectId,
    required String professorId,
    required String room,
    required List<String> days,
    required String startTime,
    required String endTime,
  }) async {
    final repo = _registrarRepo;
    if (repo == null) return;
    try {
      final section = await repo.fetchDefaultSection();
      if (section == null) {
        _toast(
          'Could not create class section: no sections exist yet. Add a '
          'section before creating a class schedule.',
        );
        return;
      }
      await repo.createClassSection(
        subjectId: subjectId,
        sectionId: section.id,
        professorId: professorId,
        room: room,
        days: days,
        startTime: startTime,
        endTime: endTime,
        schoolYear: _currentSchoolYear(),
        term: _defaultTerm,
      );
      await _loadScheduleEntries();
      _toast(
        'Class section created (Section: ${section.name}, Term: $_defaultTerm).',
      );
    } catch (e) {
      _toast('Could not create class section: $e');
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadScheduleEntries());
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
      return const Center(child: CircularProgressIndicator());
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
      initialNotifications: _notifications,
      onMarkNotificationsRead:
          _notifRepo == null ? null : _markNotificationsRead,
      onReportTechnicalIssue:
          _issuesRepo == null ? null : _reportTechnicalIssue,
      onAddStudent: _studentsRepo == null ? null : _addStudent,
      onSaveClassSchedule: _registrarRepo == null ? null : _saveClassSchedule,
      onEnrollSection: _registrarRepo == null ? null : _enrollSection,
    );
  }
}
