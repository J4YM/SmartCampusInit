import 'dart:async';

import 'package:flutter/widgets.dart';

/// How often a dashboard quietly re-reads its tables. Realtime pushes (where a
/// table is in the `supabase_realtime` publication) land instantly on top of
/// this; the poll is the safety net for every table that is not, so new data
/// never needs a manual refresh.
const Duration kAutoRefreshInterval = Duration(seconds: 15);

/// How long one refresh pass may take before it is abandoned and the next tick
/// is allowed to start a fresh one.
const Duration kAutoRefreshTimeout = Duration(seconds: 60);

/// Keeps a connected page's data fresh without anyone pressing refresh.
///
/// Call [startAutoRefresh] from `initState` with the page's *silent* reload (one
/// that does not flash a spinner, replace the page with an error screen or throw
/// away what the user is looking at), and [stopAutoRefresh] from `dispose`.
///
/// - Ticks never overlap: a slow reload is waited out, not stacked on.
/// - It rests while the app is hidden (a backgrounded tab, a minimised window)
///   and refreshes once straight away when the app comes back, so what the
///   user returns to is current.
/// - A failed tick is logged and retried on the next one.
mixin AutoRefreshMixin<T extends StatefulWidget> on State<T> {
  Timer? _autoRefreshTimer;
  AppLifecycleListener? _autoRefreshLifecycle;
  Future<void> Function()? _autoRefreshTask;
  bool _autoRefreshInFlight = false;

  /// Whether a poll is currently scheduled. Exposed for tests.
  @visibleForTesting
  bool get isAutoRefreshing => _autoRefreshTimer?.isActive ?? false;

  void startAutoRefresh(
    Future<void> Function() refresh, {
    Duration interval = kAutoRefreshInterval,
  }) {
    stopAutoRefresh();
    _autoRefreshTask = refresh;
    _autoRefreshTimer = Timer.periodic(interval, (_) => _autoRefreshTick());
    _autoRefreshLifecycle = AppLifecycleListener(
      onResume: _autoRefreshTick,
      onShow: _autoRefreshTick,
    );
  }

  void stopAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = null;
    _autoRefreshLifecycle?.dispose();
    _autoRefreshLifecycle = null;
    _autoRefreshTask = null;
  }

  Future<void> _autoRefreshTick() async {
    final task = _autoRefreshTask;
    if (task == null || !mounted || _autoRefreshInFlight) return;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle == AppLifecycleState.paused ||
        lifecycle == AppLifecycleState.hidden ||
        lifecycle == AppLifecycleState.detached) {
      return;
    }
    _autoRefreshInFlight = true;
    try {
      // A request that hangs must not stall every later refresh behind the
      // in-flight guard for good.
      await task().timeout(kAutoRefreshTimeout);
    } catch (e, st) {
      debugPrint('Auto-refresh failed (will retry): $e\n$st');
    } finally {
      _autoRefreshInFlight = false;
    }
  }

  @override
  void dispose() {
    stopAutoRefresh();
    super.dispose();
  }
}
