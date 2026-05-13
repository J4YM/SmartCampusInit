import 'package:flutter/material.dart';
import 'package:kiosk/kiosk_module.dart';
import 'package:student_kiosk_module/student_kiosk.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/students_repository.dart';
import '../env.dart';

/// Wires [VirtualAdmissionKioskScreen] to Supabase and the Student Virtual Admission Slip UI.
class CapstoneKioskScanHost extends StatelessWidget {
  const CapstoneKioskScanHost({
    super.key,
    this.embedFromHub = false,
  });

  /// When true, shows a back control for returning to the admin hub.
  final bool embedFromHub;

  @override
  Widget build(BuildContext context) {
    final scan = VirtualAdmissionKioskScreen(
      identifyStudent: (uid) async {
        if (!AppEnv.supabaseConfigured) return null;
        final repo = StudentsRepository(Supabase.instance.client);
        final student = await repo.fetchStudentByRfidUid(uid);
        if (student == null) return null;
        return KioskStudentPayload(
          displayName: student.fullName,
          studentNumber: student.studentNumber,
        );
      },
      onStudentIdentified: (ctx, payload) {
        Navigator.of(ctx).push(
          MaterialPageRoute<void>(
            builder: (_) => ViolationKioskScreen(
              studentName: payload.displayName,
              studentId: payload.studentNumber,
            ),
          ),
        );
      },
    );

    late final Widget body;
    if (!AppEnv.supabaseConfigured) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Material(
            color: Color(0xFFFEF3C7),
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Supabase is not configured (.env or dart-define). '
                'RFID lookup cannot run on this kiosk build.',
                style: TextStyle(color: Color(0xFF92400E), fontSize: 13),
              ),
            ),
          ),
          Expanded(child: scan),
        ],
      );
    } else {
      body = scan;
    }

    if (!embedFromHub) {
      return body;
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        body,
        SafeArea(
          child: Align(
            alignment: Alignment.topLeft,
            child: IconButton(
              tooltip: 'Back to hub',
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
        ),
      ],
    );
  }
}
