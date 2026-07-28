import 'package:flutter/material.dart';
import 'package:login_module/theme/app_colors.dart';
import 'package:login_module/theme/app_typography.dart';

/// Text field with a label above a soft-grey, borderless input box.
class LabeledOutlineField extends StatelessWidget {
  const LabeledOutlineField({
    super.key,
    required this.label,
    required this.hint,
    this.obscureText = false,
    this.controller,
    this.focusNode,
    this.keyboardType,
    this.textInputAction,
    this.suffixIcon,
    this.onChanged,
    this.onFieldSubmitted,
    this.expandWidth = true,
    this.scale = 1,
  });

  final String label;
  final String hint;
  final bool obscureText;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Widget? suffixIcon;
  final ValueChanged<String>? onChanged;

  /// Fires on the software keyboard's "next"/"done" action or a physical
  /// Enter/Return keypress.
  final ValueChanged<String>? onFieldSubmitted;
  final bool expandWidth;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final fieldRadius = BorderRadius.circular(AppDimensions.fieldRadius);
    final noBorder = OutlineInputBorder(
      borderRadius: fieldRadius,
      borderSide: BorderSide.none,
    );

    return SizedBox(
      width: expandWidth ? double.infinity : 320 * scale,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: AppTypography.poppins(
              fontSize: 12 * scale,
              fontWeight: FontWeight.w600,
              color: AppColors.inputLabel,
            ),
          ),
          SizedBox(height: 6 * scale),
          SizedBox(
            height: AppDimensions.fieldHeight * scale,
            child: TextFormField(
              controller: controller,
              focusNode: focusNode,
              obscureText: obscureText,
              keyboardType: keyboardType,
              textInputAction: textInputAction,
              onChanged: onChanged,
              onFieldSubmitted: onFieldSubmitted,
              style: AppTypography.poppins(
                fontSize: 14 * scale,
                fontWeight: FontWeight.w400,
                color: AppColors.inputText,
              ),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: AppTypography.poppins(
                  fontSize: 14 * scale,
                  fontWeight: FontWeight.w400,
                  color: AppColors.inputHint,
                ),
                suffixIcon: suffixIcon,
                suffixIconConstraints: BoxConstraints(
                  minWidth: 40 * scale,
                  minHeight: 40 * scale,
                ),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 16 * scale,
                  vertical: 12 * scale,
                ),
                isDense: true,
                filled: true,
                fillColor: AppColors.inputFill,
                border: noBorder,
                enabledBorder: noBorder,
                focusedBorder: noBorder,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Reserved slot for a generic credentials error between password and options row.
class CredentialsErrorSlot extends StatelessWidget {
  const CredentialsErrorSlot({
    super.key,
    this.message,
    this.expandWidth = true,
    this.scale = 1,
  });

  final String? message;
  final bool expandWidth;
  final double scale;

  static const double _baseSlotHeight = 20;

  static const String defaultMessage =
      'The credentials you entered are incorrect.';

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: expandWidth ? double.infinity : 320 * scale,
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
