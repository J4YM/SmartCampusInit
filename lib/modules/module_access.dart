import '../auth/app_role.dart';
import 'system_module_id.dart';

/// Role-based routing for module tiles. Expand when Supabase roles are available.
class ModuleAccess {
  const ModuleAccess._();

  static bool canSeeModule(AppRole role, SystemModuleId module) {
    switch (module) {
      case SystemModuleId.adminOverview:
        return role == AppRole.administrator;
      case SystemModuleId.rfidManagement:
        return {
          AppRole.administrator,
          AppRole.registrar,
          AppRole.securityPersonnel,
        }.contains(role);
      case SystemModuleId.virtualAdmissionKiosk:
        return {
          AppRole.administrator,
          AppRole.securityPersonnel,
          AppRole.student,
          AppRole.teacher,
        }.contains(role);
      case SystemModuleId.registrar:
        return {
          AppRole.administrator,
          AppRole.registrar,
        }.contains(role);
      case SystemModuleId.doDashboard:
        return {
          AppRole.administrator,
          AppRole.disciplineOfficer,
        }.contains(role);
      case SystemModuleId.guidanceCounselor:
        return {
          AppRole.administrator,
          AppRole.guidanceCounselor,
        }.contains(role);
      case SystemModuleId.teacher:
        return {
          AppRole.administrator,
          AppRole.teacher,
        }.contains(role);
      case SystemModuleId.securityPatrol:
        return {
          AppRole.administrator,
          AppRole.securityPersonnel,
        }.contains(role);
      case SystemModuleId.studentParentPortal:
        return {
          AppRole.administrator,
          AppRole.student,
          AppRole.parent,
        }.contains(role);
      case SystemModuleId.attendanceViolationLogging:
        return {
          AppRole.administrator,
          AppRole.teacher,
          AppRole.securityPersonnel,
          AppRole.disciplineOfficer,
        }.contains(role);
      case SystemModuleId.mlAnalytics:
        return {
          AppRole.administrator,
          AppRole.guidanceCounselor,
        }.contains(role);
      case SystemModuleId.notificationsReporting:
        return role == AppRole.administrator;
      case SystemModuleId.classSchedule:
        return {
          AppRole.administrator,
          AppRole.registrar,
          AppRole.teacher,
        }.contains(role);
    }
  }
}
