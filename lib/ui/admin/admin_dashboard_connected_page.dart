import 'dart:async';

import 'package:admin_dashboard/admin_dashboard.dart';
import 'package:discipline_officer_module/discipline_officer_module.dart'
    show NotificationItemModel;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../auth/app_role.dart';
import '../../auth/app_user.dart';
import '../../data/admin_approval_repository.dart';
import '../../data/audit_logger.dart';
import '../../data/notifications_repository.dart';
import '../../env.dart';

/// Wires [AdminDashboardPage]'s notification bell to the centralized
/// `notifications` table — the one piece of the Admin Dashboard shell that
/// needs a stateful host wrapper (every other page's live data comes in via
/// the `*PageBuilder` props already threaded straight from
/// `AdminHubPage`, none of which need realtime/lifecycle management here).
class AdminDashboardConnectedPage extends StatefulWidget {
  const AdminDashboardConnectedPage({
    super.key,
    this.currentUser,
    this.onReturnToHub,
    this.onSignOut,
    this.systemOverviewPageBuilder,
    this.staffAccountsPageBuilder,
    this.rfidMappingPageBuilder,
    this.studentDirectoryPageBuilder,
    this.mlThresholdsPageBuilder,
    this.registerSyncsPageBuilder,
    this.reportsExportsPageBuilder,
    this.auditLogsPageBuilder,
  });

  /// The signed-in Admin — used to attribute audit log entries (see
  /// [AuditLogger]) to whoever actually performed the action.
  final AppUser? currentUser;

  final VoidCallback? onReturnToHub;
  final VoidCallback? onSignOut;
  final WidgetBuilder? systemOverviewPageBuilder;
  final WidgetBuilder? staffAccountsPageBuilder;
  final WidgetBuilder? rfidMappingPageBuilder;
  final WidgetBuilder? studentDirectoryPageBuilder;
  final WidgetBuilder? mlThresholdsPageBuilder;
  final WidgetBuilder? registerSyncsPageBuilder;
  final WidgetBuilder? reportsExportsPageBuilder;
  final WidgetBuilder? auditLogsPageBuilder;

  @override
  State<AdminDashboardConnectedPage> createState() =>
      _AdminDashboardConnectedPageState();
}

