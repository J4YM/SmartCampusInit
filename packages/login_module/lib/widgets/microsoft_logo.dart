import 'package:flutter/material.dart';
import 'package:login_module/theme/app_colors.dart';

/// Multicolored Microsoft logo matching Figma vector colors.
class MicrosoftLogo extends StatelessWidget {
  const MicrosoftLogo({super.key, this.size = 16});

  final double size;

  @override
  Widget build(BuildContext context) {
    final squareWidth = (size - 1) / 2;
    final squareHeight = (size - 1) / 2;

    return SizedBox(
      width: size,
      height: size,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _LogoSquare(
                width: squareWidth,
                height: squareHeight,
                color: AppColors.msRed,
              ),
              const SizedBox(width: 1),
              _LogoSquare(
                width: squareWidth,
                height: squareHeight,
                color: AppColors.msGreen,
              ),
            ],
          ),
          const SizedBox(height: 1),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _LogoSquare(
                width: squareWidth,
                height: squareHeight,
                color: AppColors.msBlue,
              ),
              const SizedBox(width: 1),
              _LogoSquare(
                width: squareWidth,
                height: squareHeight,
                color: AppColors.msYellow,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LogoSquare extends StatelessWidget {
  const _LogoSquare({
    required this.width,
    required this.height,
    required this.color,
  });

  final double width;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(width: width, height: height, color: color);
  }
}
