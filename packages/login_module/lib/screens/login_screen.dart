import 'package:flutter/material.dart';
import 'package:login_module/theme/app_colors.dart';
import 'package:login_module/widgets/branding_section.dart';
import 'package:login_module/widgets/labeled_outline_field.dart';
import 'package:login_module/widgets/login_card.dart';

/// STI College Baliuag login screen.
///
/// Owns form state and text controllers. Auth is delegated to [onSignIn].
///
/// Responsive layouts:
/// - **Desktop** (width >= 800): full-screen background stack, branding left,
///   floating login card right.
/// - **Mobile** (width < 800): scrollable column with hero banner + full-width
///   form sheet.
class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.onSignIn,
    this.onMicrosoftSignIn,
    this.isSignInDisabled = false,
  });

  /// Returns `null` on success, or an error message for the credentials slot.
  final Future<String?> Function(String username, String password) onSignIn;

  final Future<void> Function()? onMicrosoftSignIn;

  /// When true, the primary login button is disabled (e.g. lockout).
  final bool isSignInDisabled;

  /// Local campus background asset (package-relative).
  static const String backgroundAssetPath =
      'assets/images/campus_background.png';

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
      credentialsError: _credentialsError,
      loginEnabled: !widget.isSignInDisabled,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.overlayBlue,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isDesktop =
              constraints.maxWidth >= AppDimensions.responsiveBreakpoint;

          if (isDesktop) {
            return _DesktopLayout(
              loginCard: _buildLoginCard(LoginCardLayout.desktop),
            );
          }

          return _MobileLayout(
            loginCard: _buildLoginCard(LoginCardLayout.mobile),
          );
        },
      ),
    );
  }
}

/// Desktop split view: full-screen background with branding left, card right.
class _DesktopLayout extends StatelessWidget {
  const _DesktopLayout({required this.loginCard});

  final LoginCard loginCard;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const _CampusBackground(fit: BoxFit.cover),
        const _BlueOverlay(),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimensions.desktopHorizontalPadding,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: const BrandingSection(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: loginCard,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Mobile stacked view: banner + full-width form sheet filling the viewport.
class _MobileLayout extends StatelessWidget {
  const _MobileLayout({required this.loginCard});

  final LoginCard loginCard;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bannerHeight = AppDimensions.mobileBannerHeight;
        final formMinHeight = constraints.maxHeight - bannerHeight;

        return SizedBox(
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: bannerHeight,
                child: const _MobileBrandingBanner(),
              ),
              Expanded(
                child: SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: formMinHeight),
                    child: loginCard,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Hero banner with campus photo, overlay, and centered branding.
class _MobileBrandingBanner extends StatelessWidget {
  const _MobileBrandingBanner();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AppDimensions.mobileBannerHeight,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const _CampusBackground(fit: BoxFit.cover),
          const _BlueOverlay(),
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: AppDimensions.mobileBannerPaddingH,
              ),
              child: BrandingSection(
                banner: true,
                centered: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Campus photograph used in desktop background and mobile banner.
class _CampusBackground extends StatelessWidget {
  const _CampusBackground({required this.fit});

  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      LoginScreen.backgroundAssetPath,
      package: 'login_module',
      fit: fit,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (context, error, stackTrace) {
        return const ColoredBox(color: AppColors.overlayBlue);
      },
    );
  }
}

/// Semi-transparent #15253F overlay for text readability.
class _BlueOverlay extends StatelessWidget {
  const _BlueOverlay();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.overlayBlue.withValues(alpha: 0.55),
    );
  }
}
