import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'env.dart';
import 'tap_display_screen.dart';
import 'tap_feed_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env', isOptional: true);
  AttendanceEnv.resolve();

  if (AttendanceEnv.configured) {
    await Supabase.initialize(
      url: AttendanceEnv.supabaseUrl,
      anonKey: AttendanceEnv.supabaseAnonKey,
    );
    await Supabase.instance.client.auth.signInWithPassword(
      email: AttendanceEnv.serviceEmail,
      password: AttendanceEnv.servicePassword,
    );
  }

  runApp(const AttendanceDisplayApp());
}

class AttendanceDisplayApp extends StatelessWidget {
  const AttendanceDisplayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
      home: AttendanceEnv.configured
          ? Builder(builder: (context) {
              final controller = TapFeedController(Supabase.instance.client);
              controller.start();
              return TapDisplayScreen(tapStream: controller.stream);
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
