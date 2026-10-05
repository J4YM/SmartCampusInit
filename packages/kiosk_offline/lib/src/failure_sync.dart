import 'dart:convert';

import 'kiosk_database.dart';
import 'kiosk_remote.dart';
import 'models.dart';

/// Stable key for one outbox row on one kiosk. It is the same on every sync,
/// so the server can ignore a repeated report and a dismissal can be matched
/// back to the local row. (Includes the creation time so a rebuilt local
/// database that reuses row ids can never collide with an old dismissal.)
String failureKey(String readerUsbSerial, OutboxRow row) =>
    '$readerUsbSerial|${row.type}|${row.id}|${row.createdAt.millisecondsSinceEpoch}';

/// Lets IT Technician / Admin review and clear the items this kiosk's server
/// refused ("rejected" outbox rows), without any clear button on the kiosk.
///
/// Each [sync]:
///  1. reports every rejected row (idempotent on [failureKey]);
///  2. asks which of this kiosk's reported failures staff have dismissed and
///     deletes those local rows, which is what clears the "N failed" chip.
///
/// Best-effort and never throws: if the server (or the table, before its
/// migration has been run) is unreachable, the rows simply stay and the next
/// sync tries again — a rejected row is never lost or cleared by a failure.
class FailureSync {
  FailureSync({
    required KioskDatabase db,
    required KioskRemote remote,
    required String readerUsbSerial,
  })  : _db = db,
        _remote = remote,
        _serial = readerUsbSerial;

  final KioskDatabase _db;
  final KioskRemote _remote;
  final String _serial;

  /// Returns how many local rows were cleared because staff dismissed them.
  Future<int> sync() async {
    try {
      final rejected = await _db.rejectedEntries();
      if (rejected.isEmpty) return 0;

      final reports = <FailureReport>[
        for (final row in rejected) await _reportFor(row),
      ];
      await _remote.reportFailures(_serial, reports);

      final dismissed = await _remote.fetchDismissedFailureKeys(_serial);
      var cleared = 0;
      for (final row in rejected) {
        if (dismissed.contains(failureKey(_serial, row))) {
          await _db.deleteOutbox(row.id);
          cleared++;
        }
      }
      return cleared;
    } on Object {
      return 0;
    }
  }

  Future<FailureReport> _reportFor(OutboxRow row) async {
    Map<String, dynamic>? payload;
    try {
      payload = jsonDecode(row.payload) as Map<String, dynamic>;
    } on Object {
      payload = null; // Unparseable payload: still worth showing to staff.
    }

    String? rfidUid;
    String? studentId;
    var occurredAt = row.createdAt;
    var kind = row.type == 'slip' ? 'slip' : 'tap';

    if (payload != null) {
      try {
        if (row.type == 'tap') {
          rfidUid = payload['rfidUid'] as String?;
          final at = payload['tappedAt'] as String?;
          if (at != null) occurredAt = DateTime.parse(at);
        } else if (row.type == 'slip') {
          studentId = payload['studentId'] as String?;
        }
      } on Object {
        // Keep whatever was read; the reason text is what matters.
      }
    }

    OfflineStudent? student;
    try {
      if (rfidUid != null) student = await _db.studentByRfid(rfidUid);
      if (student == null && studentId != null) {
        student = await _db.studentById(studentId);
      }
    } on Object {
      student = null;
    }

    return FailureReport(
      clientKey: failureKey(_serial, row),
      kind: kind,
      occurredAt: occurredAt,
      reason: (row.lastError == null || row.lastError!.trim().isEmpty)
          ? 'Rejected by the server.'
          : row.lastError!,
      rfidUid: rfidUid,
      studentId: student?.id ?? studentId,
      studentName: student?.fullName,
      payload: payload ?? {'raw': row.payload},
    );
  }
}
