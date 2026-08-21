import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin/admin_module_scope.dart';
import 'app/session_controller.dart';
import 'auth/app_role.dart';
import 'env.dart';
import 'modules/system_module_id.dart';
import 'ui/admin/admin_hub_page.dart';
import 'ui/admin/module_placeholder_page.dart';
import 'ui/awaiting_approval_page.dart';
import 'ui/discipline_officer_connected_page.dart';
import 'ui/guidance_counselor_connected_page.dart';
import 'ui/login_page.dart';
import 'ui/professor_connected_page.dart';
import 'ui/student_registration_gate_page.dart';
import 'util/load_local_env.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await loadLocalEnv();
  AppEnv.resolve();

  if (AppEnv.supabaseConfigured) {
    await Supabase.initialize(
      url: AppEnv.supabaseUrl,
      anonKey: AppEnv.supabaseAnonKey,
    );
    debugPrint(
        'Supabase initialized for ${Uri.parse(AppEnv.supabaseUrl).host}.');
  } else {
    debugPrint(
      'Supabase not configured. Add a project root `.env` with SUPABASE_URL and '
      'SUPABASE_ANON_KEY (see `.env.example`), or pass --dart-define / '
      '--dart-define-from-file when running.',
    );
  }

  runApp(const CapstoneApp());
}

class CapstoneApp extends StatefulWidget {
  const CapstoneApp({super.key});

  @override
  State<CapstoneApp> createState() => _CapstoneAppState();
}

class _CapstoneAppState extends State<CapstoneApp> {
  late final SessionController _session = SessionController();

  @override
  Widget build(BuildContext context) {
    final baseTheme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF2563EB),
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: const Color(0xFFF5F7FB),
      textTheme: GoogleFonts.interTextTheme(),
    );

    return ListenableBuilder(
      listenable: _session,
      builder: (context, _) {
        return MaterialApp(
          title: 'STI Baliuag — Attendance & Discipline',
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

/// Post-login landing page per role. Admin still lands on [AdminHubPage] to
/// preview every module during the production/testing phase; every other
/// role skips the hub picker and goes straight to their own module — a real
/// dashboard where one exists (Discipline Officer), otherwise the module
/// that shares their role's name (still a placeholder until it's built).
Widget _homeForRole(AppRole role, SessionController session) {
  if (role == AppRole.administrator) {
    return AdminHubPage(session: session);
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

  final moduleId = switch (role) {
    AppRole.student || AppRole.parent => SystemModuleId.studentParentPortal,
    AppRole.securityPersonnel => SystemModuleId.securityPatrol,
    AppRole.registrar => SystemModuleId.registrar,
    AppRole.disciplineOfficer ||
    AppRole.guidanceCounselor ||
    AppRole.teacher ||
    AppRole.administrator =>
      throw StateError('handled above'),
  };

  return ModulePlaceholderPage(
    moduleId: moduleId,
    bulletPoints: AdminModuleScope.bulletsFor(moduleId),
    onSignOut: session.signOut,
  );
}
