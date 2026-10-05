import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists just enough UI state across a browser reload (web) / app
/// restart (other platforms) that the user lands back roughly where they
/// were, instead of at the login screen. Two independent concerns:
///
///  - WHO is signed in, for the static demo accounts specifically (see
///    [demoUsername]) — a real Supabase/Microsoft session already
///    persists itself (`supabase_flutter`'s own localStorage-backed auth
///    token), but [StaticDemoAccounts] sign-in never touches Supabase at
///    all, so nothing about it survives a reload unless this class does
///    it explicitly.
///  - WHICH page the signed-in user was on (see [navState]) — this app
///    has no URL-based routing (a single-page `MaterialApp`, not
///    `MaterialApp.router`), so "which page" can't be read back from the
///    browser's address bar; it's tracked as a small set of named
///    breadcrumbs instead (e.g. "which Admin Hub module", "which
///    Registrar tab"), one independent string per call site.
///
/// Backed by `shared_preferences`, which resolves to browser `localStorage`
/// on web (the platform this actually matters for) and a plain file
/// elsewhere — safe to use identically on every platform.
class AppStatePersistence {
  AppStatePersistence._(this._prefs);

  static AppStatePersistence? _instance;

  /// Lazily creates and caches the single instance for the app's lifetime
  /// — `SharedPreferences.getInstance()` itself is already cached
  /// internally by the plugin, but every call site awaiting its own
  /// fresh `instance()` call would still redundantly re-await that each
  /// time; caching here keeps call sites simple (`await
  /// AppStatePersistence.instance()`) without worrying about that.
  static Future<AppStatePersistence> instance() async {
    final existing = _instance;
    if (existing != null) return existing;
    final prefs = await SharedPreferences.getInstance();
    final created = AppStatePersistence._(prefs);
    _instance = created;
    return created;
  }

  final SharedPreferences _prefs;

  /// Drops the cached singleton so the next [instance] call re-reads from
  /// `SharedPreferences` instead of returning a stale object — otherwise
  /// `SharedPreferences.setMockInitialValues` between tests would have no
  /// effect once this class had already cached an instance once.
  @visibleForTesting
  static void resetForTesting() => _instance = null;

  static const _demoUsernameKey = 'app.demoUsername';
  static const _navPrefix = 'app.nav.';

  String? get demoUsername => _prefs.getString(_demoUsernameKey);

  Future<void> setDemoUsername(String? username) async {
    if (username == null) {
      await _prefs.remove(_demoUsernameKey);
    } else {
      await _prefs.setString(_demoUsernameKey, username);
    }
  }

  /// Reads the breadcrumb stored under [key] (e.g. `'adminModule'`,
  /// `'registrarTab'`) — each call site owns its own independent slot,
  /// so none of them need to know about any other.
  String? navState(String key) => _prefs.getString('$_navPrefix$key');

  Future<void> setNavState(String key, String? value) async {
    final fullKey = '$_navPrefix$key';
    if (value == null) {
      await _prefs.remove(fullKey);
    } else {
      await _prefs.setString(fullKey, value);
    }
  }

  /// Clears every persisted nav breadcrumb — called on sign-out so a
  /// different user (or the same one, a different role, via a different
  /// demo account) signing in next on this browser doesn't inherit a
  /// stale "which tab/module were they on" left over from whoever used
  /// it last.
  Future<void> clearAllNavState() async {
    final keys = _prefs.getKeys().where((k) => k.startsWith(_navPrefix)).toList();
    for (final key in keys) {
      await _prefs.remove(key);
    }
  }
}
