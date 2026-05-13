import 'package:flutter/widgets.dart';

/// Minimal student identity returned after an RFID lookup (host maps DB rows here).
class KioskStudentPayload {
  const KioskStudentPayload({
    required this.displayName,
    required this.studentNumber,
  });

  final String displayName;
  final String studentNumber;
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
