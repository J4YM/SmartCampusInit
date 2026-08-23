import 'package:admin_dashboard/admin_dashboard.dart';

import '../../auth/app_role.dart';

/// Maps between the package-local, UI-only [StaffRole] enum
/// (`packages/admin_dashboard`, which has no knowledge of Supabase or the DB
/// `app_role` enum) and this app's [AppRole]. Kept in the root app so the
/// package stays backend-agnostic.
AppRole staffRoleToAppRole(StaffRole role) {
  switch (role) {
    case StaffRole.systemAdmin:
      return AppRole.administrator;
    case StaffRole.disciplineOfficer:
      return AppRole.disciplineOfficer;
    case StaffRole.guidanceCounselor:
      return AppRole.guidanceCounselor;
    case StaffRole.security:
      return AppRole.securityPersonnel;
    case StaffRole.teacher:
      return AppRole.teacher;
    case StaffRole.registrar:
      return AppRole.registrar;
    case StaffRole.itTechnician:
      return AppRole.itTechnician;
  }
}

/// Returns null for roles with no staff-facing equivalent (student, parent).
StaffRole? appRoleToStaffRole(AppRole? role) {
  switch (role) {
    case AppRole.administrator:
      return StaffRole.systemAdmin;
    case AppRole.disciplineOfficer:
      return StaffRole.disciplineOfficer;
    case AppRole.guidanceCounselor:
      return StaffRole.guidanceCounselor;
    case AppRole.securityPersonnel:
      return StaffRole.security;
    case AppRole.teacher:
      return StaffRole.teacher;
    case AppRole.registrar:
      return StaffRole.registrar;
    case AppRole.itTechnician:
      return StaffRole.itTechnician;
    case AppRole.student:
    case AppRole.parent:
    case null:
      return null;
  }
}

String avatarInitialsFor(String fullName) {
  final parts = fullName.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
}
