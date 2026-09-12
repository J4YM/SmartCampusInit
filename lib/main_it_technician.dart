import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'env.dart';
import 'ui/it_technician_connected_page.dart';
import 'util/load_local_env.dart';

/// Dedicated IT Technician device entry: no staff login — boots straight
/// into the IT Technician Dashboard. `ItTechnicianConnectedPage`'s
/// `technicianProfileId`/`technicianName` are both optional and already
/// fall back to a demo identity when omitted (the same fallback the
/// `ittech.demo` static account relies on), so this needs no session
/// wiring of its own. No `onSignOut`/`onReturnToHub` — with no login
/// screen behind it, there's nothing to sign out to, same choice
/// main_kiosk.dart already makes.
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

class ItTechnicianStandaloneApp extends StatelessWidget {
  const ItTechnicianStandaloneApp({super.key});

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
      theme: baseTheme.copyWith(
        appBarTheme: const AppBarTheme(
          elevation: 0,
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
        ),
      ),
      home: const ItTechnicianConnectedPage(),
    );
  }
}