class _AdminDashboardConnectedPageState
    extends State<AdminDashboardConnectedPage> {
  List<NotificationItemModel>? _notifications;
  List<NotificationRecipient> _staffDirectory = const [];
  RealtimeChannel? _notificationsChannel;
  Timer? _reloadDebounce;

  NotificationsRepository? get _notifRepo {
    if (!AppEnv.supabaseConfigured) return null;
    return NotificationsRepository(Supabase.instance.client);
  }

  AdminApprovalRepository? get _approvalRepo {
    if (!AppEnv.supabaseConfigured) return null;
    return AdminApprovalRepository(Supabase.instance.client);
  }

  AuditLogger? get _auditLogger {
    final user = widget.currentUser;
    if (!AppEnv.supabaseConfigured || user == null) return null;
    return AuditLogger(
      Supabase.instance.client,
      actorId: user.id.startsWith('u_') ? null : user.id,
      actorEmail: user.username,
      actorRole: user.role,
    );
  }

  /// A real Supabase Auth id safe to filter `notifications.user_id` (a uuid
  /// column) by — `null` for the static demo accounts
  /// (lib/auth/static_demo_accounts.dart), whose ids like "u_admin" aren't
  /// valid UUIDs and have no real `profiles` row to match anyway (same
  /// fallback [_auditLogger] already uses for `actorId`).
  String? get _notifiableUserId {
    final id = widget.currentUser?.id;
    if (id == null || id.startsWith('u_')) return null;
    return id;
  }

  Future<void> _loadNotifications() async {
    final notifications = await _notifRepo?.fetchForRole(
      AppRole.administrator,
      userId: _notifiableUserId,
    );
    if (!mounted || notifications == null) return;
    setState(() => _notifications = notifications);
  }

  /// Populates the "Specific user" picker on the Notifications page's
  /// compose dialog — the same approved-staff roster the Staff Accounts
  /// page shows, reused here rather than a second query.
  Future<void> _loadStaffDirectory() async {
    final roster = await _approvalRepo?.fetchApprovedStaffRoster();
    if (!mounted || roster == null) return;
    setState(() {
      _staffDirectory = roster
          .where((s) => s.role != null)
          .map((s) => NotificationRecipient(
                id: s.id,
                name: s.fullName,
                roleLabel: s.role!.displayName,
              ))
          .toList();
    });
  }

  Future<void> _markNotificationsRead() async {
    final repo = _notifRepo;
    if (repo == null) return;
    await repo.markAllReadForRole(
      AppRole.administrator,
      userId: _notifiableUserId,
    );
  }

  /// Which dashboard each "Automated Trigger Rule" (see
  /// notificationTriggers in the admin_dashboard package) broadcasts to by
  /// default — the only app-specific piece the Notifications page's button
  /// needs, since that package has no knowledge of [AppRole]. Overridden per
  /// send when the compose dialog picks a specific user instead (see
  /// [NotificationSendRequest.targetRoleLabel]).
  static const _triggerTargetRoles = {
    'earlyWarningFlag': AppRole.guidanceCounselor,
    'absenceThresholdReached': AppRole.disciplineOfficer,
    'violationCountExceeded': AppRole.disciplineOfficer,
    'newDisciplineCaseFiled': AppRole.administrator,
    'dailyAttendanceSummary': AppRole.teacher,
    'rfidGatewayOffline': AppRole.administrator,
    'mlModelRetrained': AppRole.administrator,
  };

  AppRole? _roleFromLabel(String label) {
    for (final role in AppRole.values) {
      if (role.displayName == label) return role;
    }
    return null;
  }

  Future<void> _sendComposedNotification(
    String triggerId,
    NotificationSendRequest request,
  ) async {
    final repo = _notifRepo;
    if (repo == null) return;
    final targetRole = (request.targetRoleLabel != null
            ? _roleFromLabel(request.targetRoleLabel!)
            : null) ??
        _triggerTargetRoles[triggerId];
    if (targetRole == null) return;

    await repo.send(
      targetRole: targetRole,
      title: request.title,
      message: request.message,
      targetUserId: request.targetUserId,
    );

    var destination = notificationTriggers
        .firstWhere((t) => t.id == triggerId)
        .targetDashboard;
    if (request.targetUserId != null) {
      for (final recipient in _staffDirectory) {
        if (recipient.id == request.targetUserId) {
          destination = recipient.name;
          break;
        }
      }
    }
    await _auditLogger?.log(
      action: 'Sent notification "${request.title}" to $destination',
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadNotifications();
      _loadStaffDirectory();
    });
    _subscribeToNotificationChanges();
  }

  /// Live-refreshes the bell when a new notification lands for Admin.
  /// Requires `notifications` to be in the `supabase_realtime` publication
  /// (see supabase/add_notifications_schema.sql).
  void _subscribeToNotificationChanges() {
    if (!AppEnv.supabaseConfigured) return;
    _notificationsChannel = Supabase.instance.client
        .channel('public:notifications:admin')
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
    return AdminDashboardPage(
      onReturnToHub: widget.onReturnToHub,
      onSignOut: widget.onSignOut,
      userName: widget.currentUser?.displayName,
      userEmail: widget.currentUser?.username,
      systemOverviewPageBuilder: widget.systemOverviewPageBuilder,
      staffAccountsPageBuilder: widget.staffAccountsPageBuilder,
      rfidMappingPageBuilder: widget.rfidMappingPageBuilder,
      studentDirectoryPageBuilder: widget.studentDirectoryPageBuilder,
      mlThresholdsPageBuilder: widget.mlThresholdsPageBuilder,
      registerSyncsPageBuilder: widget.registerSyncsPageBuilder,
      reportsExportsPageBuilder: widget.reportsExportsPageBuilder,
      auditLogsPageBuilder: widget.auditLogsPageBuilder,
      notificationsPageBuilder: (_) => NotificationsPage(
        onSend: _notifRepo == null ? null : _sendComposedNotification,
        staffDirectory: _staffDirectory,
      ),
      initialNotifications: _notifications,
      onMarkNotificationsRead:
          _notifRepo == null ? null : _markNotificationsRead,
    );
  }
}
