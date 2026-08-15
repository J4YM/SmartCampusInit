import 'package:flutter/material.dart';
import 'package:login_module/theme/app_colors.dart';
import 'package:login_module/widgets/labeled_outline_field.dart';
import 'package:login_module/widgets/login_card.dart';

/// STI College Baliuag login screen.
///
/// Owns form state and text controllers. Auth is delegated to [onSignIn].
///
/// A single two-panel [LoginCard] (gradient branding + white credentials
/// form) floats centered over the full-screen campus background:
/// - **Desktop** (width >= 800): panels sit side-by-side in the card.
/// - **Mobile** (width < 800): panels stack, banner on top of the form.
class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.onSignIn,
    this.onMicrosoftSignIn,
    this.onForgotPassword,
    this.isSignInDisabled = false,
  });

  /// Returns `null` on success, or an error message for the credentials slot.
  final Future<String?> Function(String username, String password) onSignIn;

  final Future<void> Function()? onMicrosoftSignIn;

  /// Invoked when the user taps "Forgot Password". If omitted, the link is
  /// still rendered but does nothing.
  final VoidCallback? onForgotPassword;

  /// When true, the primary login button is disabled (e.g. lockout).
  final bool isSignInDisabled;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _rememberMe = false;
  String? _credentialsError;

  static const String _credentialsErrorMessage =
      CredentialsErrorSlot.defaultMessage;

  @override
  void initState() {
    super.initState();
    _emailController.addListener(_clearCredentialsError);
    _passwordController.addListener(_clearCredentialsError);
  }

  void _clearCredentialsError() {
    if (_credentialsError != null) {
      setState(() => _credentialsError = null);
    }
  }

  void _showCredentialsError() {
    setState(() => _credentialsError = _credentialsErrorMessage);
  }

  @override
  void dispose() {
    _emailController.removeListener(_clearCredentialsError);
    _passwordController.removeListener(_clearCredentialsError);
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleEmailLogin() async {
    if (widget.isSignInDisabled) return;

    final username = _emailController.text.trim();
    final password = _passwordController.text;

    if (username.isEmpty || password.isEmpty) {
      _showCredentialsError();
      return;
    }

    setState(() => _credentialsError = null);

    final error = await widget.onSignIn(username, password);
    if (!mounted) return;

    if (error != null) {
      setState(() => _credentialsError = error);
    }
  }

  Future<void> _handleMicrosoftLogin() async {
    await widget.onMicrosoftSignIn?.call();
  }

  LoginCard _buildLoginCard(LoginCardLayout layout) {
    return LoginCard(
      layout: layout,
      formKey: _formKey,
      emailController: _emailController,
      passwordController: _passwordController,
      rememberMe: _rememberMe,
      onRememberMeChanged: (value) {
        setState(() => _rememberMe = value ?? false);
      },
      onLoginPressed: _handleEmailLogin,
      onMicrosoftPressed: _handleMicrosoftLogin,
      onForgotPassword: widget.onForgotPassword,
      credentialsError: _credentialsError,
      loginEnabled: !widget.isSignInDisabled,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.overlayBlue,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const _CampusBackground(),
          const _BlueOverlay(),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isDesktop =
                    constraints.maxWidth >= AppDimensions.responsiveBreakpoint;

                final card = _buildLoginCard(
                  isDesktop ? LoginCardLayout.desktop : LoginCardLayout.mobile,
                );

                if (isDesktop) {
                  return Center(child: card);
                }

                // Mobile (Figma node 306:1831) is a full-bleed page, not a
                // floating card — no outer margin, top-anchored rather than
                // centered. The minHeight makes the card's white background
                // (banner excluded) reach the bottom of the screen even
                // when its content is shorter than the viewport, instead of
                // leaving the dimmed campus photo exposed below it — the
                // Column still only sizes its children naturally, so this
                // never forces anything to stretch or overflow. Still
                // wrapped in a scroll view so short viewports (landscape
                // phones, an open keyboard, large system text scale) never
                // overflow the other way either.
                return SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: card,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Campus photograph filling the screen behind the login card.
class _CampusBackground extends StatelessWidget {
  const _CampusBackground();

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      AppColors.campusBackgroundAsset,
      package: 'login_module',
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (context, error, stackTrace) {
        return const ColoredBox(color: AppColors.overlayBlue);
      },
    );
  }
}

/// Semi-transparent dark-blue overlay for readability over the campus photo.
class _BlueOverlay extends StatelessWidget {
  const _BlueOverlay();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.overlayBlue.withOpacity(0.55),
    );
  }
}
