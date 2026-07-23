import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

abstract final class AppTypography {
  static TextTheme textTheme() {
    final base = GoogleFonts.poppinsTextTheme();
    return base.apply(
      bodyColor: AppColors.sidebarText,
      displayColor: AppColors.sidebarText,
    );
  }
}
