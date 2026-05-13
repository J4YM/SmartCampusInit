/// Identifiers for major UI areas in the integrated STI Baliuag system.
enum SystemModuleId {
  adminOverview,
  rfidManagement,
  virtualAdmissionKiosk,
  registrar,
  doDashboard,
  guidanceCounselor,
  teacher,
  securityPatrol,
  studentParentPortal,
  attendanceViolationLogging,
  mlAnalytics,
  notificationsReporting,
  classSchedule,
}

extension SystemModuleIdLabel on SystemModuleId {
  String get title {
    switch (this) {
      case SystemModuleId.adminOverview:
        return 'Admin Overview';
      case SystemModuleId.rfidManagement:
        return 'RFID Management';
      case SystemModuleId.virtualAdmissionKiosk:
        return 'Virtual Admission Kiosk';
      case SystemModuleId.registrar:
        return 'Registrar';
      case SystemModuleId.doDashboard:
        return 'Discipline Officer';
      case SystemModuleId.guidanceCounselor:
        return 'Guidance Counselor';
      case SystemModuleId.teacher:
        return 'Teacher / Professor';
      case SystemModuleId.securityPatrol:
        return 'Security Personnel';
      case SystemModuleId.studentParentPortal:
        return 'Student & Parent Portal';
      case SystemModuleId.attendanceViolationLogging:
        return 'RFID Attendance & Violations';
      case SystemModuleId.mlAnalytics:
        return 'ML & Behavioral Analytics';
      case SystemModuleId.notificationsReporting:
        return 'Notifications & Reporting';
      case SystemModuleId.classSchedule:
        return 'Class Schedule';
    }
  }
}
