import 'package:flutter/material.dart';
import 'package:login_module/theme/app_colors.dart';
import 'package:login_module/theme/app_typography.dart';
import 'package:login_module/widgets/branding_section.dart';
import 'package:login_module/widgets/labeled_outline_field.dart';
import 'package:login_module/widgets/microsoft_logo.dart';

/// Layout mode for the login card container.
enum LoginCardLayout {
  /// Two-column split card: gradient branding panel left, white form panel
  /// right (desktop / wide viewports).
  desktop,

  /// Stacked card: gradient branding banner on top, white form panel below
  /// (narrow / mobile viewports).
  mobile,
}

/// Two-panel login card: a white outer frame wrapping a gradient branding
/// panel and a white credentials form panel.
///
/// Presentation-only widget — form state and auth handlers are owned by
/// [LoginScreen] and passed in via constructor parameters.
class LoginCard extends StatelessWidget {
  const LoginCard({
    super.key,
    required this.formKey,
    required this.emailController,
    required this.passwordController,
    required this.rememberMe,
    required this.onRememberMeChanged,
    required this.onLoginPressed,
    required this.onMicrosoftPressed,
    this.onForgotPassword,
    this.credentialsError,
    this.layout = LoginCardLayout.desktop,
    this.loginEnabled = true,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool rememberMe;
  final ValueChanged<bool?> onRememberMeChanged;
  final VoidCallback onLoginPressed;
  final VoidCallback onMicrosoftPressed;
  final VoidCallback? onForgotPassword;
  final String? credentialsError;
  final LoginCardLayout layout;
  final bool loginEnabled;

  bool get _isMobile => layout == LoginCardLayout.mobile;

  @override
  Widget build(BuildContext context) {
    final formPanel = _FormPanel(
      formKey: formKey,
      emailController: emailController,
      passwordController: passwordController,
      rememberMe: rememberMe,
      onRememberMeChanged: onRememberMeChanged,
      onLoginPressed: onLoginPressed,
      onMicrosoftPressed: onMicrosoftPressed,
      onForgotPassword: onForgotPassword,
      credentialsError: credentialsError,
      isMobile: _isMobile,
      loginEnabled: loginEnabled,
    );

    final brandingPanel = _BrandingPanel(isMobile: _isMobile);

    final cardBody = _isMobile
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: AppDimensions.mobileBannerHeight,
                width: double.infinity,
                child: brandingPanel,
              ),
              const SizedBox(height: AppDimensions.panelGap),
              formPanel,
            ],
          )
        : SizedBox(
            width: AppDimensions.cardContentWidth,
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: AppDimensions.brandingFlex,
                    child: brandingPanel,
                  ),
                  const SizedBox(width: AppDimensions.panelGap),
                  Expanded(
                    flex: AppDimensions.formFlex,
                    child: formPanel,
                  ),
                ],
              ),
            ),
          );

    return Container(
      width: _isMobile ? double.infinity : null,
      padding: const EdgeInsets.all(AppDimensions.cardFramePadding),
      decoration: BoxDecoration(
        color: AppColors.cardFrame,
        borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
        boxShadow: const [
          BoxShadow(
            color: AppColors.cardShadow,
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: cardBody,
    );
  }
}

/// Left/top gradient panel carrying the STI College branding.
class _BrandingPanel extends StatelessWidget {
  const _BrandingPanel({required this.isMobile});

  final bool isMobile;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppDimensions.panelRadius),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.brandGradientStart, AppColors.brandGradientEnd],
          ),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 24 : AppDimensions.brandingPanelPaddingH,
            vertical: isMobile ? 16 : AppDimensions.brandingPanelPaddingV,
          ),
          child: Align(
            alignment: isMobile ? Alignment.center : Alignment.centerLeft,
            child: BrandingSection(
              centered: isMobile,
              scale: isMobile ? 0.85 : 1,
            ),
          ),
        ),
      ),
    );
  }
}

