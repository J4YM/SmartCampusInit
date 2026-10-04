import 'dart:async';

import 'package:flutter/widgets.dart';

/// Minimal student identity returned after an RFID lookup (host maps DB rows here).
class KioskStudentPayload {
  const KioskStudentPayload({
    required this.id,
    required this.displayName,
    required this.studentNumber,
    this.gradeSection,
    this.course,
  });

  /// `students.id` (uuid) — the internal FK, distinct from [studentNumber]
  /// (the human-facing student number), needed to write a
  /// `student_violations` row on this student's behalf.
  final String id;

  final String displayName;
  final String studentNumber;
  final String? gradeSection;
  final String? course;
}

/// Resolves a scanned RFID UID to a registered student, or returns null if invalid.
typedef IdentifyStudentFromRfid = Future<KioskStudentPayload?> Function(
  String rfidUid,
);

/// Host opens the Virtual Admission Slip flow (e.g. push a route). The
/// returned future should complete when that flow is closed (i.e. `await` the
/// pushed route) — the kiosk screen uses it to restart its Violation-mode idle
/// timer once the student comes back.
typedef OnStudentIdentifiedFromKiosk = FutureOr<void> Function(
  BuildContext context,
  KioskStudentPayload student,
);

/// Result of recording an attendance tap for a scanned RFID UID.
class KioskAttendanceTapResult {
  const KioskAttendanceTapResult({required this.student, required this.direction});

  /// Null when the card doesn't match a registered student.
  final KioskStudentPayload? student;

  /// `'in'` or `'out'` — mirrors `rfid_tap_events.tap_direction`.
  final String direction;
}

/// Records an attendance tap for a scanned RFID UID (the host decides how —
/// e.g. Supabase's `record_rfid_tap`, which owns the in/out toggle).
///
/// Throws [AttendanceTapRejected] for a tap disallowed by business rules
/// (tapping out too soon after tapping in, or already having tapped in and
/// out today) — the kiosk screen shows that message directly rather than
/// its generic "check network" fallback.
typedef RecordAttendanceTapFromRfid = Future<KioskAttendanceTapResult> Function(
  String rfidUid,
);

/// Thrown by a [RecordAttendanceTapFromRfid] implementation when a tap is
/// rejected by a business rule rather than failing technically (network,
/// Supabase config) — [message] is a complete, student-facing sentence.
class AttendanceTapRejected implements Exception {
  AttendanceTapRejected(this.message);
  final String message;

  @override
  String toString() => message;
}
