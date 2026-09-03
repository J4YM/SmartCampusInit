import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'env.dart';

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
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text(
            AttendanceEnv.configured
                ? 'Attendance Display — waiting for taps'
                : 'Not configured — check .env',
            style: const TextStyle(color: Colors.white, fontSize: 20),
          ),
        ),
      ),
    );
  }
}
