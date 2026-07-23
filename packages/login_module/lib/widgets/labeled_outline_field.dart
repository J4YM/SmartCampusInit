import 'package:flutter/material.dart';
import 'package:login_module/theme/app_colors.dart';
import 'package:login_module/theme/app_typography.dart';

/// Text field with a Figma-style label embedded at the top-left border.
class LabeledOutlineField extends StatelessWidget {
  const LabeledOutlineField({
    super.key,
    required this.label,
    required this.hint,
    this.obscureText = false,
    this.controller,
    this.keyboardType,
    this.textInputAction,
    this.suffixIcon,
    this.onChanged,
    this.expandWidth = false,
    this.scale = 1,
  });

  final String label;
  final String hint;
  final bool obscureText;
  final TextEditingController? controller;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Widget? suffixIcon;
  final ValueChanged<String>? onChanged;
  final bool expandWidth;
  final double scale;

  static const double _baseLabelOffsetTop = 12;

  @override
  Widget build(BuildContext context) {
    final labelOffsetTop = _baseLabelOffsetTop * scale;
    final fieldHeight = AppDimensions.fieldHeight * scale;
    final fieldRadius = BorderRadius.circular(AppDimensions.fieldRadius * scale);

    final labelStyle = AppTypography.poppins(
      fontSize: 12 * scale,
      fontWeight: FontWeight.w400,
      color: AppColors.fieldText,
      height: 16 / 12,
      letterSpacing: 0.4,
    );

    final fieldDecoration = InputDecoration(
      hintText: hint,
      hintStyle: AppTypography.poppins(
        fontSize: 16 * scale,
        fontWeight: FontWeight.w400,
        color: AppColors.fieldText,
        height: 24 / 16,
        letterSpacing: 0.5,
      ),
      suffixIcon: suffixIcon,
      suffixIconConstraints: BoxConstraints(
        minWidth: 44 * scale,
        minHeight: 44 * scale,
      ),
      contentPadding: EdgeInsets.symmetric(
        horizontal: 16 * scale,
        vertical: 18 * scale,
      ),
      isDense: true,
      filled: true,
      fillColor: AppColors.cardBackground,
      enabledBorder: OutlineInputBorder(
        borderRadius: fieldRadius,
        borderSide: const BorderSide(color: AppColors.fieldBorder, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: fieldRadius,
        borderSide: const BorderSide(color: AppColors.fieldBorder, width: 1),
      ),
      border: OutlineInputBorder(
        borderRadius: fieldRadius,
        borderSide: const BorderSide(color: AppColors.fieldBorder, width: 1),
      ),
    );

    return SizedBox(
      width: expandWidth ? double.infinity : AppDimensions.fieldWidth * scale,
      child: Padding(
        padding: EdgeInsets.only(top: labelOffsetTop),
        child: SizedBox(
          height: fieldHeight,
          width: expandWidth ? double.infinity : AppDimensions.fieldWidth * scale,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              TextFormField(
                controller: controller,
                obscureText: obscureText,
                keyboardType: keyboardType,
                textInputAction: textInputAction,
                onChanged: onChanged,
                style: AppTypography.poppins(
                  fontSize: 16 * scale,
                  fontWeight: FontWeight.w400,
                  color: AppColors.fieldText,
                  height: 24 / 16,
                  letterSpacing: 0.5,
                ),
                decoration: fieldDecoration,
              ),
              Positioned(
                left: 12 * scale,
                top: -labelOffsetTop,
                child: ColoredBox(
                  color: AppColors.white,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4 * scale),
                    child: Text(label, style: labelStyle),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Reserved slot for a generic credentials error between password and options row.
class CredentialsErrorSlot extends StatelessWidget {
  const CredentialsErrorSlot({
    super.key,
    this.message,
    this.expandWidth = false,
    this.scale = 1,
  });

  final String? message;
  final bool expandWidth;
  final double scale;

  static const double _baseSlotHeight = 24;

  static const String defaultMessage =
      'The credentials you entered are incorrect.';

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: expandWidth ? double.infinity : AppDimensions.fieldWidth * scale,
      height: _baseSlotHeight * scale,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          message ?? '',
          style: AppTypography.poppins(
            fontSize: 11 * scale,
            fontWeight: FontWeight.w400,
            color: AppColors.credentialsError,
            height: 1.2,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
