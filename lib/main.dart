import 'package:admin_dashboard/admin_dashboard.dart' show AdminModuleEntry;
import 'package:discipline_officer_module/discipline_officer_module.dart'
    show NotificationReplyHandler, ProfileActions;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin/admin_module_scope.dart';
import 'app/notification_alert.dart';
import 'app/notification_sound_persistence.dart';
import 'app/session_controller.dart';
import 'app/technical_issue_reply.dart';
import 'app/theme_mode_persistence.dart';
import 'auth/app_role.dart';
import 'auth/staff_password_auth.dart';
import 'env.dart';
import 'modules/system_module_id.dart';
import 'ui/admin/admin_dashboard_connected_page.dart';
import 'ui/admin/audit_logs_connected_page.dart';
import 'ui/admin/ml_thresholds_connected_page.dart';
import 'ui/admin/module_placeholder_page.dart';
import 'ui/admin/academic_term_connected_page.dart';
import 'ui/admin/register_syncs_connected_page.dart';
import 'ui/admin/reports_exports_connected_page.dart';
import 'ui/admin/rfid_mapping_connected_page.dart';
import 'ui/admin/staff_accounts_connected_page.dart';
import 'ui/admin/student_directory_connected_page.dart';
import 'ui/admin/system_overview_connected_page.dart';
import 'ui/awaiting_approval_page.dart';
import 'ui/discipline_officer_connected_page.dart';
import 'ui/guidance_counselor_connected_page.dart';
import 'ui/login_page.dart';
import 'ui/it_technician_connected_page.dart';
import 'ui/professor_connected_page.dart';
import 'ui/professor_links_panel.dart';
import 'ui/registrar_connected_page.dart';
import 'ui/scheduling_officer_connected_page.dart';
import 'ui/parent_portal_connected_page.dart';
import 'ui/student_portal_connected_page.dart';
import 'ui/student_registration_gate_page.dart';
import 'util/load_local_env.dart';
import 'util/window_lockdown.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Every window this repo's native Windows runner creates starts locked
  // down (fullscreen, no close button — see win32_window.cpp) for the
  // kiosk build's sake; this is the main login-gated dashboard, not a
  // kiosk, so it asks to be a normal closable window instead. A no-op on
  // every other platform.
  await disableKioskLockdownOnWindows();

  await loadLocalEnv();
  AppEnv.resolve();

  if (AppEnv.supabaseConfigured) {
    await Supabase.initialize(
      url: AppEnv.supabaseUrl,
      anonKey: AppEnv.supabaseAnonKey,
    );
    debugPrint(
        'Supabase initialized for ${Uri.parse(AppEnv.supabaseUrl).host}.');
    // "Update password" on every dashboard's profile screen: works for an
    // email + password account; a demo login or Microsoft account is told why
    // it cannot (see changeOwnPassword).
    ProfileActions.changePassword = ({
      required String currentPassword,
      required String newPassword,
    }) =>
        changeOwnPassword(
          Supabase.instance.client,
          currentPassword: currentPassword,
          newPassword: newPassword,
        );
  } else {
    debugPrint(
      'Supabase not configured. Add a project root `.env` with SUPABASE_URL and '
      'SUPABASE_ANON_KEY (see `.env.example`), or pass --dart-define / '
      '--dart-define-from-file when running.',
    );
  }

  // The light/dark choice made last time (it outlives sign-out and restart).
  await restoreThemeMode();

  // Every newly sent notification makes a sound, on whichever dashboard —
  // unless the person switched it off in their profile menu.
  await setUpNotificationSound();

  runApp(const CapstoneApp());
}

class CapstoneApp extends StatefulWidget {
  const CapstoneApp({super.key});

  @override
  State<CapstoneApp> createState() => _CapstoneAppState();
}

class _CapstoneAppState extends State<CapstoneApp> {
  late final SessionController _session = SessionController();

  String? _windowTitle;

  /// `STI Baliuag - Admin`, `STI Baliuag - Registrar`, … — or `Sign In`
  /// before anyone is signed in. Used for both the browser tab and the
  /// Windows title bar / taskbar.
  String get _pageTitle => stiBaliuagTitle(
        _session.isAuthenticated ? _session.user!.role.titleName : 'Sign In',
      );

  /// Names the dashboard on screen in the Windows title bar / taskbar.
  void _syncWindowTitle() {
    final title = _pageTitle;
    if (title == _windowTitle) return;
    _windowTitle = title;
    setWindowTitleOnWindows(title);
  }

