import 'package:flutter/material.dart';
import 'package:login_module/theme/app_colors.dart';
import 'package:login_module/theme/app_typography.dart';

/// Branding block for the login card's left panel: "STI COLLEGE" split-color
/// title, "Baliuag" subtitle, and italic tagline.
class BrandingSection extends StatelessWidget {
  const BrandingSection({
    super.key,
    this.centered = false,
    this.scale = 1,
    this.showTagline = true,
  });

  /// When true, centers the text block (used in the stacked mobile layout).
  final bool centered;

  /// Uniform size multiplier for smaller viewports.
  final double scale;

  /// The mobile banner (Figma node 306:1831) omits the italic tagline to
  /// keep the fixed-height banner short — desktop keeps it.
  final bool showTagline;

  @override
  Widget build(BuildContext context) {
    final crossAxisAlignment =
        centered ? CrossAxisAlignment.center : CrossAxisAlignment.start;
    final textAlign = centered ? TextAlign.center : TextAlign.start;

    return Column(
      crossAxisAlignment: crossAxisAlignment,
      mainAxisSize: MainAxisSize.min,
      children: [
        RichText(
          textAlign: textAlign,
          text: TextSpan(
            style: AppTypography.poppins(
              fontSize: 45 * scale,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
            children: const [
              TextSpan(
                text: 'STI ',
                style: TextStyle(color: AppColors.brandYellow),
              ),
              TextSpan(
                text: 'COLLEGE',
                style: TextStyle(color: AppColors.white),
              ),
            ],
          ),
        ),
        SizedBox(height: 6 * scale),
        Text(
          'Baliuag',
          textAlign: textAlign,
          style: AppTypography.poppins(
            fontSize: 27 * scale,
            fontWeight: FontWeight.w500,
            color: AppColors.white,
            height: 1.2,
          ),
        ),
        SizedBox(height: 28 * scale),
        Text(
          'Be Future-Ready, Be STI',
          textAlign: textAlign,
          style: AppTypography.poppins(
            fontSize: 22 * scale,
            fontWeight: FontWeight.w400,
            fontStyle: FontStyle.italic,
            color: AppColors.white,
            height: 1.3,
          ),
        ),
      ],
    );
  }
}
