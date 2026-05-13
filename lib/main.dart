import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/session_controller.dart';
import 'env.dart';
import 'ui/admin/admin_hub_page.dart';
import 'ui/login_page.dart';
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
    debugPrint('Supabase initialized for ${Uri.parse(AppEnv.supabaseUrl).host}.');
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
          home: _session.isAuthenticated
              ? AdminHubPage(session: _session)
              : LoginPage(session: _session),
        );
      },
    );
  }
}
