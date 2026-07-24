import 'package:flutter/material.dart';

import 'layout/dashboard_shell.dart';

/// Admin Dashboard shell from the Capstone UI repository
/// (CipherPunk-7800/Capstone-Project, `Admin Dashboard/`).
class AdminDashboardPage extends StatelessWidget {
  const AdminDashboardPage({
    super.key,
    this.onReturnToHub,
    this.staffAccountsPageBuilder,
    this.rfidMappingPageBuilder,
    this.studentDirectoryPageBuilder,
  });

  final VoidCallback? onReturnToHub;

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

  @override
  Widget build(BuildContext context) {
    return DashboardShell(
      onReturnToHub: onReturnToHub,
      staffAccountsPageBuilder: staffAccountsPageBuilder,
      rfidMappingPageBuilder: rfidMappingPageBuilder,
      studentDirectoryPageBuilder: studentDirectoryPageBuilder,
    );
  }
}