  @override
  Widget build(BuildContext context) {
    final baseTheme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF2563EB),
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: const Color(0xFFF5F7FB),
      textTheme: GoogleFonts.poppinsTextTheme(),
    );

    return ListenableBuilder(
      listenable: _session,
      builder: (context, _) {
        _syncWindowTitle();
        // Whoever is signed in can answer a technical-issue message from any
        // dashboard's notification popup (cleared again on sign-out).
        NotificationReplyHandler.current = replySenderFor(_session);
        // Signed out: the next sign-in's first read is quiet again.
        if (!_session.isAuthenticated) NotificationAlert.reset();
        return MaterialApp(
          title: _pageTitle,
          debugShowCheckedModeBanner: false,
          theme: baseTheme.copyWith(
            appBarTheme: const AppBarTheme(
              elevation: 0,
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
            ),
          ),
          home: !_session.isAuthenticated
              ? (_session.isAwaitingApproval
                  ? AwaitingApprovalPage(session: _session)
                  : _session.needsStudentSetup
                      ? StudentRegistrationGatePage(session: _session)
                      : LoginPage(session: _session))
              : _homeForRole(_session.user!.role, _session),
        );
      },
    );
  }
}

/// Post-login landing page per role. Every role goes straight to its own
/// module — a real dashboard where one exists, otherwise the module that
/// shares the role's name (still a placeholder until it's built). There is
/// no cross-module hub: to see another role's module, sign in with that
/// role's own demo account.
Widget _homeForRole(AppRole role, SessionController session) {
  if (role == AppRole.administrator) {
    final user = session.user!;
    return AdminDashboardConnectedPage(
      currentUser: user,
      onSignOut: session.signOut,
      systemOverviewPageBuilder: (_) => const SystemOverviewConnectedPage(),
      staffAccountsPageBuilder: (_) => StaffAccountsConnectedPage(currentUser: user),
      rfidMappingPageBuilder: (_) => RfidMappingConnectedPage(currentUser: user),
      studentDirectoryPageBuilder: (_) => StudentDirectoryConnectedPage(session: session),
      mlThresholdsPageBuilder: (_) => const MlThresholdsConnectedPage(),
      registerSyncsPageBuilder: (_) => const RegisterSyncsConnectedPage(),
      academicTermPageBuilder: (_) => AcademicTermConnectedPage(currentUser: user),
      accountLinkingPageBuilder: !AppEnv.supabaseConfigured
          ? null
          : (_) => ProfessorLinksPanel(
                actorName: user.displayName,
                actorRole: user.role,
                actorId: user.id.startsWith('u_') ? null : user.id,
              ),
      reportsExportsPageBuilder: (_) => const ReportsExportsConnectedPage(),
      auditLogsPageBuilder: (_) => const AuditLogsConnectedPage(),
      moduleEntries: _adminModuleEntries(session),
    );
  }

  if (role == AppRole.disciplineOfficer) {
    return DisciplineOfficerConnectedPage(
      officerName: session.user!.displayName,
      currentUser: session.user,
      onSignOut: session.signOut,
    );
  }

  if (role == AppRole.guidanceCounselor) {
    return GuidanceCounselorConnectedPage(
      counselorName: session.user!.displayName,
      counselorProfileId: session.user!.id,
      onSignOut: session.signOut,
    );
  }

  if (role == AppRole.teacher) {
    return ProfessorConnectedPage(
      professorName: session.user!.displayName,
      professorProfileId: session.user!.id,
      onSignOut: session.signOut,
    );
  }

  if (role == AppRole.itTechnician) {
    return ItTechnicianConnectedPage(
      technicianName: session.user!.displayName,
      technicianProfileId: session.user!.id,
      onSignOut: session.signOut,
    );
  }

  if (role == AppRole.registrar) {
    return RegistrarConnectedPage(
      registrarName: session.user!.displayName,
      registrarProfileId: session.user!.id,
      onSignOut: session.signOut,
    );
  }

  if (role == AppRole.schedulingOfficer) {
    return SchedulingOfficerConnectedPage(
      officerName: session.user!.displayName,
      onSignOut: session.signOut,
    );
  }

  if (role == AppRole.student) {
    return StudentPortalConnectedPage(
      currentUser: session.user,
      onSignOut: session.signOut,
    );
  }

  if (role == AppRole.parent) {
    return ParentPortalConnectedPage(
      currentUser: session.user,
      onSignOut: session.signOut,
    );
  }

  final moduleId = switch (role) {
    AppRole.parent => throw StateError('handled above'),
    AppRole.student => throw StateError('handled above'),
    AppRole.securityPersonnel => SystemModuleId.securityPatrol,
    AppRole.disciplineOfficer ||
    AppRole.guidanceCounselor ||
    AppRole.teacher ||
    AppRole.administrator ||
    AppRole.itTechnician ||
    AppRole.registrar ||
    AppRole.schedulingOfficer =>
      throw StateError('handled above'),
  };

  return ModulePlaceholderPage(
    moduleId: moduleId,
    bulletPoints: AdminModuleScope.bulletsFor(moduleId),
    onSignOut: session.signOut,
  );
}

