import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../env.dart';

/// Result of asking whether this sign-in session may attempt a password
/// sign-in.
class LoginLockStatus {
  const LoginLockStatus({
    required this.locked,
    this.lockedUntil,
    this.remaining = LoginAttemptGuard.maxAttempts,
  });

  final bool locked;
  final DateTime? lockedUntil;

  /// Failed attempts left before the session locks.
  final int remaining;

  /// Whole minutes left on the lock, rounded up (at least 1 while locked).
  int get minutesLeft {
    final until = lockedUntil;
    if (until == null) return 0;
    final secs = until.difference(DateTime.now()).inSeconds;
    return secs <= 0 ? 1 : (secs / 60).ceil();
  }
}

/// Limits password sign-in to [maxAttempts] failures per sign-in SESSION
/// before a [lockout]. The limit belongs to the session making the attempts
/// (this browser/device), not to the account name: another person signing in
/// to the same account from a different session is never locked out by it.
///
/// A session is a random id generated the first time the app runs on a
/// device and kept in shared preferences. Two layers, the stricter wins:
///
///  * Server: the `login_lock_status` / `record_failed_login` RPCs in
///    `supabase/add_login_lockout.sql` hold the counter by session id (so it
///    survives a reload) and queue the security email on the lock.
///  * Local: a copy in shared preferences, used when Supabase is unconfigured
///    or unreachable.
///
/// Clearing site data starts a new session, so this limits guessing per
/// session — it is not an account- or IP-level control.
class LoginAttemptGuard {
  LoginAttemptGuard._();

  static const int maxAttempts = 3;
  static const Duration lockout = Duration(minutes: 15);
  static const Duration _window = Duration(minutes: 15);

  static const _sessionKey = 'app.loginSessionId';
  static const _stateKey = 'app.loginGuard';

  static Future<String> _sessionId(SharedPreferences prefs) async {
    final existing = prefs.getString(_sessionKey);
    if (existing != null && existing.length >= 16) return existing;
    final rng = Random.secure();
    final id = base64UrlEncode(List<int>.generate(24, (_) => rng.nextInt(256)));
    await prefs.setString(_sessionKey, id);
    return id;
  }

  static Future<LoginLockStatus> check() async {
    final prefs = await SharedPreferences.getInstance();
    final session = await _sessionId(prefs);
    final local = _localStatus(prefs);
    final remote = await _remoteStatus(session);
    return _stricter(local, remote);
  }

  /// Counts one failed attempt for this session and returns the resulting
  /// status. On the attempt that reaches [maxAttempts] the server also sends
  /// the alert email. [username] only names the account that was targeted.
  ///
  /// With [accountExists] false (the name belongs to no account) nothing is
  /// counted and the current status is returned unchanged: typing a name nobody
  /// owns must never lock the session out, only wrong passwords for real
  /// accounts do. A session that is already locked stays locked.
  static Future<LoginLockStatus> recordFailure(
    String username, {
    bool accountExists = true,
  }) async {
    if (!accountExists) return check();
    final prefs = await SharedPreferences.getInstance();
    final session = await _sessionId(prefs);
    final local = await _localRecordFailure(prefs);
    final name = username.trim().toLowerCase();
    final remote = await _remoteRecordFailure(
      session,
      name.length > 100 ? name.substring(0, 100) : name,
    );
    return _stricter(local, remote);
  }

  static LoginLockStatus _stricter(LoginLockStatus a, LoginLockStatus? b) {
    if (b == null) return a;
    if (a.locked && b.locked) {
      final au = a.lockedUntil, bu = b.lockedUntil;
      if (au == null || bu == null) return a;
      return au.isAfter(bu) ? a : b;
    }
    if (a.locked) return a;
    if (b.locked) return b;
    return a.remaining <= b.remaining ? a : b;
  }

  // -- server --------------------------------------------------------------

