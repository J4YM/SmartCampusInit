import 'dart:async';
import 'dart:convert';

import 'connectivity_monitor.dart';
import 'kiosk_database.dart';
import 'kiosk_offline_api.dart';
import 'kiosk_remote.dart';
import 'models.dart';
import 'outbox.dart';
import 'reference_sync.dart';
import 'sync_coordinator.dart';
import 'tap_engine.dart';
import 'tap_rules.dart';

class KioskOfflineImpl implements KioskOffline {
  KioskOfflineImpl({
    required KioskDatabase db,
    required KioskRemote remote,
    required String readerUsbSerial,
    TapRules rules = const TapRules(),
    DateTime Function()? now,
  })  : _db = db,
        _remote = remote,
        _now = now ?? DateTime.now {
    _monitor = ConnectivityMonitor(ping: remote.ping);
    _outbox = Outbox(db: db, remote: remote, now: _now);
    _reference = ReferenceSync(db: db, remote: remote, now: _now);
    _engine = TapEngine(
      db: db,
      remote: remote,
      rules: rules,
      readerUsbSerial: readerUsbSerial,
      isOnline: () => _monitor.isOnline,
      onTransientFailure: _monitor.markOffline,
      now: _now,
    );
    _coordinator = SyncCoordinator(
      monitor: _monitor,
      outbox: _outbox,
      reference: _reference,
      pendingCount: db.pendingCount,
      onChanged: () => unawaited(_emit()),
    );
  }

  final KioskDatabase _db;
  final KioskRemote _remote;
  final DateTime Function() _now;
  late final ConnectivityMonitor _monitor;
  late final Outbox _outbox;
  late final ReferenceSync _reference;
  late final TapEngine _engine;
  late final SyncCoordinator _coordinator;
  final _status = StreamController<SyncStatus>.broadcast();
  bool _disposed = false;

  /// Tail of the recordTap queue. TapEngine.recordTap is not re-entrant (two
  /// concurrent calls could both read the last tap before either writes and
  /// bypass the debounce), so calls run strictly one after another.
  Future<void> _tapQueue = Future<void>.value();

  /// Begins the background probe/drain/refresh loop.
  Future<void> start() async => _coordinator.start();

  /// One immediate probe + drain + refresh cycle (used by tests and startup).
  Future<void> syncNow() => _coordinator.tick();

  @override
  Future<OfflineStudent?> identifyStudent(String rfidUid) =>
      _db.studentByRfid(rfidUid);

  @override
  Future<OfflineStaff?> identifyStaff(String rfidCardId) =>
      _db.staffByCard(rfidCardId);

  @override
  Future<List<OfflineStudent>> searchStudents(String numberPrefix, {int limit = 8}) =>
      _db.searchStudents(numberPrefix, limit: limit);

  @override
  Future<List<OfflineOffense>> offenses() => _db.offenses();

  @override
  Future<List<OfflineTeacher>> teachers() => _db.teachers();

  @override
  Future<TapOutcome> recordTap(String rfidUid) {
    final run = _tapQueue.then((_) async {
      try {
        return await _engine.recordTap(rfidUid);
      } finally {
        await _afterWrite();
      }
    });
    // Errors belong to this call's caller only; never poison the queue.
    _tapQueue = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  @override
  Future<void> submitSlip(SlipSubmission slip) async {
    if (_monitor.isOnline && await _db.pendingCount() == 0) {
      try {
        await _remote.submitSlip(slip).timeout(const Duration(seconds: 5));
        return;
      } on RemoteRejected {
        rethrow;
      } on Object {
        _monitor.markOffline();
      }
    }
    await _db.enqueue('slip', jsonEncode(slip.toJson()), _now());
    await _afterWrite();
  }

  /// Best-effort bookkeeping after a write (status push, drain kick). It runs
  /// in `finally` blocks and after enqueue, so it must never throw: a failing
  /// status query must not replace the caller's real result or error.
  Future<void> _afterWrite() async {
    try {
      await _emit();
      if (_disposed) return;
      if (_monitor.isOnline && await _db.pendingCount() > 0) {
        _coordinator.requestDrain();
      }
    } on Object {
      // Notification only.
    }
  }

  Future<void> _emit() async {
    if (_disposed || _status.isClosed) return;
    try {
      final s = await currentStatus();
      // Disposal can happen while the status query is in flight.
      if (_disposed || _status.isClosed) return;
      _status.add(s);
    } on Object {
      // Transient DB trouble or shutdown: the next event will carry fresh state.
    }
  }

  @override
  Future<SyncStatus> currentStatus() async => SyncStatus(
        online: _monitor.isOnline,
        pending: await _db.pendingCount(),
        rejected: await _db.rejectedCount(),
      );

  @override
  Stream<SyncStatus> get status => _status.stream;

  @override
  Future<List<OutboxDiagnostic>> diagnostics() => _db.diagnostics();

  @override
  Future<void> dispose() async {
    _disposed = true;
    _coordinator.stop();
    _monitor.dispose();
    await _status.close();
    await _db.close();
  }
}
