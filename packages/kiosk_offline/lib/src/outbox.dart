import 'dart:convert';

import 'kiosk_database.dart';
import 'kiosk_remote.dart';
import 'models.dart';

class DrainReport {
  const DrainReport({required this.processed, required this.blocked});

  /// Entries removed from the pending queue this call (sent or parked).
  final int processed;

  /// True when a transient failure (or an active backoff) stopped the drain.
  final bool blocked;
}

/// Replays queued writes to the server in strict queue order.
///
/// - success: the row is deleted;
/// - [RemoteRejected]: the row is parked as `rejected` (never retried) and
///   the queue moves on;
/// - anything else (network, timeout, 5xx): the row stays, the drain stops,
///   and the next attempt waits an exponentially growing backoff.
class Outbox {
  Outbox({
    required KioskDatabase db,
    required KioskRemote remote,
    DateTime Function()? now,
    this.baseBackoff = const Duration(seconds: 2),
    this.maxBackoff = const Duration(seconds: 60),
  })  : _db = db,
        _remote = remote,
        _now = now ?? DateTime.now;

  final KioskDatabase _db;
  final KioskRemote _remote;
  final DateTime Function() _now;
  final Duration baseBackoff;
  final Duration maxBackoff;

  bool _draining = false;
  int _failures = 0;
  DateTime? _nextAttemptAt;

  Future<DrainReport> drain({bool force = false}) async {
    if (_draining) return const DrainReport(processed: 0, blocked: false);
    final next = _nextAttemptAt;
    if (!force && next != null && _now().isBefore(next)) {
      return const DrainReport(processed: 0, blocked: true);
    }

    _draining = true;
    var processed = 0;
    try {
      while (true) {
        final entry = await _db.nextPending();
        if (entry == null) break;
        try {
          await _send(entry);
          await _db.deleteOutbox(entry.id);
          processed++;
          _failures = 0;
          _nextAttemptAt = null;
        } on RemoteRejected catch (e) {
          await _db.markRejected(entry.id, e.message);
          await _dropLocalTap(entry);
          processed++;
        } catch (e) {
          await _db.recordAttempt(entry.id, e.toString());
          _failures++;
          final scaled = baseBackoff * (1 << (_failures - 1).clamp(0, 10));
          final delay = scaled > maxBackoff ? maxBackoff : scaled;
          _nextAttemptAt = _now().add(delay);
          return DrainReport(processed: processed, blocked: true);
        }
      }
      return DrainReport(processed: processed, blocked: false);
    } finally {
      _draining = false;
    }
  }

  Future<void> _send(OutboxRow entry) async {
    final json = jsonDecode(entry.payload) as Map<String, dynamic>;
    switch (entry.type) {
      case 'tap':
        final r = await _remote.recordTap(
          readerUsbSerial: json['readerUsbSerial'] as String,
          rfidUid: json['rfidUid'] as String,
          tappedAt: DateTime.parse(json['tappedAt'] as String),
        );
        final localId = json['localTapId'] as int?;
        if (localId != null) {
          // The server is authoritative (it also sees other readers' taps).
          await _db.setLocalTapDirection(localId, r.direction);
        }
      case 'slip':
        await _remote.submitSlip(SlipSubmission.fromJson(json));
      default:
        throw RemoteRejected('Unknown outbox entry type "${entry.type}".');
    }
  }

  /// A refused tap must not keep influencing the offline rules.
  Future<void> _dropLocalTap(OutboxRow entry) async {
    if (entry.type != 'tap') return;
    try {
      final json = jsonDecode(entry.payload) as Map<String, dynamic>;
      final localId = json['localTapId'] as int?;
      if (localId != null) await _db.deleteLocalTap(localId);
    } on FormatException {
      // Unparseable payload: nothing to clean up.
    }
  }
}
