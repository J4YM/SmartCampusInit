import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'kiosk_student_payload.dart';
import 'virtual_admission_kiosk_screen.dart';

void main() {
  runApp(const KioskApp());
}

/// Standalone kiosk shell (e.g. `flutter run` inside this package). Host apps should
/// pass [identifyStudent] / [onStudentIdentified] for database-backed RFID flow.
class KioskApp extends StatelessWidget {
  const KioskApp({
    super.key,
    this.identifyStudent,
    this.onStudentIdentified,
  });

  final IdentifyStudentFromRfid? identifyStudent;
  final OnStudentIdentifiedFromKiosk? onStudentIdentified;

  static Future<KioskStudentPayload?> _defaultNeverIdentify(String _) async => null;

  static void _defaultNoop(BuildContext context, KioskStudentPayload student) {}

  @override
  Widget build(BuildContext context) {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF001A99)),
    );
    return MaterialApp(
      title: 'Virtual Admission Kiosk',
      debugShowCheckedModeBanner: false,
      theme: base.copyWith(
        textTheme: GoogleFonts.poppinsTextTheme(base.textTheme),
      ),
      home: VirtualAdmissionKioskScreen(
        identifyStudent: identifyStudent ?? _defaultNeverIdentify,
        onStudentIdentified: onStudentIdentified ?? _defaultNoop,
      ),
    );
  }
}