/// Right/bottom white panel carrying the credentials form.
class _FormPanel extends StatelessWidget {
  const _FormPanel({
    required this.formKey,
    required this.emailController,
    required this.passwordController,
    required this.rememberMe,
    required this.onRememberMeChanged,
    required this.onLoginPressed,
    required this.onMicrosoftPressed,
    required this.onForgotPassword,
    required this.credentialsError,
    required this.isMobile,
    required this.loginEnabled,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool rememberMe;
  final ValueChanged<bool?> onRememberMeChanged;
  final VoidCallback onLoginPressed;
  final VoidCallback onMicrosoftPressed;
  final VoidCallback? onForgotPassword;
  final String? credentialsError;
  final bool isMobile;
  final bool loginEnabled;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppDimensions.panelRadius),
      child: ColoredBox(
        color: AppColors.formBackground,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: isMobile
                ? AppDimensions.mobileFormPaddingH
                : AppDimensions.formPanelPaddingH,
            vertical: isMobile
                ? AppDimensions.mobileFormPaddingV
                : AppDimensions.formPanelPaddingV,
          ),
          // Centered rather than top-anchored so the form reads balanced
          // against the taller branding panel next to it.
          child: Center(
            child: Form(
              key: formKey,
              child: _FormFields(
                emailController: emailController,
                passwordController: passwordController,
                rememberMe: rememberMe,
                onRememberMeChanged: onRememberMeChanged,
                onLoginPressed: onLoginPressed,
                onMicrosoftPressed: onMicrosoftPressed,
                onForgotPassword: onForgotPassword,
                credentialsError: credentialsError,
                loginEnabled: loginEnabled,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FormFields extends StatefulWidget {
  const _FormFields({
    required this.emailController,
    required this.passwordController,
    required this.rememberMe,
    required this.onRememberMeChanged,
    required this.onLoginPressed,
    required this.onMicrosoftPressed,
    required this.onForgotPassword,
    required this.credentialsError,
    required this.loginEnabled,
  });

  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool rememberMe;
  final ValueChanged<bool?> onRememberMeChanged;
  final VoidCallback onLoginPressed;
  final VoidCallback onMicrosoftPressed;
  final VoidCallback? onForgotPassword;
  final String? credentialsError;
  final bool loginEnabled;

  @override
  State<_FormFields> createState() => _FormFieldsState();
}

class _FormFieldsState extends State<_FormFields> {
  bool _obscurePassword = true;
  final _passwordFocusNode = FocusNode();

  @override
  void dispose() {
    _passwordFocusNode.dispose();
    super.dispose();
  }

  void _submitIfEnabled() {
    if (widget.loginEnabled) widget.onLoginPressed();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Sign to your account',
          textAlign: TextAlign.center,
          style: AppTypography.poppins(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: AppColors.titleText,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Use your school credentials',
          textAlign: TextAlign.center,
          style: AppTypography.poppins(
            fontSize: 12,
            fontWeight: FontWeight.w400,
            color: AppColors.subtitleText,
          ),
        ),
        const SizedBox(height: 16),
        LabeledOutlineField(
          label: 'Email',
          hint: 'e.g., username@gmail.com',
          controller: widget.emailController,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          onFieldSubmitted: (_) => _passwordFocusNode.requestFocus(),
        ),
        const SizedBox(height: 14),
        LabeledOutlineField(
          label: 'Password',
          hint: '••••••••',
          controller: widget.passwordController,
          focusNode: _passwordFocusNode,
          obscureText: _obscurePassword,
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _submitIfEnabled(),
          suffixIcon: IconButton(
            onPressed: () {
              setState(() => _obscurePassword = !_obscurePassword);
            },
            icon: Icon(
              _obscurePassword
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              size: 18,
              color: AppColors.inputHint,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            tooltip: _obscurePassword ? 'Show password' : 'Hide password',
          ),
        ),
        CredentialsErrorSlot(message: widget.credentialsError),
        _OptionsRow(
          rememberMe: widget.rememberMe,
          onRememberMeChanged: widget.onRememberMeChanged,
          onForgotPassword: widget.onForgotPassword,
        ),
        const SizedBox(height: 14),
        _LoginButton(
          onPressed: widget.loginEnabled ? widget.onLoginPressed : null,
        ),
        const SizedBox(height: 16),
        const _SignInWithDivider(),
        const SizedBox(height: 14),
        _MicrosoftButton(onPressed: widget.onMicrosoftPressed),
      ],
    );
  }
}

/// Remember-me checkbox on the left, forgot-password link on the right.
class _OptionsRow extends StatelessWidget {
  const _OptionsRow({
    required this.rememberMe,
    required this.onRememberMeChanged,
    required this.onForgotPassword,
  });

  final bool rememberMe;
  final ValueChanged<bool?> onRememberMeChanged;
  final VoidCallback? onForgotPassword;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 20,
              width: 20,
              child: Checkbox(
                value: rememberMe,
                onChanged: onRememberMeChanged,
                activeColor: AppColors.loginButton,
                checkColor: AppColors.buttonText,
                side: const BorderSide(
                  color: AppColors.checkboxIcon,
                  width: 1.5,
                ),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Remember Me',
              style: AppTypography.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: AppColors.rememberMeText,
              ),
            ),
          ],
        ),
        TextButton(
          onPressed: onForgotPassword ?? () {},
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            foregroundColor: AppColors.forgotPassword,
          ),
          child: Text(
            'Forgot Password',
            style: AppTypography.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: AppColors.forgotPassword,
            ),
          ),
        ),
      ],
    );
  }
}

class _LoginButton extends StatelessWidget {
  const _LoginButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: AppDimensions.buttonHeight,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.loginButton,
          foregroundColor: AppColors.buttonText,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimensions.buttonRadius),
          ),
          elevation: 0,
        ),
        child: Text(
          'Login',
          style: AppTypography.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.buttonText,
          ),
        ),
      ),
    );
  }
}

/// Divider with thin grey lines flanking "Sign in with".
class _SignInWithDivider extends StatelessWidget {
  const _SignInWithDivider();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider(color: AppColors.dividerLine, height: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            'Sign in with',
            style: AppTypography.poppins(
              fontSize: 11,
              fontWeight: FontWeight.w400,
              color: AppColors.dividerText,
            ),
          ),
        ),
        const Expanded(child: Divider(color: AppColors.dividerLine, height: 1)),
      ],
    );
  }
}

class _MicrosoftButton extends StatelessWidget {
  const _MicrosoftButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: AppDimensions.buttonHeight,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: AppColors.formBackground,
          foregroundColor: AppColors.microsoftText,
          side: const BorderSide(color: AppColors.microsoftBorder, width: 1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimensions.buttonRadius),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            const MicrosoftLogo(size: 16),
            const SizedBox(width: 10),
            Text(
              'Microsoft',
              style: AppTypography.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.microsoftText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
