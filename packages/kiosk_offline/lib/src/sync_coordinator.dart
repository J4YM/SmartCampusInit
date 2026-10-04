import 'dart:async';

import 'connectivity_monitor.dart';
import 'outbox.dart';
import 'reference_sync.dart';

/// Owns the timers: probe connectivity, drain the outbox, refresh reference
/// data. Probes every [busyInterval] while offline or while writes are
/// pending, every [idleInterval] otherwise.
class SyncCoordinator {
  SyncCoordinator({
    required ConnectivityMonitor monitor,
    required Outbox outbox,
    required ReferenceSync reference,
    required Future<int> Function() pendingCount,
    void Function()? onChanged,
    this.idleInterval = const Duration(seconds: 60),
    this.busyInterval = const Duration(seconds: 15),
  })  : _monitor = monitor,
        _outbox = outbox,
        _reference = reference,
        _pendingCount = pendingCount,
        _onChanged = onChanged;

  final ConnectivityMonitor _monitor;
  final Outbox _outbox;
  final ReferenceSync _reference;
  final Future<int> Function() _pendingCount;
  final void Function()? _onChanged;
  final Duration idleInterval;
  final Duration busyInterval;

  Timer? _timer;
  bool _stopped = false;

  void start() {
    _stopped = false;
    _schedule(Duration.zero);
  }

  void stop() {
    _stopped = true;
    _timer?.cancel();
  }

  /// One probe/drain/refresh cycle. Never throws.
  Future<void> tick() async {
    try {
      final wasOnline = _monitor.isOnline;
      final online = await _monitor.check();
      if (online) {
        await _outbox.drain(force: !wasOnline);
        await _reference.refreshIfDue(force: !wasOnline);
      }
    } catch (_) {
      // A cycle failing must not kill the timer; the next one retries.
    }
    _onChanged?.call();
  }

  /// Called right after a write is queued while online.
  void requestDrain() {
    unawaited(() async {
      try {
        await _outbox.drain(force: true);
      } catch (_) {}
      _onChanged?.call();
    }());
  }

  void _schedule(Duration delay) {
    _timer?.cancel();
    _timer = Timer(delay, () async {
      await tick();
      if (_stopped) return;
      final busy = !_monitor.isOnline || await _pendingCount() > 0;
      if (!_stopped) _schedule(busy ? busyInterval : idleInterval);
    });
  }
}
