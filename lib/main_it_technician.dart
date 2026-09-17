import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/session_controller.dart';
import 'auth/app_role.dart';
import 'env.dart';
import 'ui/it_technician_connected_page.dart';
import 'ui/login_page.dart';
import 'util/load_local_env.dart';

/// Dedicated IT Technician device entry: gated behind [LoginPage] (the
/// same demo-account/Microsoft sign-in used by the main dashboard),
/// restricted to accounts whose role is [AppRole.itTechnician] — this
/// device exposes student PII, student create/delete, and reader-device
/// configuration, so it must not accept any other staff account. See
/// `windows/installer/it_technician_installer.iss`'s SECURITY NOTE,
/// written when this entrypoint had no login at all.
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
      'IT Technician mode: Supabase initialized for ${Uri.parse(AppEnv.supabaseUrl).host}.',
    );
  } else {
    debugPrint(
      'IT Technician mode: Supabase not configured. Add a project root '
      '`.env` with SUPABASE_URL and SUPABASE_ANON_KEY (see `.env.example`).',
    );
  }

  runApp(const ItTechnicianStandaloneApp());
}

class ItTechnicianStandaloneApp extends StatefulWidget {
  const ItTechnicianStandaloneApp({super.key});

  @override
  State<ItTechnicianStandaloneApp> createState() =>
      _ItTechnicianStandaloneAppState();
}

class _ItTechnicianStandaloneAppState
    extends State<ItTechnicianStandaloneApp> {
  final SessionController _session = SessionController();
  final _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

  /// Guards against scheduling more than one sign-out if `build()` runs
  /// again (e.g. from an unrelated rebuild) before the post-frame
  /// callback below has fired.
  bool _rejectingWrongRole = false;

  @override
  void dispose() {
    _session.dispose();
    super.dispose();
  }

  /// Signs a non-IT_Technician account back out and reports why. Only
  /// reachable via Microsoft sign-in — every demo account's role is
  /// already known synchronously from [StaticDemoAccounts], but a
  /// Microsoft-authenticated account's role only resolves after
  /// [SessionController] completes the OAuth round trip. Deferred to a
  /// post-frame callback: `build()` is what detects the wrong role, and
  /// `signOut()` calls `notifyListeners()`, which `ListenableBuilder`
  /// would otherwise try to act on while this very build is still in
  /// progress.
  void _rejectWrongRole() {
    if (_rejectingWrongRole) return;
    _rejectingWrongRole = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _rejectingWrongRole = false;
      _session.signOut();
      _scaffoldMessengerKey.currentState?.showSnackBar(
        const SnackBar(
          content:
              Text('This device is for IT Technician accounts only.'),
        ),
      );
    });
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
      textTheme: GoogleFonts.interTextTheme(),
    );

    return MaterialApp(
      title: 'STI Baliuag — IT Technician',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: _scaffoldMessengerKey,
      theme: baseTheme.copyWith(
        appBarTheme: const AppBarTheme(
          elevation: 0,
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
        ),
      ),
      home: ListenableBuilder(
        listenable: _session,
        builder: (context, _) {
          final user = _session.user;
          if (user == null) {
            return LoginPage(session: _session);
          }
          if (user.role != AppRole.itTechnician) {
            // Never render the dashboard for a wrong-role account, even
            // for one frame — the sign-out fires as a side effect below,
            // but the branch taken here already keeps this build() on
            // the login screen.
            _rejectWrongRole();
            return LoginPage(session: _session);
          }
          return ItTechnicianConnectedPage(
            technicianName: user.displayName,
            technicianProfileId: user.id,
            onSignOut: _session.signOut,
          );
        },
      ),
    );
  }
}
