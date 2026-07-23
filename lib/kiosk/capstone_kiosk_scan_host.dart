import 'package:flutter/material.dart';
import 'package:kiosk/kiosk_module.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:virtual_admission_slip/virtual_admission_slip.dart';

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
          gradeSection: '${student.yearLevel} — ${student.section}',
          course: student.course,
        );
      },
      onStudentIdentified: (ctx, payload) {
        final now = DateTime.now();
        final validUntil = now.add(const Duration(hours: 72));
        Navigator.of(ctx).push(
          MaterialPageRoute<void>(
            builder: (_) => AdmissionSlipGeneratedView(
              data: AdmissionSlipData(
                studentName: payload.displayName,
                studentNumber: payload.studentNumber,
                gradeSection: payload.gradeSection ?? '{{gradeSection}}',
                slipId: 'VAS-${payload.studentNumber}-${now.millisecondsSinceEpoch}',
                violationCode: 'PENDING',
                violationDescription: 'Acknowledged at kiosk — violation details pending DO review.',
                issueDateTime: _formatDateTime(now),
                validUntil: _formatDateTime(validUntil),
                timeRemaining: '72 hours',
              ),
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

String _formatDateTime(DateTime dt) {
  final local = dt.toLocal();
  final h = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final ampm = local.hour >= 12 ? 'PM' : 'AM';
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '${local.year}-$month-$day ${h.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')} $ampm';
}
