import '../modules/system_module_id.dart';

/// Future admin capabilities (audit trails, bulk user management, ML retrain, etc.).
/// The hub reads this for "Admin overview" and documentation-style tooltips.
class AdminModuleScope {
  const AdminModuleScope._();

  static const List<String> roleBasedDashboards = [
    'Role-based views: violations, attendance trends, repeat offenders.',
    'Filters: demographics, programs, date ranges, violation types.',
    'Exports: PDF / Excel for CHED and internal reviews.',
  ];

  static const List<String> userAndRfidOperations = [
    'Bulk user management: add/edit students, assign RFID, reset permissions.',
    'Integration with registrar records and RFID UID uniqueness checks.',
  ];

  static const List<String> systemConfiguration = [
    'Notification thresholds for parents and escalation SLAs.',
    'ML model retraining schedules and anonymized training pipelines.',
    'Backup automation and environment promotion controls.',
  ];

  static const List<String> compliance = [
    'Audit trails for every login and sensitive data access (RA 10173).',
    'Compliance reports: who viewed which student records and when.',
  ];

  static List<String> bulletsFor(SystemModuleId id) {
    switch (id) {
      case SystemModuleId.adminOverview:
        return [
          ...roleBasedDashboards,
          ...userAndRfidOperations,
          ...systemConfiguration,
          ...compliance,
        ];
      case SystemModuleId.rfidManagement:
        return [
          'Initialize and link RFID UIDs to student profiles.',
          'Manual entry for personal data; validation against registrar sections.',
        ];
      case SystemModuleId.virtualAdmissionKiosk:
        return [
          'Self-service RFID flow, minor violation acknowledgement, slip generation.',
          'QR codes with TTL, duplicate-scan prevention, offline cache + sync.',
        ];
      case SystemModuleId.registrar:
        return [
          'Centralized student information, schedules per block and per student.',
          'Grade and schedule import via manual entry or spreadsheet for ML inputs.',
        ];
      case SystemModuleId.doDashboard:
        return [
          'Admission slip validation, sanction workflow, evidence attachments.',
          'Queue for slip approvals, escalation SLA to security incidents.',
        ];
      case SystemModuleId.guidanceCounselor:
        return [
          'ML early warnings, student timelines, intervention logging.',
          'View-only violations; collaboration with DO and parents.',
        ];
      case SystemModuleId.teacher:
        return [
          'Class RFID roster, proxy detection, admission slip QR checks.',
          'In-class violation reporting with evidence; section analytics.',
        ];
      case SystemModuleId.securityPatrol:
        return [
          'Patrol-mode kiosk scanning, major violation escalation to DO.',
          'End-of-shift incident report generation.',
        ];
      case SystemModuleId.studentParentPortal:
        return [
          'Attendance, violations, pending slips, risk indicators.',
          'Secure messaging with DO/Guidance; mobile-responsive layout.',
        ];
      case SystemModuleId.attendanceViolationLogging:
        return [
          'ESP32 + RC522 paths: gates, rooms, patrol points; sub-second capture.',
          'Tardiness rules, handbook-aligned offense classes, visitor RFID TTL.',
        ];
      case SystemModuleId.mlAnalytics:
        return [
          'Logistic Regression, Random Forest, SVM, XGBoost ensemble.',
          'SMOTE preprocessing, quarterly retrain, dropout risk > 70% flags.',
        ];
      case SystemModuleId.notificationsReporting:
        return [
          'Push / SMS / email; security → DO → Guidance escalation timers.',
          'CHED-oriented compliance packs and custom report builder.',
        ];
      case SystemModuleId.classSchedule:
        return [
          'Registrar-linked schedules; irregular and makeup class support.',
          'Attendance scan windows gated by subject, room, and time.',
        ];
    }
  }
}
