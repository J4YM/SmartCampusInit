import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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
            showDialog<void>(
              context: context,
              builder: (dialogContext) => Dialog(
                backgroundColor: Colors.transparent,
                insetPadding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                child: SizedBox(
                  width: 380,
                  child: BentoCard(
                    backgroundColor: Colors.white,
                    borderColor: const Color(0x0D000000),
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline_rounded,
                            color: Colors.red, size: 40),
                        const SizedBox(height: 12),
                        Text(
                          'Sign-in error',
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          oAuthError,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(fontSize: 13),
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          child: Material(
                            color: const Color(0xFF345892),
                            borderRadius: BorderRadius.circular(10),
                            child: InkWell(
                              onTap: () => Navigator.of(dialogContext).pop(),
                              borderRadius: BorderRadius.circular(10),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 12),
                                child: Text(
                                  'OK',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
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
