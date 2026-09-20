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

/// Host opens the Virtual Admission Slip flow (e.g. push a route).
typedef OnStudentIdentifiedFromKiosk = void Function(
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
typedef RecordAttendanceTapFromRfid = Future<KioskAttendanceTapResult> Function(
  String rfidUid,
);
