import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Global Poppins typography helpers for the login module.
abstract final class AppTypography {
  static TextStyle poppins({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? height,
    double? letterSpacing,
  }) {
    return GoogleFonts.poppins(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
    );
  }

  static TextTheme textTheme() => GoogleFonts.poppinsTextTheme();
}
