import 'package:flutter/material.dart';
import 'package:login_module/theme/app_colors.dart';
import 'package:login_module/theme/app_typography.dart';
import 'package:login_module/widgets/labeled_outline_field.dart';
import 'package:login_module/widgets/microsoft_logo.dart';

/// Layout mode for the login card container.
enum LoginCardLayout {
  /// Floating 400px card on the right (desktop split view).
  desktop,

  /// Full-width white form sheet below the mobile banner.
  mobile,
}

/// Login card styled to Figma specifications; height wraps its contents.
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
  final String? credentialsError;
  final LoginCardLayout layout;
  final bool loginEnabled;

  bool get _isMobile => layout == LoginCardLayout.mobile;

  @override
  Widget build(BuildContext context) {
    final formContent = Form(
      key: formKey,
      child: _CardContent(
        emailController: emailController,
        passwordController: passwordController,
        rememberMe: rememberMe,
        onRememberMeChanged: onRememberMeChanged,
        onLoginPressed: onLoginPressed,
        onMicrosoftPressed: onMicrosoftPressed,
        credentialsError: credentialsError,
        isMobile: _isMobile,
        loginEnabled: loginEnabled,
      ),
    );

    if (_isMobile) {
      return ColoredBox(
        color: AppColors.cardBackground,
        child: SizedBox(
          width: double.infinity,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimensions.mobileFormPaddingH,
              vertical: AppDimensions.mobileFormPaddingV,
            ),
            child: formContent,
          ),
        ),
      );
    }

    return SizedBox(
      width: AppDimensions.cardWidth,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimensions.cardPaddingH,
            vertical: AppDimensions.cardPaddingV,
          ),
          child: formContent,
        ),
      ),
    );
  }
}

class _CardContent extends StatelessWidget {
  const _CardContent({
    required this.emailController,
    required this.passwordController,
    required this.rememberMe,
    required this.onRememberMeChanged,
    required this.onLoginPressed,
    required this.onMicrosoftPressed,
    required this.credentialsError,
    required this.isMobile,
    required this.loginEnabled,
  });

  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool rememberMe;
  final ValueChanged<bool?> onRememberMeChanged;
  final VoidCallback onLoginPressed;
  final VoidCallback onMicrosoftPressed;
  final String? credentialsError;
  final bool isMobile;
  final bool loginEnabled;

  @override
  Widget build(BuildContext context) {
    final scale = isMobile ? AppDimensions.mobileContentScale : 1.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _CardHeader(isMobile: isMobile, scale: scale),
        SizedBox(height: isMobile ? AppDimensions.mobileScale(16) : 10),
        _MiddleSection(
          emailController: emailController,
          passwordController: passwordController,
          rememberMe: rememberMe,
          onRememberMeChanged: onRememberMeChanged,
          credentialsError: credentialsError,
          isMobile: isMobile,
          scale: scale,
          loginEnabled: loginEnabled,
        ),
        SizedBox(height: isMobile ? AppDimensions.mobileScale(5) : 5),
        _LoginButton(
          onPressed: loginEnabled ? onLoginPressed : null,
          isMobile: isMobile,
          scale: scale,
        ),
        SizedBox(height: isMobile ? AppDimensions.mobileScale(10) : 10),
        _SignInWithDivider(isMobile: isMobile, scale: scale),
        SizedBox(height: isMobile ? AppDimensions.mobileScale(10) : 10),
        _MicrosoftButton(
          onPressed: onMicrosoftPressed,
          isMobile: isMobile,
          scale: scale,
        ),
      ],
    );
  }
}

class _CardHeader extends StatelessWidget {
  const _CardHeader({
    required this.isMobile,
    required this.scale,
  });

  final bool isMobile;
  final double scale;

  @override
  Widget build(BuildContext context) {
    if (isMobile) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: AppDimensions.mobileScale(8)),
        child: Text(
          'Sign in to your account',
          textAlign: TextAlign.center,
          style: AppTypography.poppins(
            fontSize: AppDimensions.cardTitleFontSize * scale,
            fontWeight: FontWeight.w700,
            color: AppColors.cardHeader,
            height: 16 / 24,
            letterSpacing: 0.4,
          ),
        ),
      );
    }

    return SizedBox(
      width: 380,
      height: 76,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Align(
          alignment: Alignment.center,
          child: Text(
            'Sign in to your account',
            style: AppTypography.poppins(
              fontSize: AppDimensions.cardTitleFontSize,
              fontWeight: FontWeight.w700,
              color: AppColors.cardHeader,
              height: 16 / 24,
              letterSpacing: 0.4,
            ),
          ),
        ),
      ),
    );
  }
}

class _MiddleSection extends StatefulWidget {
  const _MiddleSection({
    required this.emailController,
    required this.passwordController,
    required this.rememberMe,
    required this.onRememberMeChanged,
    required this.credentialsError,
    required this.isMobile,
    required this.scale,
    required this.loginEnabled,
  });

  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool rememberMe;
  final ValueChanged<bool?> onRememberMeChanged;
  final String? credentialsError;
  final bool isMobile;
  final double scale;
  final bool loginEnabled;

  @override
  State<_MiddleSection> createState() => _MiddleSectionState();
}

class _MiddleSectionState extends State<_MiddleSection> {
  bool _obscurePassword = true;