/// Every other role's dashboard, offered to the Admin in the sidebar's
/// "Role Modules" section. Grouped by the part of the school the role works
/// in; the Admin has full control over all of them (see
/// [ModuleAccess.canSeeModule], which already admits the administrator to
/// every module).
List<AdminModuleEntry> _adminModuleEntries(SessionController session) {
  final user = session.user!;
  final name = user.displayName;
  // A real profiles.id, or null for a static demo account (see
  // SessionController.canVerifyPassword).
  final profileId = user.id;

  return [
    AdminModuleEntry(
      id: 'registrar',
      group: 'Academic Affairs',
      label: 'Registrar',
      icon: Icons.assignment_ind_outlined,
      builder: (_) => RegistrarConnectedPage(
        registrarName: name,
        registrarProfileId: profileId,
        onSignOut: session.signOut,
        canLiftRestrictions: true,
      ),
    ),
    AdminModuleEntry(
      id: 'scheduling',
      group: 'Academic Affairs',
      label: 'Scheduling Officer',
      icon: Icons.calendar_month_outlined,
      builder: (_) => SchedulingOfficerConnectedPage(
        officerName: name,
        onSignOut: session.signOut,
      ),
    ),
    AdminModuleEntry(
      id: 'discipline',
      group: 'Student Services',
      label: 'Student Affairs & Services',
      icon: Icons.gavel_outlined,
      builder: (_) => DisciplineOfficerConnectedPage(
        officerName: name,
        currentUser: user,
        onSignOut: session.signOut,
      ),
    ),
    AdminModuleEntry(
      id: 'guidance',
      group: 'Student Services',
      label: 'Guidance Counselor',
      icon: Icons.psychology_outlined,
      builder: (_) => GuidanceCounselorConnectedPage(
        counselorName: name,
        counselorProfileId: profileId,
        onSignOut: session.signOut,
      ),
    ),
    AdminModuleEntry(
      id: 'professor',
      group: 'Faculty',
      label: 'Professor',
      icon: Icons.co_present_outlined,
      builder: (_) => ProfessorConnectedPage(
        professorName: name,
        professorProfileId: profileId,
        onSignOut: session.signOut,
      ),
    ),
    AdminModuleEntry(
      id: 'it-technician',
      group: 'IT & Security',
      label: 'IT Technician',
      icon: Icons.computer_outlined,
      builder: (_) => ItTechnicianConnectedPage(
        technicianName: name,
        technicianProfileId: profileId,
        onSignOut: session.signOut,
      ),
    ),
    AdminModuleEntry(
      id: 'security',
      group: 'IT & Security',
      label: 'Security Personnel',
      icon: Icons.security_outlined,
      builder: (_) => ModulePlaceholderPage(
        moduleId: SystemModuleId.securityPatrol,
        bulletPoints: AdminModuleScope.bulletsFor(SystemModuleId.securityPatrol),
      ),
    ),
    AdminModuleEntry(
      id: 'student-portal',
      group: 'Portals',
      label: 'Student Portal',
      icon: Icons.school_outlined,
      builder: (_) => StudentPortalConnectedPage(
        currentUser: user,
        onSignOut: session.signOut,
      ),
    ),
    AdminModuleEntry(
      id: 'parent-portal',
      group: 'Portals',
      label: 'Parent Portal',
      icon: Icons.family_restroom_outlined,
      builder: (_) => ParentPortalConnectedPage(
        currentUser: user,
        onSignOut: session.signOut,
      ),
    ),
  ];
}
