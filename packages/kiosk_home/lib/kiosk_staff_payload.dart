import 'package:flutter/widgets.dart';

/// Minimal staff identity returned after an RFID lookup that didn't match a
/// student (host maps DB rows here) — lets the kiosk branch into a
/// staff-specific flow (e.g. Security Personnel reporting) instead of the
/// student admission-slip flow.
class KioskStaffPayload {
  const KioskStaffPayload({
    required this.id,
    required this.displayName,
    required this.roleLabel,
  });

  /// `profiles.id` (uuid) — needed to attribute a report to this staff
  /// member (e.g. `student_violations.reported_by`).
  final String id;

  final String displayName;

  /// e.g. "Security Personnel" — shown on the staff-mode screen and used by
  /// the host to decide which staff flow to open (only Security Personnel
  /// is wired today; other staff roles fall back to "not supported here").
  final String roleLabel;
}

/// Resolves a scanned RFID UID to a staff member, or returns null if it
/// doesn't match any registered staff RFID either. Only consulted when
/// [identifyStudent] (see kiosk_student_payload.dart) already returned null.
typedef IdentifyStaffFromRfid = Future<KioskStaffPayload?> Function(
  String rfidUid,
);

/// Host opens the staff-specific flow (e.g. Security Personnel reporting).
typedef OnStaffIdentifiedFromKiosk = void Function(
  BuildContext context,
  KioskStaffPayload staff,
);
