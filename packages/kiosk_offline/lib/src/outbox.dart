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
    this.sendTimeout = const Duration(seconds: 10),
  })  : _db = db,
        _remote = remote,
        _now = now ?? DateTime.now;

  final KioskDatabase _db;
  final KioskRemote _remote;
  final DateTime Function() _now;
  final Duration baseBackoff;
  final Duration maxBackoff;

  /// Upper bound for one send so a half-open connection cannot hold the
  /// drain lock forever (a timeout counts as a transient failure).
  final Duration sendTimeout;

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
          try {
            await _db.markRejected(entry.id, e.message);
            await _dropLocalTap(entry);
          } catch (_) {
            // Local DB trouble: leave the row pending and back off.
            _scheduleBackoff();
            return DrainReport(processed: processed, blocked: true);
          }
          processed++;
        } catch (e) {
          // Backoff first so a failing bookkeeping write cannot skip it.
          _scheduleBackoff();
          try {
            await _db.recordAttempt(entry.id, e.toString());
          } catch (_) {
            // Diagnostics only; the backoff is already recorded.
          }
          return DrainReport(processed: processed, blocked: true);
        }
      }
      return DrainReport(processed: processed, blocked: false);
    } finally {
      _draining = false;
    }
  }

  void _scheduleBackoff() {
    _failures++;
    final scaled = baseBackoff * (1 << (_failures - 1).clamp(0, 10));
    final delay = scaled > maxBackoff ? maxBackoff : scaled;
    _nextAttemptAt = _now().add(delay);
  }

  Future<void> _send(OutboxRow entry) async {
    // Parse first: a payload that can never parse must be parked, not retried.
    final Map<String, dynamic> json;
    String? readerUsbSerial;
    String? rfidUid;
    DateTime? tappedAt;
    int? localId;
    SlipSubmission? slip;
    try {
      json = jsonDecode(entry.payload) as Map<String, dynamic>;
      switch (entry.type) {
        case 'tap':
          readerUsbSerial = json['readerUsbSerial'] as String;
          rfidUid = json['rfidUid'] as String;
          tappedAt = DateTime.parse(json['tappedAt'] as String);
          localId = json['localTapId'] as int?;
        case 'slip':
          slip = SlipSubmission.fromJson(json);
      }
    } on Object catch (e) {
      throw RemoteRejected('Malformed outbox payload: $e');
    }

    switch (entry.type) {
      case 'tap':
        final r = await _remote
            .recordTap(
              readerUsbSerial: readerUsbSerial!,
              rfidUid: rfidUid!,
              tappedAt: tappedAt!,
            )
            .timeout(sendTimeout);
        if (localId != null) {
          // The server is authoritative (it also sees other readers' taps).
          // The local direction is only a provisional hint: the server has
          // already accepted the tap, so a failure here must never re-send it.
          try {
            await _db.setLocalTapDirection(localId, r.direction);
          } catch (_) {}
        }
      case 'slip':
        await _remote.submitSlip(slip!).timeout(sendTimeout);
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
    } on TypeError {
      // Unparseable payload: nothing to clean up.
    }
  }
}
