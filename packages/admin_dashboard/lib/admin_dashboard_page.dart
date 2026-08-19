import 'package:discipline_officer_module/discipline_officer_module.dart'
    show NotificationItemModel;
import 'package:flutter/material.dart';

import 'layout/dashboard_shell.dart';

/// Admin Dashboard shell from the Capstone UI repository
/// (CipherPunk-7800/Capstone-Project, `Admin Dashboard/`).
class AdminDashboardPage extends StatelessWidget {
  const AdminDashboardPage({
    super.key,
    this.onReturnToHub,
    this.onSignOut,
    this.systemOverviewPageBuilder,
    this.staffAccountsPageBuilder,
    this.rfidMappingPageBuilder,
    this.studentDirectoryPageBuilder,
    this.mlThresholdsPageBuilder,
    this.notificationsPageBuilder,
    this.registerSyncsPageBuilder,
    this.reportsExportsPageBuilder,
    this.auditLogsPageBuilder,
    this.initialNotifications,
    this.onMarkNotificationsRead,
  });

  final VoidCallback? onReturnToHub;

  /// Invoked (after the sidebar's Logout confirmation) to perform a real
  /// sign-out. See [DashboardShell.onSignOut].
  final VoidCallback? onSignOut;

  /// Supplies a live-data System Overview page. Falls back to
  /// [SystemOverviewPage.empty] when omitted.
  final WidgetBuilder? systemOverviewPageBuilder;

  /// Supplies a live-data Staff Accounts page (e.g. wired to Supabase from
  /// the host app). Falls back to [StaffAccountsPage.empty] when omitted, so
  /// this package stays independently runnable/demoable without a backend.
  final WidgetBuilder? staffAccountsPageBuilder;

  /// Supplies a live-data RFID Mapping page. Falls back to
  /// [RfidMappingPage.empty] when omitted.
  final WidgetBuilder? rfidMappingPageBuilder;

  /// Supplies a live-data Student Directory page. Falls back to
  /// [StudentDirectoryPage.empty] when omitted.
  final WidgetBuilder? studentDirectoryPageBuilder;

  /// Supplies a live-data ML & Thresholds page. Falls back to
  /// [MlThresholdsPage.empty] when omitted.
  final WidgetBuilder? mlThresholdsPageBuilder;
  final WidgetBuilder? notificationsPageBuilder;
  final WidgetBuilder? registerSyncsPageBuilder;
  final WidgetBuilder? reportsExportsPageBuilder;
  final WidgetBuilder? auditLogsPageBuilder;

  /// Admin's own notification bell (top of the sidebar). Falls back to an
  /// empty bell when omitted (demo behavior).
  final List<NotificationItemModel>? initialNotifications;

  /// Marks every currently-unread notification read — invoked by the bell's
  /// "View all notifications" action.
  final Future<void> Function()? onMarkNotificationsRead;

  @override
  Widget build(BuildContext context) {
    return DashboardShell(
      onReturnToHub: onReturnToHub,
      onSignOut: onSignOut,
      systemOverviewPageBuilder: systemOverviewPageBuilder,
      staffAccountsPageBuilder: staffAccountsPageBuilder,
      rfidMappingPageBuilder: rfidMappingPageBuilder,
      studentDirectoryPageBuilder: studentDirectoryPageBuilder,
      mlThresholdsPageBuilder: mlThresholdsPageBuilder,
      notificationsPageBuilder: notificationsPageBuilder,
      registerSyncsPageBuilder: registerSyncsPageBuilder,
      reportsExportsPageBuilder: reportsExportsPageBuilder,
      auditLogsPageBuilder: auditLogsPageBuilder,
      initialNotifications: initialNotifications,
      onMarkNotificationsRead: onMarkNotificationsRead,
    );
  }
}
