import 'dart:convert';

import 'kiosk_database.dart';
import 'kiosk_offline_api.dart';
import 'kiosk_remote.dart';
import 'tap_rules.dart';

/// Records attendance taps.
///
/// Online with an empty outbox: ask the server (authoritative — it also knows
/// taps from other readers) and mirror its answer locally. Offline, on a
/// transient failure, or when older entries are still queued (so the server
/// sees taps in order): decide locally with [TapRules] and queue the tap for
/// replay with its true timestamp.
class TapEngine {
  TapEngine({
    required KioskDatabase db,
    required KioskRemote remote,
    required TapRules rules,
    required String readerUsbSerial,
    required bool Function() isOnline,
    void Function()? onTransientFailure,
    DateTime Function()? now,
    Duration remoteTimeout = const Duration(seconds: 3),
  })  : _db = db,
        _remote = remote,
        _rules = rules,
        _serial = readerUsbSerial,
        _isOnline = isOnline,
        _onTransientFailure = onTransientFailure,
        _now = now ?? DateTime.now,
        _remoteTimeout = remoteTimeout;

  final KioskDatabase _db;
  final KioskRemote _remote;
  final TapRules _rules;
  final String _serial;
  final bool Function() _isOnline;
  final void Function()? _onTransientFailure;
  final DateTime Function() _now;
  final Duration _remoteTimeout;

  Future<TapOutcome> recordTap(String rfidUid) async {
    final uid = rfidUid.trim();
    final tappedAt = _now().toUtc();

    if (_isOnline() && await _db.pendingCount() == 0) {
      try {
        final r = await _remote
            .recordTap(readerUsbSerial: _serial, rfidUid: uid, tappedAt: tappedAt)
            .timeout(_remoteTimeout);
        final studentId = r.studentId;
        if (studentId != null) {
          await _db.insertLocalTap(
            studentId: studentId,
            direction: r.direction,
            tappedAt: r.tappedAt,
          );
        }
        return TapOutcome(
          direction: r.direction,
          studentId: studentId,
          student: studentId == null ? null : await _db.studentById(studentId),
        );
      } on RemoteRejected catch (e) {
        throw TapRejectedException(e.message);
      } on Object {
        // Network failure, timeout, 5xx: fall through to the local path.
        _onTransientFailure?.call();
      }
    }

    return _recordLocally(uid, tappedAt);
  }

  Future<TapOutcome> _recordLocally(String uid, DateTime tappedAt) async {
    final student = await _db.studentByRfid(uid);

    if (student == null) {
      await _db.enqueue('tap', _payload(uid, tappedAt, null), tappedAt);
      return const TapOutcome(direction: 'in', studentId: null, student: null);
    }

    final last = await _db.lastTapOnDay(student.id, schoolDayOf(tappedAt));
    final decision = _rules.decide(
      tappedAt: tappedAt,
      studentKnown: true,
      lastTapToday: last == null
          ? null
          : PriorTap(direction: last.direction, tappedAt: last.tappedAt),
    );

    switch (decision) {
      case TapDenied(:final message):
        throw TapRejectedException(message);
      case TapEchoed(:final direction):
        return TapOutcome(
            direction: direction, studentId: student.id, student: student);
      case TapAccepted(:final direction):
        await _db.transaction(() async {
          final localId = await _db.insertLocalTap(
            studentId: student.id,
            direction: direction,
            tappedAt: tappedAt,
          );
          await _db.enqueue('tap', _payload(uid, tappedAt, localId), tappedAt);
        });
        return TapOutcome(
            direction: direction, studentId: student.id, student: student);
    }
  }

  String _payload(String uid, DateTime tappedAt, int? localTapId) => jsonEncode({
        'readerUsbSerial': _serial,
        'rfidUid': uid,
        'tappedAt': tappedAt.toUtc().toIso8601String(),
        'localTapId': localTapId,
      });
}
