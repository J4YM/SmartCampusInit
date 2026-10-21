import 'dart:io' show Platform;

import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:login_module/screens/login_screen.dart';
import 'package:login_module/widgets/labeled_outline_field.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app/session_controller.dart';
import '../auth/demo_account_gate.dart';
import '../auth/login_attempt_guard.dart';
import '../auth/account_lookup.dart';
import '../auth/staff_password_auth.dart';
import '../auth/static_demo_accounts.dart';
import '../data/parent_credential_repository.dart';
import '../env.dart';

/// Where Supabase sends the Windows desktop app back after Microsoft sign-in.
/// Must match the scheme registered in windows/installer/dashboard_installer.iss
/// and handled in windows/runner/main.cpp, and be listed under Supabase →
/// Authentication → URL Configuration → Redirect URLs.
const _windowsRedirectUrl = 'stibaliuag-dashboard://login-callback/';

/// Same idea for the Android APK. Must match the intent-filter in
/// android/app/src/main/AndroidManifest.xml and be listed under Supabase →
/// Authentication → URL Configuration → Redirect URLs.
const _androidRedirectUrl = 'ph.edu.stibaliuag.smartcampus://login-callback/';

String? get _nativeRedirectUrl {
  if (kIsWeb) return null;
  if (Platform.isWindows) return _windowsRedirectUrl;
  if (Platform.isAndroid) return _androidRedirectUrl;
  return null;
}

/// Username/password gate wired to [SessionController] and the new login UI.
class LoginPage extends StatelessWidget {
  const LoginPage({super.key, required this.session});

  final SessionController session;

  Future<String?> _handleSignIn(String username, String password) async {
    // Checked before the password so a locked session rejects even the
    // correct password until the lock expires (the lock is per session, not
    // per account).
    final status = await LoginAttemptGuard.check();
    if (status.locked) return _lockedMessage(status);

    final user = StaticDemoAccounts.trySignIn(username, password);
    if (user != null) {
      // A correct password isn't enough: an Admin may have switched this
      // account off in Staff Accounts. Not counted as a failed attempt.
      if (await isDemoAccountDeactivated(user)) {
        return kDeactivatedAccountMessage;
      }
      session.signIn(user);
      return null;
    }

    // Not a built-in demo account. An email address is either a real account
    // in Supabase Auth (staff created by an Admin, see
    // supabase/create_real_accounts.template.sql) or a guardian.
    if (AppEnv.supabaseConfigured && username.contains('@')) {
      final staff = await signInStaffWithPassword(
        Supabase.instance.client,
        username,
        password,
      );
      if (staff == StaffSignInResult.signedIn) {
        // The session controller resolves the profile's role, approval and
        // deactivation state from the new Supabase session.
        return null;
      }
    }

    // A guardian signing in with the email the registrar enrolled them under
    // plus the temporary password issued at enrollment
    // (supabase/add_parent_credentials.sql).
    if (AppEnv.supabaseConfigured && username.contains('@')) {
      try {
        final result = await ParentCredentialRepository(
          Supabase.instance.client,
        ).login(username, password);
        if (result.deactivated) return kDeactivatedAccountMessage;
        final login = result.login;
        if (login != null) {
          session.signInParent(login);
          return null;
        }
      } catch (_) {
        // Migration not installed / offline: counts as a normal failure.
      }
    }

    // Only a wrong password for an account that exists counts toward the
    // lockout. A name nobody owns shows the same error but is not counted.
    final exists = await loginAccountExists(
      AppEnv.supabaseConfigured ? Supabase.instance.client : null,
      username,
    );
    final after =
        await LoginAttemptGuard.recordFailure(username, accountExists: exists);
    if (after.locked) return _lockedMessage(after, justLocked: true);
    final n = after.remaining;
    return '${CredentialsErrorSlot.defaultMessage} '
        '$n attempt${n == 1 ? '' : 's'} remaining before this session is '
        'locked.';
  }

  static String _lockedMessage(LoginLockStatus s, {bool justLocked = false}) {
    final mins = s.minutesLeft;
    final alert = justLocked && AppEnv.supabaseConfigured
        ? ' A security alert email has been sent.'
        : '';
    return 'Too many failed sign-in attempts. Sign-in is locked for '
        '$mins more minute${mins == 1 ? '' : 's'}.$alert';
  }

  Future<void> _handleMicrosoftSignIn(BuildContext context) async {
    if (!AppEnv.supabaseConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Supabase is not configured; Microsoft sign-in is unavailable.',
          ),
        ),
      );
      return;
    }

    try {
      // Redirects the browser/webview to Microsoft via Supabase's Azure AD
      // OAuth provider (configured in the Supabase dashboard). On success,
      // the app reloads with a Supabase session and
      // `SessionController._onAuthStateChange` completes the sign-in.
      //
      // On the Windows desktop app the redirect must come back to the app
      // itself (custom URL scheme registered by the installer, forwarded to
      // the running window by windows/runner/main.cpp). Without it Supabase
      // falls back to its Site URL, so the browser tab — which never saw the
      // PKCE code verifier — tries to finish the sign-in and fails with
      // "Code verifier could not be found in local storage".
      await Supabase.instance.client.auth.signInWithOAuth(
        OAuthProvider.azure,
        redirectTo: _nativeRedirectUrl,
      );
    } on AuthException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Microsoft sign-in failed: ${e.message}')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Microsoft sign-in failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final oAuthError = session.oAuthError;
        if (oAuthError != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!context.mounted) return;
            session.clearOAuthError();
            showAppMessage(
              context,
              title: 'Sign-in error',
              message: oAuthError,
            );
          });
        }

        return LoginScreen(
          onSignIn: _handleSignIn,
          onMicrosoftSignIn: () => _handleMicrosoftSignIn(context),
        );
      },
    );
  }
}
