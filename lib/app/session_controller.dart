import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/app_role.dart';
import '../auth/app_user.dart';
import '../env.dart';

/// Host-side session until Supabase JWT + secure storage are wired in.
class SessionController extends ChangeNotifier {
  SessionController() {
    if (AppEnv.supabaseConfigured) {
      _authSubscription = Supabase.instance.client.auth.onAuthStateChange
          .listen(_onAuthStateChange, onError: _onAuthStateError);
    }
  }

  StreamSubscription<AuthState>? _authSubscription;

  AppUser? _user;
  AppUser? get user => _user;

  bool get isAuthenticated => _user != null;

  int _failedAttempts = 0;
  int get failedAttempts => _failedAttempts;
  DateTime? _lockedUntil;

  /// Set when an OAuth (e.g. Microsoft) sign-in completes but can't resolve
  /// to a usable account — surfaced once by [LoginPage], then cleared via
  /// [clearOAuthError].
  String? _oAuthError;
  String? get oAuthError => _oAuthError;

  void clearOAuthError() {
    if (_oAuthError == null) return;
    _oAuthError = null;
    notifyListeners();
  }

  /// True when a signed-in Supabase user's `profiles.status` is `pending`
  /// (a staff sign-in awaiting admin approval + role assignment). Distinct
  /// from [oAuthError], which means the profile row is missing/broken.
  bool _awaitingApproval = false;
  bool get isAwaitingApproval => _awaitingApproval;

  String? _pendingApprovalEmail;
  String? get pendingApprovalEmail => _pendingApprovalEmail;

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
    _awaitingApproval = false;
    _pendingApprovalEmail = null;
    notifyListeners();
  }

  /// Returns `true` if lockout was triggered.
  bool registerFailedAttempt(
      {required int maxAttempts, required Duration lockout}) {
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
    _awaitingApproval = false;
    _pendingApprovalEmail = null;
    notifyListeners();
    if (AppEnv.supabaseConfigured) {
      // An active OAuth session (e.g. Microsoft) must be cleared too, or
      // `_onAuthStateChange` would sign the user straight back in.
      Supabase.instance.client.auth.signOut();
    }
  }

  /// Re-fetches the current Supabase user's profile to check whether an
  /// admin has approved a pending staff account since the last check. Used
  /// by the "Refresh status" action on the awaiting-approval screen (there's
  /// no push notification when approval happens in a separate session).
  Future<void> recheckApprovalStatus() async {
    final supabaseUser = Supabase.instance.client.auth.currentUser;
    if (supabaseUser == null) return;
    await _resolveFromSupabaseUser(supabaseUser);
  }

  /// Resolves a completed Supabase OAuth sign-in (e.g. Microsoft via Azure
  /// AD) to an [AppUser] by looking up the matching `profiles` row for its
  /// role and display name. No-ops if a user is already signed in (e.g. via
  /// the static demo accounts) so it never clobbers an active session.
  Future<void> _onAuthStateChange(AuthState state) async {
    final supabaseUser = state.session?.user;
    if (supabaseUser == null || _user != null) return;
    await _resolveFromSupabaseUser(supabaseUser);
  }

  Future<void> _resolveFromSupabaseUser(User supabaseUser) async {
    try {
      final profile = await Supabase.instance.client
          .from('profiles')
          .select('first_name, last_name, role, status')
          .eq('id', supabaseUser.id)
          .maybeSingle();

      final status = approvalStatusFromDbValue(profile?['status'] as String?);
      if (status == ApprovalStatus.pending) {
        _awaitingApproval = true;
        _pendingApprovalEmail = supabaseUser.email;
        notifyListeners();
        return;
      }

      final role = appRoleFromDbValue(profile?['role'] as String?);
      if (role == null) {
        _awaitingApproval = false;
        _oAuthError = 'Your account is signed in with Microsoft but has no '
            'role assigned yet. Contact an administrator.';
        notifyListeners();
        return;
      }

      final firstName = (profile?['first_name'] as String?)?.trim() ?? '';
      final lastName = (profile?['last_name'] as String?)?.trim() ?? '';
      final displayName =
          [firstName, lastName].where((s) => s.isNotEmpty).join(' ');

      signIn(
        AppUser(
          id: supabaseUser.id,
          displayName: displayName.isEmpty
              ? (supabaseUser.email ?? 'Microsoft account')
              : displayName,
          role: role,
          username: supabaseUser.email ?? supabaseUser.id,
        ),
      );
    } catch (e) {
      _oAuthError = 'Could not complete Microsoft sign-in: $e';
      notifyListeners();
    }
  }

  /// Handles errors emitted on the `onAuthStateChange` stream itself — this
  /// is how a rejection from the `handle_new_auth_user` trigger (invalid
  /// domain/email pattern) actually reaches the app. `signInWithOAuth()`
  /// only kicks off the browser redirect to Microsoft and doesn't throw for
  /// this; the rejection happens later, when Supabase redirects back with an
  /// `error`/`error_description` in the URL. supabase_flutter's deep-link
  /// handler turns that into an [AuthException] and forwards it via
  /// `GoTrueClient.notifyException`, which surfaces here as a stream error
  /// (not a normal [AuthState] event) — so this handler must exist, or the
  /// rejection is silently dropped and the user sees nothing.
  void _onAuthStateError(Object error, StackTrace stackTrace) {
    if (_user != null) return;
    _awaitingApproval = false;
    _oAuthError = _describeOAuthStreamError(error);
    notifyListeners();
  }

  String _describeOAuthStreamError(Object error) {
    final raw = error is AuthException ? error.message : error.toString();
    final lower = raw.toLowerCase();

    // Supabase's GoTrue server sometimes replaces a trigger's custom
    // `raise exception` message with a generic one (e.g. "Database error
    // saving new user") rather than forwarding it verbatim, so a specific,
    // helpful fallback is shown whenever the raw message isn't already
    // self-explanatory.
    if (lower.contains('baliuag') || lower.contains('not an authorized')) {
      return raw;
    }
    if (lower.contains('database error saving new user') ||
        lower.contains('unexpected_failure') ||
        lower.contains('server_error')) {
      return 'Sign-in rejected: only @baliuag.sti.edu.ph accounts in an '
          'approved format (student number or firstname.lastname) can sign '
          'in with Microsoft.';
    }
    return 'Microsoft sign-in failed: $raw';
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}