  static Future<LoginLockStatus?> _remoteStatus(String session) async {
    if (!AppEnv.supabaseConfigured) return null;
    try {
      final res = await Supabase.instance.client
          .rpc('login_lock_status', params: {'p_session_id': session});
      final row = _firstRow(res);
      if (row == null) return null;
      final attempts = (row['attempts'] as num?)?.toInt() ?? 0;
      return LoginLockStatus(
        locked: row['locked'] == true,
        lockedUntil: _parseTime(row['locked_until']),
        remaining: (maxAttempts - attempts).clamp(0, maxAttempts),
      );
    } catch (e) {
      debugPrint('login_lock_status unavailable: $e');
      return null;
    }
  }

  static Future<LoginLockStatus?> _remoteRecordFailure(
    String session,
    String username,
  ) async {
    if (!AppEnv.supabaseConfigured) return null;
    try {
      final res = await Supabase.instance.client.rpc(
        'record_failed_login',
        params: {'p_session_id': session, 'p_username': username},
      );
      final row = _firstRow(res);
      if (row == null) return null;
      return LoginLockStatus(
        locked: row['locked'] == true,
        lockedUntil: _parseTime(row['locked_until']),
        remaining: (row['remaining'] as num?)?.toInt() ?? 0,
      );
    } catch (e) {
      debugPrint('record_failed_login unavailable: $e');
      return null;
    }
  }

  static Map<String, dynamic>? _firstRow(dynamic res) {
    if (res is List && res.isNotEmpty && res.first is Map) {
      return Map<String, dynamic>.from(res.first as Map);
    }
    if (res is Map) return Map<String, dynamic>.from(res);
    return null;
  }

  static DateTime? _parseTime(dynamic v) =>
      v is String ? DateTime.tryParse(v)?.toLocal() : null;

  // -- local ---------------------------------------------------------------

  static Map<String, dynamic> _readState(SharedPreferences prefs) {
    try {
      final raw = prefs.getString(_stateKey);
      if (raw == null) return {};
      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : {};
    } catch (_) {
      return {};
    }
  }

  static LoginLockStatus _localStatus(SharedPreferences prefs) {
    final state = _readState(prefs);
    final now = DateTime.now();
    final until = _parseTime(state['lockedUntil']);
    if (until != null && until.isAfter(now)) {
      return LoginLockStatus(locked: true, lockedUntil: until, remaining: 0);
    }
    final last = _parseTime(state['lastFailed']);
    if (last == null || now.difference(last) > _window) {
      return const LoginLockStatus(locked: false);
    }
    final count = (state['count'] as num?)?.toInt() ?? 0;
    return LoginLockStatus(
      locked: false,
      remaining: (maxAttempts - count).clamp(0, maxAttempts),
    );
  }

  static Future<LoginLockStatus> _localRecordFailure(
    SharedPreferences prefs,
  ) async {
    try {
      final state = _readState(prefs);
      final now = DateTime.now();
      final until = _parseTime(state['lockedUntil']);
      if (until != null && until.isAfter(now)) {
        return LoginLockStatus(locked: true, lockedUntil: until, remaining: 0);
      }

      var count = 1;
      final last = _parseTime(state['lastFailed']);
      final lockExpired = until != null && !until.isAfter(now);
      if (!lockExpired && last != null && now.difference(last) <= _window) {
        count = ((state['count'] as num?)?.toInt() ?? 0) + 1;
      }

      final locked = count >= maxAttempts;
      final lockedUntil = locked ? now.add(lockout) : null;
      await prefs.setString(
        _stateKey,
        jsonEncode({
          'count': count,
          'lastFailed': now.toUtc().toIso8601String(),
          if (lockedUntil != null)
            'lockedUntil': lockedUntil.toUtc().toIso8601String(),
        }),
      );
      return LoginLockStatus(
        locked: locked,
        lockedUntil: lockedUntil,
        remaining: (maxAttempts - count).clamp(0, maxAttempts),
      );
    } catch (_) {
      return const LoginLockStatus(locked: false);
    }
  }
}
