import 'package:flutter/material.dart';
import 'package:login_module/theme/app_colors.dart';
import 'package:login_module/theme/app_typography.dart';

/// Branding: "STI COLLEGE" with split colors, "Baliuag" subtitle below.
class BrandingSection extends StatelessWidget {
  const BrandingSection({
    super.key,
    this.compact = false,
    this.centered = false,
    this.banner = false,
  });

  /// When true, scales typography for smaller layouts.
  final bool compact;

  /// When true, centers the text block (mobile banner).
  final bool centered;

  /// When true, uses typography sized for the mobile hero banner.
  final bool banner;

  static const double _headingLineHeightRatio =
      AppDimensions.headingLineHeight / AppDimensions.headingFontSize;

  @override
  Widget build(BuildContext context) {
    final titleSize = banner
        ? AppDimensions.headingFontSize *
            0.5 *
            AppDimensions.mobileBannerScale
        : compact
            ? AppDimensions.headingFontSize * 0.42
            : AppDimensions.headingFontSize;
    final subtitleSize = titleSize * AppDimensions.subtitleScale;

    final titleBaseStyle = AppTypography.poppins(
      fontSize: titleSize,
      fontWeight: FontWeight.bold,
      height: _headingLineHeightRatio,
      letterSpacing: 0.5,
    );

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
            style: titleBaseStyle,
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
        SizedBox(height: banner ? 10 * AppDimensions.mobileBannerScale : 10),
        Text(
          'Baliuag',
          textAlign: textAlign,
          style: AppTypography.poppins(
            fontSize: subtitleSize,
            fontWeight: FontWeight.w400,
            color: AppColors.white,
            height: 1.2,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}
