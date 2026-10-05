import 'app_role.dart';
import 'app_user.dart';

/// Demo-only accounts. Replace with Supabase auth + JWT per scope.
///
/// Password policy for capstone demos: documented here for reviewers.
class StaticDemoAccounts {
  const StaticDemoAccounts._();

  /// Lowercase username -> record
  static const Map<String, _DemoRecord> _records = {
    'admin': _DemoRecord(
      password: 'Capstone2026!',
      user: AppUser(
        id: 'u_admin',
        displayName: 'Administrator',
        role: AppRole.administrator,
        username: 'admin',
      ),
    ),
    'registrar.demo': _DemoRecord(
      password: 'Registrar2026!',
      user: AppUser(
        id: 'u_registrar',
        displayName: 'Registrar Staff',
        role: AppRole.registrar,
        username: 'registrar.demo',
      ),
    ),
    'do.demo': _DemoRecord(
      password: 'DO2026!',
      user: AppUser(
        id: 'u_do',
        displayName: 'Student Affairs & Services',
        role: AppRole.disciplineOfficer,
        username: 'do.demo',
      ),
    ),
    'guidance.demo': _DemoRecord(
      password: 'Guidance2026!',
      user: AppUser(
        id: 'u_guidance',
        displayName: 'Guidance Counselor',
        role: AppRole.guidanceCounselor,
        username: 'guidance.demo',
      ),
    ),
    'teacher.demo': _DemoRecord(
      password: 'Teach2026!',
      user: AppUser(
        id: 'u_teacher',
        displayName: 'Faculty Member',
        role: AppRole.teacher,
        username: 'teacher.demo',
      ),
    ),
    'security.demo': _DemoRecord(
      password: 'Security2026!',
      user: AppUser(
        id: 'u_security',
        displayName: 'Campus Security',
        role: AppRole.securityPersonnel,
        username: 'security.demo',
      ),
    ),
    'ittech.demo': _DemoRecord(
      password: 'ITTech2026!',
      user: AppUser(
        id: 'u_ittech',
        displayName: 'IT Technician',
        role: AppRole.itTechnician,
        username: 'ittech.demo',
      ),
    ),
    'scheduling.demo': _DemoRecord(
      password: 'Scheduling2026!',
      user: AppUser(
        id: 'u_scheduling',
        displayName: 'Scheduling Officer',
        role: AppRole.schedulingOfficer,
        username: 'scheduling.demo',
      ),
    ),
    'student.demo': _DemoRecord(
      password: 'Student2026!',
      user: AppUser(
        id: 'u_student',
        displayName: 'Demo Student',
        role: AppRole.student,
        username: 'student.demo',
      ),
    ),
    'parent.demo': _DemoRecord(
      password: 'Parent2026!',
      user: AppUser(
        id: 'u_parent',
        displayName: 'Demo Parent',
        role: AppRole.parent,
        username: 'parent.demo',
      ),
    ),
  };

  static AppUser? trySignIn(String username, String password) {
    final key = username.trim().toLowerCase();
    final record = _records[key];
    if (record == null) return null;
    if (record.password != password) return null;
    return record.user;
  }

  /// Looks up a demo account by username alone, with no password check —
  /// used only to restore a session already proven once (the password was
  /// checked at the original [trySignIn] call; [AppStatePersistence]
  /// storing the username afterward is the "remember me" token, not a
  /// bypass of that check).
  static AppUser? byUsername(String username) {
    return _records[username.trim().toLowerCase()]?.user;
  }

  static String demoAccountHelpText() {
    final lines = <String>[
      'Demo accounts (username / password):',
      '  admin / Capstone2026!',
      '  security.demo / Security2026!  → kiosk + RFID',
      '  ittech.demo / ITTech2026!  → IT Technician Dashboard',
      '  registrar.demo / Registrar2026!',
      '  scheduling.demo / Scheduling2026!  → Scheduling Officer Dashboard',
      '  do.demo / DO2026!',
      '  guidance.demo / Guidance2026!',
      '  teacher.demo / Teach2026!',
      '  student.demo / Student2026!',
      '  parent.demo / Parent2026!',
    ];
    return lines.join('\n');
  }
}

class _DemoRecord {
  const _DemoRecord({required this.password, required this.user});

  final String password;
  final AppUser user;
}
