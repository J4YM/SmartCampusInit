import 'package:flutter/material.dart';
import 'package:login_module/screens/login_screen.dart';
import 'package:login_module/widgets/labeled_outline_field.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app/session_controller.dart';
import '../auth/static_demo_accounts.dart';
import '../env.dart';

/// Username/password gate wired to [SessionController] and the new login UI.
class LoginPage extends StatelessWidget {
  const LoginPage({super.key, required this.session});

  final SessionController session;

  Future<String?> _handleSignIn(String username, String password) async {
    session.refreshLockoutState();
    if (session.isLockedOut) {
      final remaining = session.lockoutRemaining ?? Duration.zero;
      return 'Too many attempts. Try again in ${remaining.inSeconds.clamp(1, 999)}s.';
    }

    final user = StaticDemoAccounts.trySignIn(username, password);
    if (user != null) {
      session.signIn(user);
      return null;
    }

    final locked = session.registerFailedAttempt(
      maxAttempts: StaticDemoAccounts.maxAttemptsBeforeLockout,
      lockout: StaticDemoAccounts.lockoutDuration,
    );
    if (locked) {
      return 'Three failed attempts. This demo locks briefly; production will log to Supabase audit.';
    }

    final remaining =
        StaticDemoAccounts.maxAttemptsBeforeLockout - session.failedAttempts;
    if (remaining > 0) {
      return 'Invalid credentials. Attempts remaining before lockout: $remaining.';
    }
    return CredentialsErrorSlot.defaultMessage;
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
      await Supabase.instance.client.auth.signInWithOAuth(
        OAuthProvider.azure,
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
            showDialog<void>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                icon: const Icon(Icons.error_outline_rounded, color: Colors.red),
                title: const Text('Sign-in error'),
                content: Text(oAuthError),
                actions: [
                  FilledButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('OK'),
                  ),
                ],
              ),
            );
          });
        }

        return LoginScreen(
          isSignInDisabled: session.isLockedOut,
          onSignIn: _handleSignIn,
          onMicrosoftSignIn: () => _handleMicrosoftSignIn(context),
        );
      },
    );
  }
}
