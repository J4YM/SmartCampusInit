enum DashboardRoute {
  overview,
  studentDirectory,
  staffAccounts,
  rfidMapping,
  mlThresholds,
  notifications,
  registerSyncs,
  auditPrivacyLogs,
  reportsExports,
  settings,
}

extension DashboardRouteX on DashboardRoute {
  String get title {
    switch (this) {
      case DashboardRoute.overview:
        return 'Overview';
      case DashboardRoute.studentDirectory:
        return 'Student Directory';
      case DashboardRoute.staffAccounts:
        return 'Staff Accounts';
      case DashboardRoute.rfidMapping:
        return 'RFID Mapping';
      case DashboardRoute.mlThresholds:
        return 'ML & Thresholds';
      case DashboardRoute.notifications:
        return 'Notifications';
      case DashboardRoute.registerSyncs:
        return 'Register Syncs';
      case DashboardRoute.auditPrivacyLogs:
        return 'Audit & Privacy Logs';
      case DashboardRoute.reportsExports:
        return 'Reports & Exports';
      case DashboardRoute.settings:
        return 'Settings';
    }
  }
}
