enum DashboardRoute {
  overview,
  studentDirectory,
  staffAccounts,
  accountLinking,
  rfidMapping,
  mlThresholds,
  notifications,
  registerSyncs,
  academicTerm,
  auditPrivacyLogs,
  kioskSyncFailures,
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
      case DashboardRoute.accountLinking:
        return 'Account Linking';
      case DashboardRoute.rfidMapping:
        return 'RFID Mapping';
      case DashboardRoute.mlThresholds:
        return 'ML & Thresholds';
      case DashboardRoute.notifications:
        return 'Notifications';
      case DashboardRoute.academicTerm:
        return 'Academic Term';
      case DashboardRoute.registerSyncs:
        return 'Register Syncs';
      case DashboardRoute.auditPrivacyLogs:
        return 'Audit & Privacy Logs';
      case DashboardRoute.kioskSyncFailures:
        return 'Kiosk Sync Failures';
      case DashboardRoute.reportsExports:
        return 'Reports & Exports';
      case DashboardRoute.settings:
        return 'Settings';
    }
  }
}
