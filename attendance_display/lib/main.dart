import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'env.dart';
import 'reader_input_field.dart';
import 'tap_display_screen.dart';
import 'tap_feed_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env', isOptional: true);
  AttendanceEnv.resolve();

  // This is an unattended display with no operator console: if startup
  // (network not up yet at boot, wrong credentials, etc.) throws before
  // runApp, the screen would otherwise stay permanently blank with no way
  // to diagnose it on-site. Always reach runApp, and surface the error
  // visibly instead.
  String? startupError;
  if (AttendanceEnv.configured) {
    try {
      await Supabase.initialize(
        url: AttendanceEnv.supabaseUrl,
        anonKey: AttendanceEnv.supabaseAnonKey,
      );
      await Supabase.instance.client.auth.signInWithPassword(
        email: AttendanceEnv.serviceEmail,
        password: AttendanceEnv.servicePassword,
      );
    } catch (e) {
      startupError = e.toString();
    }
  }

  runApp(AttendanceDisplayApp(startupError: startupError));
}

class AttendanceDisplayApp extends StatelessWidget {
  const AttendanceDisplayApp({super.key, this.startupError});

  /// Set when Supabase initialization/sign-in threw during startup. Shown
  /// instead of the normal display so this unattended kiosk never just
  /// goes silently blank with no way to diagnose it on-site.
  final String? startupError;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
      home: startupError != null
          ? Scaffold(
              backgroundColor: Colors.black,
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Startup error — check network/credentials',
                        style: TextStyle(color: Colors.white, fontSize: 22),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        startupError!,
                        style: const TextStyle(color: Colors.white70, fontSize: 14),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            )
          : AttendanceEnv.configured
              ? Builder(builder: (context) {
                  final controller = TapFeedController(Supabase.instance.client);
                  controller.start();
                  return ReaderInputCapture(
                    child: TapDisplayScreen(tapStream: controller.stream),
                  );
                })
              : const Scaffold(
                  backgroundColor: Colors.black,
                  body: Center(
                    child: Text(
                      'Not configured — check .env',
                      style: TextStyle(color: Colors.white, fontSize: 20),
                    ),
                  ),
                ),
    );
  }
}
