import 'dart:async';

import 'package:dashboard_layout/dashboard_layout.dart'
    show ReportTechnicalIssueCategory;
import 'package:discipline_officer_module/discipline_officer_module.dart'
    show NotificationItemModel;
import 'package:flutter/material.dart';
import 'package:professor_module/pages/dashboard/conduct_report_view.dart';
import 'package:professor_module/professor_module.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/app_role.dart';
import '../data/audit_logger.dart';
import '../data/notifications_repository.dart';
import '../data/professor_repository.dart';
import '../data/technical_issues_repository.dart';
import '../env.dart';

/// Wires [ProfessorDashboardPage] to Supabase via [ProfessorRepository] —
/// the professor's assigned sections, attendance (summary + Take
/// Attendance), and Conduct Report tab (which reuses `student_violations` /
/// `handbook_offenses`, exactly like the Discipline Officer dashboard) all
/// come from real tables.
///
/// Falls back to the page's own built-in demo data when Supabase isn't
/// configured, so this still renders something reasonable in that case.
class ProfessorConnectedPage extends StatefulWidget {
  const ProfessorConnectedPage({
    super.key,
    this.professorName,
    this.professorProfileId,
    this.onReturnToHub,
    this.onSignOut,
  });

  final String? professorName;

  /// The signed-in user's `profiles.id`. Real Microsoft-authenticated
  /// Teacher accounts pass their actual id; the static `teacher.demo`
  /// account (lib/auth/static_demo_accounts.dart) has no real Supabase Auth
  /// identity, so this falls back to a fixed seeded demo profile instead
  /// (see [_demoProfessorProfileId]).
  final String? professorProfileId;

  final VoidCallback? onReturnToHub;
  final VoidCallback? onSignOut;

  @override
  State<ProfessorConnectedPage> createState() =>
      _ProfessorConnectedPageState();
}

class _ProfessorConnectedPageState extends State<ProfessorConnectedPage> {
  bool _loading = true;
  String? _error;

  List<ProfessorSectionModel>? _sections;
  AttendanceSummaryModel? _attendanceSummary;
  List<StudentAttendanceRecordModel>? _studentAttendance;
  List<AttendanceCellModel>? _attendanceCells;
  List<ConductStudentModel>? _conductStudents;
  List<ConductViolationOption>? _offenseOptions;
  List<NotificationItemModel>? _notifications;

  RealtimeChannel? _notificationsChannel;
  Timer? _reloadDebounce;

  /// Matches the fixed profile seeded by
  /// supabase/add_professor_module_schema.sql — keep the two in sync if it
  /// ever changes. Static demo account ids all use the `u_` prefix (see
  /// SessionController.canVerifyPassword), which is how this tells "demo
  /// account, no real profile row" apart from a real Supabase Auth UUID.
  static const _demoProfessorProfileId =
      '00000000-0000-4000-8000-000000000002';

  String get _effectiveProfessorId {
    final id = widget.professorProfileId;
    if (id == null || id.startsWith('u_')) return _demoProfessorProfileId;
    return id;
  }

  ProfessorRepository? get _repo {
    if (!AppEnv.supabaseConfigured) return null;
    return ProfessorRepository(Supabase.instance.client);
  }

  NotificationsRepository? get _notifRepo {
    if (!AppEnv.supabaseConfigured) return null;
    return NotificationsRepository(Supabase.instance.client);
  }

  TechnicalIssuesRepository? get _issuesRepo {
    if (!AppEnv.supabaseConfigured) return null;
    return TechnicalIssuesRepository(Supabase.instance.client);
  }

  AuditLogger? get _auditLogger {
    if (!AppEnv.supabaseConfigured) return null;
    return AuditLogger(
      Supabase.instance.client,
      // The Teacher role has no "demo vs real" ambiguity to resolve here
      // the way DisciplineOfficerConnectedPage does — _effectiveProfessorId
      // already picks the right id for either case.
      actorId: _effectiveProfessorId,
      actorEmail: widget.professorName ?? 'Faculty Member',
      actorRole: AppRole.teacher,
    );
  }

