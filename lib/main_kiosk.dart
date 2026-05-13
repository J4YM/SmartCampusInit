import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'env.dart';
import 'kiosk/capstone_kiosk_scan_host.dart';
import 'util/load_local_env.dart';

/// Dedicated kiosk device entry: no staff login — only RFID gate + admission slip flow.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await loadLocalEnv();
  AppEnv.resolve();

  if (AppEnv.supabaseConfigured) {
    await Supabase.initialize(
      url: AppEnv.supabaseUrl,
      anonKey: AppEnv.supabaseAnonKey,
    );
    debugPrint('Kiosk mode: Supabase initialized for ${Uri.parse(AppEnv.supabaseUrl).host}.');
  } else {
    debugPrint(
      'Kiosk mode: Supabase not configured. RFID validation will fail until '
      'SUPABASE_URL and SUPABASE_ANON_KEY are provided.',
    );
  }

  runApp(const KioskStandaloneApp());
}

class KioskStandaloneApp extends StatelessWidget {
  const KioskStandaloneApp({super.key});

  @override
  Widget build(BuildContext context) {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF001A99),
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: const Color(0xFFF5F7FB),
      textTheme: GoogleFonts.interTextTheme(),
    );

    return MaterialApp(
      title: 'STI Baliuag — Kiosk',
      debugShowCheckedModeBanner: false,
      theme: base,
      home: const CapstoneKioskScanHost(embedFromHub: false),
    );
  }
}
