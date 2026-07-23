import 'package:flutter/material.dart';

import '../models/dashboard_route.dart';
import '../theme/app_colors.dart';
import 'overview/system_overview_page.dart';
import 'student_directory/student_directory_page.dart';
import 'staff_accounts/staff_accounts_page.dart';
import 'rfid_mapping/rfid_mapping_page.dart';
import 'ml_thresholds/ml_thresholds_page.dart';
import 'notifications/notifications_page.dart';
import 'audit_logs/audit_logs_page.dart';
import 'reports_exports/reports_exports_page.dart';
import 'settings/settings_page.dart';

class MainContentArea extends StatelessWidget {
  const MainContentArea({
    super.key,
    required this.selectedRoute,
  });

  final DashboardRoute selectedRoute;

  @override
  Widget build(BuildContext context) {
    if (selectedRoute == DashboardRoute.overview) {
      return SystemOverviewPage.empty();
    }

    if (selectedRoute == DashboardRoute.studentDirectory) {
      return StudentDirectoryPage.empty();
    }

    if (selectedRoute == DashboardRoute.staffAccounts) {
      return StaffAccountsPage.empty();
    }

    if (selectedRoute == DashboardRoute.rfidMapping) {
      return RfidMappingPage.empty();
    }

    if (selectedRoute == DashboardRoute.mlThresholds) {
      return MlThresholdsPage.empty();
    }

    if (selectedRoute == DashboardRoute.notifications) {
      return NotificationsPage.empty();
    }

    if (selectedRoute == DashboardRoute.auditPrivacyLogs) {
      return AuditLogsPage.empty();
    }

    if (selectedRoute == DashboardRoute.reportsExports) {
      return ReportsExportsPage.empty();
    }

    if (selectedRoute == DashboardRoute.settings) {
      return SettingsPage.empty();
    }

    return ColoredBox(
      color: AppColors.mainBackground,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                selectedRoute.title,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: AppColors.contentText,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _subtitleForRoute(selectedRoute),
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 15,
                  fontWeight: FontWeight.w400,
                  color: AppColors.contentMuted,
                ),
              ),
              const SizedBox(height: 32),
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: Center(
                    child: Text(
                      '${selectedRoute.title} content goes here.',
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 16,
                        color: AppColors.contentMuted,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _subtitleForRoute(DashboardRoute route) {
    switch (route) {
      case DashboardRoute.overview:
        return 'Monitor key metrics and system activity at a glance.';
      case DashboardRoute.studentDirectory:
        return 'Browse and manage enrolled student records.';
      case DashboardRoute.staffAccounts:
        return 'Configure staff roles, access, and account details.';
      case DashboardRoute.rfidMapping:
        return 'Assign and review RFID card mappings for users.';
      case DashboardRoute.mlThresholds:
        return 'Tune machine learning models and alert thresholds.';
      case DashboardRoute.notifications:
        return 'Manage notification channels and delivery rules.';
      case DashboardRoute.registerSyncs:
        return 'Review synchronization jobs and registration pipelines.';
      case DashboardRoute.auditPrivacyLogs:
        return 'Inspect audit trails and privacy-related events.';
      case DashboardRoute.reportsExports:
        return 'Generate reports and export dashboard data.';
      case DashboardRoute.settings:
        return 'Update your profile and application preferences.';
    }
  }
}
