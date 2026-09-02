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
import '../data/technical_issues_repository.dart';
import '../env.dart';

/// Wires [RegistrarDashboardPage] into the app's navigation. Overview,
/// Student Records, and RFID Management are real (via [RegistrarRepository]
/// — `students`/`profiles`/`sections`); Grades and Class Schedule still run
/// on the dashboard's own built-in mock data since there's no
/// `grade_records`/`class_schedules` table yet (a bigger schema piece,
/// tracked separately). The shared notification bell and Report Technical
/// Issue action reuse the same [NotificationsRepository]/
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
      initialNotifications: _notifications,
      onMarkNotificationsRead:
          _notifRepo == null ? null : _markNotificationsRead,
      onReportTechnicalIssue:
          _issuesRepo == null ? null : _reportTechnicalIssue,
    );
  }
}
