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
import '../data/technical_issues_repository.dart';
import '../env.dart';

/// Wires [RegistrarDashboardPage] into the app's navigation. No
/// Registrar-specific Supabase tables exist yet, so the dashboard itself
/// still runs on its own built-in mock data — but the shared notification
/// bell and Report Technical Issue action are real, reusing the same
/// [NotificationsRepository]/[TechnicalIssuesRepository] every other
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

  RealtimeChannel? _notificationsChannel;
  Timer? _reloadDebounce;

  NotificationsRepository? get _notifRepo {
    if (!AppEnv.supabaseConfigured) return null;
    return NotificationsRepository(Supabase.instance.client);
  }

  TechnicalIssuesRepository? get _issuesRepo {
    if (!AppEnv.supabaseConfigured) return null;
    return TechnicalIssuesRepository(Supabase.instance.client);
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
    _subscribeToNotificationChanges();
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
    final channel = _notificationsChannel;
    if (channel != null) {
      Supabase.instance.client.removeChannel(channel);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RegistrarDashboardPage(
      registrarName: widget.registrarName ?? 'Juan Dela Cruz',
      onReturnToHub: widget.onReturnToHub,
      onSignOut: widget.onSignOut,
      initialNotifications: _notifications,
      onMarkNotificationsRead:
          _notifRepo == null ? null : _markNotificationsRead,
      onReportTechnicalIssue:
          _issuesRepo == null ? null : _reportTechnicalIssue,
    );
  }
}
