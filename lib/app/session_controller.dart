import 'package:flutter/foundation.dart';

import '../auth/app_user.dart';

/// Host-side session until Supabase JWT + secure storage are wired in.
class SessionController extends ChangeNotifier {
  AppUser? _user;
  AppUser? get user => _user;

  bool get isAuthenticated => _user != null;

  int _failedAttempts = 0;
  int get failedAttempts => _failedAttempts;
  DateTime? _lockedUntil;

  bool get isLockedOut =>
      _lockedUntil != null && DateTime.now().isBefore(_lockedUntil!);

  Duration? get lockoutRemaining {
    final until = _lockedUntil;
    if (until == null || !DateTime.now().isBefore(until)) return null;
    return until.difference(DateTime.now());
  }

  /// Clears an expired lockout window so the UI can enable sign-in again.
  void refreshLockoutState() {
    final until = _lockedUntil;
    if (until != null && !DateTime.now().isBefore(until)) {
      _lockedUntil = null;
      notifyListeners();
    }
  }

  void signIn(AppUser user) {
    _user = user;
    _failedAttempts = 0;
    _lockedUntil = null;
    notifyListeners();
  }

  /// Returns `true` if lockout was triggered.
  bool registerFailedAttempt({required int maxAttempts, required Duration lockout}) {
    _failedAttempts += 1;
    if (_failedAttempts >= maxAttempts) {
      _lockedUntil = DateTime.now().add(lockout);
      _failedAttempts = 0;
      notifyListeners();
      return true;
    }
    notifyListeners();
    return false;
  }

  void clearFailedAttempts() {
    _failedAttempts = 0;
    notifyListeners();
  }

  void signOut() {
    _user = null;
    notifyListeners();
  }
}
