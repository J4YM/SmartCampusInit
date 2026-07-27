import 'package:admin_dashboard/admin_dashboard.dart';
import 'package:discipline_officer_module/discipline_officer_module.dart';
import 'package:flutter/material.dart';
import 'package:guidance_counselor_module/pages/dashboard/guidance_counselor_dashboard_page.dart';
import '../../kiosk/capstone_kiosk_scan_host.dart';
import '../../admin/admin_module_scope.dart';
import '../../app/session_controller.dart';
import '../../auth/app_role.dart';
import '../../auth/static_demo_accounts.dart';
import '../../modules/module_access.dart';
import '../../modules/system_module_id.dart';
import '../dashboard_page.dart';
import 'module_placeholder_page.dart';
import 'rfid_mapping_connected_page.dart';
import 'staff_accounts_connected_page.dart';
import 'student_directory_connected_page.dart';

/// Central shell after authentication. Opens live modules or placeholders.
class AdminHubPage extends StatelessWidget {
  const AdminHubPage({super.key, required this.session});

  final SessionController session;

  void _confirmLogout(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return LogoutConfirmationDialog(
          onCancel: () => Navigator.of(dialogContext).pop(),
          onConfirm: () {
            Navigator.of(dialogContext).pop();
            session.signOut();
          },
        );
      },
    );
  }

  void _openModule(BuildContext context, SystemModuleId id) {
    final user = session.user;
    if (user == null) return;
    if (!ModuleAccess.canSeeModule(user.role, id)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${user.role.displayName} accounts cannot open "${id.title}" in this demo.',
          ),
        ),
      );
      return;
    }

    switch (id) {
      case SystemModuleId.rfidManagement:
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (routeContext) => DashboardPage(
              onReturnToHub: () => Navigator.of(routeContext).pop(),
            ),
          ),
        );
        return;
      case SystemModuleId.virtualAdmissionKiosk:
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const CapstoneKioskScanHost(embedFromHub: true),
          ),
        );
        return;
      case SystemModuleId.adminOverview:
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (routeContext) => AdminDashboardPage(
              onReturnToHub: () => Navigator.of(routeContext).pop(),
              onSignOut: () {
                Navigator.of(routeContext).pop();
                session.signOut();
              },
              staffAccountsPageBuilder: (_) => const StaffAccountsConnectedPage(),
              rfidMappingPageBuilder: (_) => const RfidMappingConnectedPage(),
              studentDirectoryPageBuilder: (_) => const StudentDirectoryConnectedPage(),
            ),
          ),
        );
        return;
      case SystemModuleId.doDashboard:
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (routeContext) => DisciplineOfficerDashboardPage(
              onReturnToHub: () => Navigator.of(routeContext).pop(),
            ),
          ),
        );
        return;
      case SystemModuleId.guidanceCounselor:
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (routeContext) => GuidanceCounselorDashboard(
              onReturnToHub: () => Navigator.of(routeContext).pop(),
            ),
          ),
        );
        return;
      default:
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ModulePlaceholderPage(
              moduleId: id,
              bulletPoints: AdminModuleScope.bulletsFor(id),
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = session.user!;
    final theme = Theme.of(context);

    final modules = SystemModuleId.values.where((m) {
      return ModuleAccess.canSeeModule(user.role, m);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('STI Baliuag — Integrated Admin Hub'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(
              child: Text(
                user.displayName,
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ),
          TextButton(
            onPressed: () => _confirmLogout(context),
            child: const Text('Sign out'),
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Welcome, ${user.displayName}',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Role: ${user.role.displayName}. '
                    'Choose a module to continue. Static demo auth is active; '
                    'Supabase JWT from the project scope will replace this flow.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF6B7280),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    StaticDemoAccounts.demoAccountHelpText(),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF9CA3AF),
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 320,
                mainAxisSpacing: 14,
                crossAxisSpacing: 14,
                childAspectRatio: 1.15,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final id = modules[index];
                  final isLive = id == SystemModuleId.rfidManagement ||
                      id == SystemModuleId.virtualAdmissionKiosk ||
                      id == SystemModuleId.adminOverview ||
                      id == SystemModuleId.doDashboard ||
                      id == SystemModuleId.guidanceCounselor;
                  return _ModuleCard(
                    title: id.title,
                    subtitle:
                        isLive ? 'Live in this build' : 'Scaffold / planned',
                    icon: _iconFor(id),
                    onTap: () => _openModule(context, id),
                  );
                },
                childCount: modules.length,
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconFor(SystemModuleId id) {
    switch (id) {
      case SystemModuleId.adminOverview:
        return Icons.dashboard_customize_outlined;
      case SystemModuleId.rfidManagement:
        return Icons.credit_card_outlined;
      case SystemModuleId.virtualAdmissionKiosk:
        return Icons.touch_app_outlined;
      case SystemModuleId.registrar:
        return Icons.school_outlined;
      case SystemModuleId.doDashboard:
        return Icons.gavel_outlined;
      case SystemModuleId.guidanceCounselor:
        return Icons.psychology_outlined;
      case SystemModuleId.teacher:
        return Icons.menu_book_outlined;
      case SystemModuleId.securityPatrol:
        return Icons.local_police_outlined;
      case SystemModuleId.studentParentPortal:
        return Icons.family_restroom_outlined;
      case SystemModuleId.attendanceViolationLogging:
        return Icons.fact_check_outlined;
      case SystemModuleId.mlAnalytics:
        return Icons.auto_graph_outlined;
      case SystemModuleId.notificationsReporting:
        return Icons.notifications_active_outlined;
      case SystemModuleId.classSchedule:
        return Icons.calendar_month_outlined;
    }
  }
}

class _ModuleCard extends StatelessWidget {
  const _ModuleCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 1,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 28, color: const Color(0xFF2563EB)),
              const Spacer(),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF6B7280),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
