import 'package:flutter/material.dart';

import 'layout/dashboard_shell.dart';

/// Admin Dashboard shell from the Capstone UI repository
/// (CipherPunk-7800/Capstone-Project, `Admin Dashboard/`).
class AdminDashboardPage extends StatelessWidget {
  const AdminDashboardPage({super.key, this.onReturnToHub});

  final VoidCallback? onReturnToHub;

  @override
  Widget build(BuildContext context) {
    return DashboardShell(onReturnToHub: onReturnToHub);
  }
}
