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

/// Maps a Postgres `app_role` enum label (as stored on `profiles.role`) to
/// the app's own [AppRole]. Returns `null` for an unrecognized/missing value
/// so callers can distinguish "no role assigned yet" from a bug.
AppRole? appRoleFromDbValue(String? value) {
  switch (value) {
    case 'Admin':
      return AppRole.administrator;
    case 'Student':
      return AppRole.student;
    case 'Parent':
      return AppRole.parent;
    case 'Discipline_Officer':
      return AppRole.disciplineOfficer;
    case 'Guidance_Counselor':
      return AppRole.guidanceCounselor;
    case 'Teacher':
      return AppRole.teacher;
    case 'Security':
      return AppRole.securityPersonnel;
    case 'Registrar':
      return AppRole.registrar;
    default:
      return null;
  }
}

/// Reverse of [appRoleFromDbValue] — needed to send a role choice back to
/// Supabase (e.g. the admin staff-approval RPCs' `p_role` argument).
String appRoleToDbValue(AppRole role) {
  switch (role) {
    case AppRole.administrator:
      return 'Admin';
    case AppRole.student:
      return 'Student';
    case AppRole.parent:
      return 'Parent';
    case AppRole.disciplineOfficer:
      return 'Discipline_Officer';
    case AppRole.guidanceCounselor:
      return 'Guidance_Counselor';
    case AppRole.teacher:
      return 'Teacher';
    case AppRole.securityPersonnel:
      return 'Security';
    case AppRole.registrar:
      return 'Registrar';
  }
}

/// Roles an admin may hand-assign when approving a pending staff sign-in.
/// Student/Parent are excluded — those are only ever set automatically by
/// the `handle_new_auth_user` trigger from the sign-up email pattern.
const staffAssignableRoles = <AppRole>[
  AppRole.teacher,
  AppRole.registrar,
  AppRole.disciplineOfficer,
  AppRole.guidanceCounselor,
  AppRole.securityPersonnel,
  AppRole.administrator,
];

/// Mirrors the Postgres `approval_status` enum on `profiles.status`.
enum ApprovalStatus { pending, approved }

/// Fails open to [ApprovalStatus.approved] for a null/legacy value so no
/// pre-existing account is locked out client-side by a missing column value.
ApprovalStatus approvalStatusFromDbValue(String? value) {
  return value == 'pending' ? ApprovalStatus.pending : ApprovalStatus.approved;
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
