/// Roles described in the capstone scope (login module + dashboards).
enum AppRole {
  student,
  parent,
  teacher,
  securityPersonnel,
  guidanceCounselor,
  disciplineOfficer,
  registrar,
  administrator,
}

extension AppRoleLabel on AppRole {
  String get displayName {
    switch (this) {
      case AppRole.student:
        return 'Student';
      case AppRole.parent:
        return 'Parent';
      case AppRole.teacher:
        return 'Teacher / Professor';
      case AppRole.securityPersonnel:
        return 'Security Personnel';
      case AppRole.guidanceCounselor:
        return 'Guidance Counselor';
      case AppRole.disciplineOfficer:
        return 'Discipline Officer';
      case AppRole.registrar:
        return 'Registrar';
      case AppRole.administrator:
        return 'Administrator';
    }
  }
}
