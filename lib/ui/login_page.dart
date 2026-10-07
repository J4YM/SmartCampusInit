import 'package:dashboard_layout/dashboard_layout.dart';
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
    final user = StaticDemoAccounts.trySignIn(username, password);
    if (user != null) {
      session.signIn(user);
      return null;
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
