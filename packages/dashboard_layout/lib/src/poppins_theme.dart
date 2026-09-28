import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Makes Poppins the default font of a [ThemeData], so any text that doesn't
/// set its own font (button labels, dialog titles, text-field input, hints,
/// snackbars, tooltips, menu items...) still renders in Poppins instead of
/// Flutter's default Roboto.
///
/// Every dashboard builds its own `ThemeData(...)` for its local dark/light
/// toggle, and a fresh `ThemeData` resets the font — call this on each one.
/// Applied after construction (not as a `textTheme:` argument) so the text
/// colors still come from the theme's own brightness.
extension PoppinsThemeX on ThemeData {
  ThemeData withPoppins() => copyWith(
        textTheme: GoogleFonts.poppinsTextTheme(textTheme),
        primaryTextTheme: GoogleFonts.poppinsTextTheme(primaryTextTheme),
      );
}