  @override
  Widget build(BuildContext context) {
    final expandWidth = widget.isMobile;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: widget.isMobile ? 0 : 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LabeledOutlineField(
            label: 'Email',
            hint: 'Enter email',
            controller: widget.emailController,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            expandWidth: expandWidth,
            scale: widget.scale,
          ),
          SizedBox(height: widget.isMobile ? AppDimensions.mobileScale(5) : 5),
          LabeledOutlineField(
            label: 'Password',
            hint: 'Enter password',
            controller: widget.passwordController,
            obscureText: _obscurePassword,
            textInputAction: TextInputAction.done,
            expandWidth: expandWidth,
            scale: widget.scale,
            suffixIcon: IconButton(
              onPressed: () {
                setState(() => _obscurePassword = !_obscurePassword);
              },
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                size: 20 * widget.scale,
                color: AppColors.fieldText,
              ),
              padding: EdgeInsets.zero,
              constraints: BoxConstraints(
                minWidth: 44 * widget.scale,
                minHeight: 44 * widget.scale,
              ),
              tooltip: _obscurePassword ? 'Show password' : 'Hide password',
            ),
          ),
          CredentialsErrorSlot(
            message: widget.credentialsError,
            expandWidth: expandWidth,
            scale: widget.scale,
          ),
          SizedBox(height: widget.isMobile ? AppDimensions.mobileScale(5) : 5),
          _OptionsRow(
            rememberMe: widget.rememberMe,
            onRememberMeChanged: widget.onRememberMeChanged,
            isMobile: widget.isMobile,
            scale: widget.scale,
          ),
        ],
      ),
    );
  }
}

/// Remember-me checkbox on the left, forget-password link on the right.
class _OptionsRow extends StatelessWidget {
  const _OptionsRow({
    required this.rememberMe,
    required this.onRememberMeChanged,
    required this.isMobile,
    required this.scale,
  });

  final bool rememberMe;
  final ValueChanged<bool?> onRememberMeChanged;
  final bool isMobile;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 0 : 20),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                SizedBox(
                  height: 24 * scale,
                  width: 24 * scale,
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
                  ),
                ),
                SizedBox(width: 10 * scale),
                Flexible(
                  child: Text(
                    'Remember me',
                    style: AppTypography.poppins(
                      fontSize: 12 * scale,
                      fontWeight: FontWeight.w400,
                      color: AppColors.rememberMe,
                      height: 24 / 12,
                      letterSpacing: 0.5,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () {},
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: AppColors.forgetPassword,
                ),
                child: Text(
                  'Forget password',
                  style: AppTypography.poppins(
                    fontSize: 12 * scale,
                    fontWeight: FontWeight.w400,
                    color: AppColors.forgetPassword,
                    height: 24 / 12,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginButton extends StatelessWidget {
  const _LoginButton({
    required this.onPressed,
    required this.isMobile,
    required this.scale,
  });

  final VoidCallback? onPressed;
  final bool isMobile;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 0 : 10,
        vertical: isMobile ? 0 : 10,
      ),
      child: SizedBox(
        width: isMobile ? double.infinity : AppDimensions.buttonWidth,
        height: AppDimensions.buttonHeight * scale,
        child: FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.loginButton,
            foregroundColor: AppColors.buttonText,
            padding: EdgeInsets.symmetric(
              horizontal: 24 * scale,
              vertical: 16 * scale,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(
                AppDimensions.buttonRadius * scale,
              ),
            ),
            elevation: 0,
          ),
          child: Text(
            'Login',
            style: AppTypography.poppins(
              fontSize: 16 * scale,
              fontWeight: FontWeight.w500,
              color: AppColors.buttonText,
              height: 24 / 16,
              letterSpacing: 0.15,
            ),
          ),
        ),
      ),
    );
  }
}

/// Divider with 0.5px black lines flanking "Sign in with".
class _SignInWithDivider extends StatelessWidget {
  const _SignInWithDivider({
    required this.isMobile,
    required this.scale,
  });

  final bool isMobile;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 0 : 25),
      child: Row(
        children: [
          const Expanded(child: _ThinDividerLine()),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 10 * scale),
            child: Text(
              'Sign in with',
              style: AppTypography.poppins(
                fontSize: 12 * scale,
                fontWeight: FontWeight.w400,
                color: AppColors.dividerLine,
                height: 20 / 12,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const Expanded(child: _ThinDividerLine()),
        ],
      ),
    );
  }
}

class _ThinDividerLine extends StatelessWidget {
  const _ThinDividerLine();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: AppDimensions.dividerThickness,
      color: AppColors.dividerLine,
    );
  }
}

class _MicrosoftButton extends StatelessWidget {
  const _MicrosoftButton({
    required this.onPressed,
    required this.isMobile,
    required this.scale,
  });

  final VoidCallback onPressed;
  final bool isMobile;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 0 : 10,
        vertical: isMobile ? 0 : 10,
      ),
      child: SizedBox(
        width: isMobile ? double.infinity : AppDimensions.buttonWidth,
        height: AppDimensions.buttonHeight * scale,
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            backgroundColor: AppColors.cardBackground,
            foregroundColor: AppColors.microsoftText,
            padding: EdgeInsets.symmetric(
              horizontal: 24 * scale,
              vertical: 16 * scale,
            ),
            side: const BorderSide(
              color: AppColors.microsoftBorder,
              width: AppDimensions.microsoftBorderWidth,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(
                AppDimensions.buttonRadius * scale,
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              MicrosoftLogo(size: 16 * scale),
              SizedBox(width: 10 * scale),
              Text(
                'Microsoft',
                style: AppTypography.poppins(
                  fontSize: 16 * scale,
                  fontWeight: FontWeight.w400,
                  color: AppColors.microsoftText,
                  height: 24 / 16,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
