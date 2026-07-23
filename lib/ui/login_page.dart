import 'package:flutter/material.dart';
import 'package:login_module/screens/login_screen.dart';
import 'package:login_module/widgets/labeled_outline_field.dart';

import '../../app/session_controller.dart';
import '../../auth/static_demo_accounts.dart';

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

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        return LoginScreen(
          isSignInDisabled: session.isLockedOut,
          onSignIn: _handleSignIn,
          onMicrosoftSignIn: () async {
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Microsoft sign-in will be wired to Supabase OAuth in production.',
                ),
              ),
            );
          },
        );
      },
    );
  }
}
