import 'dart:async';

/// Tracks whether the server is actually reachable. [ping] should be a cheap
/// request to the real backend (adapter state is not enough: "connected, no
/// internet" is the common failure).
class ConnectivityMonitor {
  ConnectivityMonitor({required Future<bool> Function() ping}) : _ping = ping;

  final Future<bool> Function() _ping;
  final _controller = StreamController<bool>.broadcast();
  bool _online = false;

  bool get isOnline => _online;

  /// Emits only when the state changes.
  Stream<bool> get changes => _controller.stream;

  Future<bool> check() async {
    bool ok;
    try {
      ok = await _ping();
    } catch (_) {
      ok = false;
    }
    _set(ok);
    return ok;
  }

  /// A real request just failed transiently — stop trusting "online" until
  /// the next successful probe.
  void markOffline() => _set(false);

  void _set(bool value) {
    if (value == _online) return;
    _online = value;
    if (!_controller.isClosed) _controller.add(value);
  }

  void dispose() => _controller.close();
}
