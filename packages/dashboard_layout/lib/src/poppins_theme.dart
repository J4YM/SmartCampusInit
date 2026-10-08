import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'nav_hover_underline.dart' show kSubNavActiveDarkColor;

/// The tick inside a dark-mode checkbox: dark navy, to read on the light-blue
/// ([kSubNavActiveDarkColor]) fill.
const Color kDarkCheckboxCheckColor = Color(0xFF15253F);

/// Makes Poppins the default font of a [ThemeData], so any text that doesn't
/// set its own font (button labels, dialog titles, text-field input, hints,
/// snackbars, tooltips, menu items...) still renders in Poppins instead of
/// Flutter's default Roboto.
///
/// Every dashboard builds its own `ThemeData(...)` for its local dark/light
/// toggle, and a fresh `ThemeData` resets the font — call this on each one.
/// Applied after construction (not as a `textTheme:` argument) so the text
/// colors still come from the theme's own brightness.
///
/// In a dark theme it also gives every [Checkbox] the dark-mode accent
/// (#A9C6FD, the same light blue as the active sub-nav tab) instead of the
/// brand blue, which is too dark to see on the dark surfaces.
extension PoppinsThemeX on ThemeData {
  ThemeData withPoppins() => copyWith(
        textTheme: GoogleFonts.poppinsTextTheme(textTheme),
        primaryTextTheme: GoogleFonts.poppinsTextTheme(primaryTextTheme),
        checkboxTheme: brightness == Brightness.dark
            ? checkboxTheme.copyWith(
                fillColor: WidgetStateProperty.resolveWith((states) =>
                    states.contains(WidgetState.selected) &&
                            !states.contains(WidgetState.disabled)
                        ? kSubNavActiveDarkColor
                        : null),
                checkColor:
                    const WidgetStatePropertyAll(kDarkCheckboxCheckColor),
              )
            : checkboxTheme,
      );
}