  Future<void> _load() async {
    final repo = _repo;
    if (repo == null) {
      setState(() => _loading = false);
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final sections = await repo.fetchAssignedSections(_effectiveProfessorId);
      final conductStudents = await repo.fetchConductStudentsForSections(
        sections.map((s) => s.id).toList(),
      );
      final offenseOptions = await repo.fetchOffenseOptions();
      final notifications = await _notifRepo?.fetchForRole(
        AppRole.teacher,
        userId: _effectiveProfessorId,
      );

      AttendanceSummaryModel? summary;
      List<StudentAttendanceRecordModel>? attendance;
      List<AttendanceCellModel>? cells;
      if (sections.isNotEmpty) {
        summary = await repo.fetchAttendanceSummary(sections.first.id);
        attendance = await repo.fetchStudentAttendance(sections.first.id);
        cells = await repo.fetchAttendanceCells(sections.first.id);
      }

      if (!mounted) return;
      setState(() {
        _sections = sections;
        _attendanceSummary = summary;
        _studentAttendance = attendance;
        _attendanceCells = cells;
        _conductStudents = conductStudents;
        _offenseOptions = offenseOptions;
        if (notifications != null) _notifications = notifications;
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not load professor data: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _onSectionSelected(ProfessorSectionModel section) async {
    final repo = _repo;
    if (repo == null) return;
    try {
      final summary = await repo.fetchAttendanceSummary(section.id);
      final attendance = await repo.fetchStudentAttendance(section.id);
      final cells = await repo.fetchAttendanceCells(section.id);
      if (!mounted) return;
      setState(() {
        _attendanceSummary = summary;
        _studentAttendance = attendance;
        _attendanceCells = cells;
      });
    } catch (e) {
      debugPrint('Could not load attendance for ${section.name}: $e');
    }
  }

  Future<void> _submitAttendance(
    ProfessorSectionModel section,
    DateTime date,
    Map<String, String> statusByStudentId,
  ) async {
    final repo = _repo;
    if (repo == null) return;
    await repo.submitAttendance(
      section.id,
      statusByStudentId,
      recordedBy: _effectiveProfessorId,
      date: date,
    );
    await _auditLogger?.log(
      action: 'Took attendance for ${section.name}',
      recordId: section.id,
    );
    // Refresh so the just-submitted numbers show up immediately rather than
    // waiting for the next section switch.
    await _onSectionSelected(section);
  }

  Future<void> _submitConductReport(ConductReportSubmission submission) async {
    final repo = _repo;
    if (repo == null) return;
    await repo.submitConductReport(submission, reportedBy: _effectiveProfessorId);
    await _auditLogger?.log(
      action: 'Filed conduct report',
      recordId: submission.studentId,
    );
  }

  Future<void> _markNotificationsRead() async {
    final repo = _notifRepo;
    if (repo == null) return;
    await repo.markAllReadForRole(
      AppRole.teacher,
      userId: _effectiveProfessorId,
    );
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
      reporterId: _effectiveProfessorId,
      reporterRole: 'Teacher',
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    _subscribeToNotificationChanges();
  }

  /// Live-refreshes the bell when a new notification lands for this
  /// dashboard. Requires `notifications` to be in the `supabase_realtime`
  /// publication (see supabase/add_notifications_schema.sql).
  void _subscribeToNotificationChanges() {
    if (!AppEnv.supabaseConfigured) return;
    _notificationsChannel = Supabase.instance.client
        .channel('public:notifications:teacher')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'notifications',
          callback: (_) {
            _reloadDebounce?.cancel();
            _reloadDebounce =
                Timer(const Duration(milliseconds: 400), _reloadNotifications);
          },
        )
        .subscribe();
  }

  /// Refetches only the bell's notifications — deliberately not [_load],
  /// which would flash the whole dashboard back to its loading spinner just
  /// because a notification arrived elsewhere.
  Future<void> _reloadNotifications() async {
    if (!mounted) return;
    final notifications = await _notifRepo?.fetchForRole(
      AppRole.teacher,
      userId: _effectiveProfessorId,
    );
    if (!mounted || notifications == null) return;
    setState(() => _notifications = notifications);
  }

  @override
  void dispose() {
    _reloadDebounce?.cancel();
    final channel = _notificationsChannel;
    if (channel != null) {
      Supabase.instance.client.removeChannel(channel);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton(onPressed: _load, child: const Text('Retry')),
              ],
            ),
          ),
        ),
      );
    }

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final repo = _repo;
    return ProfessorDashboardPage(
      professorName: widget.professorName ?? 'Juan Dela Cruz',
      onReturnToHub: widget.onReturnToHub,
      onSignOut: widget.onSignOut,
      initialSections: _sections,
      initialAttendanceSummary: _attendanceSummary,
      initialStudentAttendance: _studentAttendance,
      initialAttendanceCells: _attendanceCells,
      onSectionSelected: repo == null ? null : _onSectionSelected,
      onSubmitAttendance: repo == null ? null : _submitAttendance,
      initialConductStudents: _conductStudents,
      initialViolationOptions: _offenseOptions,
      onSubmitConductReport: repo == null ? null : _submitConductReport,
      initialNotifications: _notifications,
      onMarkNotificationsRead:
          _notifRepo == null ? null : _markNotificationsRead,
      onReportTechnicalIssue: _issuesRepo == null ? null : _reportTechnicalIssue,
    );
  }
}
