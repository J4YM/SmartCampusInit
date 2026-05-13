import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'screens/violation_kiosk_screen.dart';

void main() {
  runApp(const StudentKioskApp());
}

class StudentKioskApp extends StatelessWidget {
  const StudentKioskApp({super.key});

  @override
  Widget build(BuildContext context) {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF00158A),
        brightness: Brightness.light,
      ),
    );

    return MaterialApp(
      title: 'Virtual Admission Kiosk',
      debugShowCheckedModeBanner: false,
      theme: base.copyWith(
        textTheme: GoogleFonts.poppinsTextTheme(base.textTheme),
        scaffoldBackgroundColor: const Color(0xFFF0F4FF),
      ),
      home: const ViolationKioskScreen(),
    );
  }
}
