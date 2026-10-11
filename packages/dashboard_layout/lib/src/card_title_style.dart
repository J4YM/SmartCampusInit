import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'responsive_x.dart';

/// Font size of a card's title on a phone / on a desktop-width window.
const double kCardTitleFontSizeMobile = 16;
const double kCardTitleFontSizeDesktop = 18;

/// The ONE style for a card's title — "At-Risk Students", "Student List",
/// "Room Assignment", "My Documents" — on every dashboard and portal: 16px on
/// a phone, 18px on a desktop-width window, semi-bold.
///
/// A card's muted line under the title is the table kit's own sub style, and
/// a title nested inside another card (a sub-card, an accordion) stays at its
/// own smaller size — this is for the card's top-level label only.
TextStyle dashboardCardTitleStyle(BuildContext context, {Color? color}) =>
    GoogleFonts.poppins(
      fontSize: context.isMobileWidth
          ? kCardTitleFontSizeMobile
          : kCardTitleFontSizeDesktop,
      fontWeight: FontWeight.w600,
      color: color,
    );
