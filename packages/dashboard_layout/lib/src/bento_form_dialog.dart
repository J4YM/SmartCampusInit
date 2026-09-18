import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'bento_card.dart';

/// Small `BentoCard`-shelled form/confirm dialog — title, arbitrary
/// [content], Cancel + a single confirm action. The shared shape for every
/// "Rename X" / "Delete X" / "Unsaved changes" style dialog across this app
/// (previously each hand-rolled its own bare `AlertDialog`), so they all get
/// the same rounded/shadowed `BentoCard` shell and Poppins typography as
/// every other dialog/popover instead of Flutter's default dialog chrome.
///
/// Takes explicit colors (not a shared color-token class) since each module
/// still owns its own per-page dark-mode palette — pass that module's own
/// card/border/text/field-fill tokens through, same convention as
/// `BentoCard` itself.
class BentoFormDialog extends StatelessWidget {
  const BentoFormDialog({
    super.key,
    required this.title,
    required this.content,
    required this.cancelLabel,
    required this.onCancel,
    required this.confirmLabel,
    required this.onConfirm,
    required this.backgroundColor,
    required this.borderColor,
    required this.titleColor,
    required this.cancelFillColor,
    this.confirmColor = const Color(0xFF345892),
    this.width = 380,
    this.isDarkMode,
  });

  final String title;
  final Widget content;
  final String cancelLabel;
  final VoidCallback onCancel;
  final String confirmLabel;
  final VoidCallback onConfirm;

  final Color backgroundColor;
  final Color borderColor;
  final Color titleColor;

  /// Fill for the Cancel pill — typically a module's pale "field fill"
  /// token; its own label reuses [titleColor].
  final Color cancelFillColor;

  /// Fill for the confirm pill — defaults to the app's shared brand blue;
  /// pass a danger color (e.g. for "Delete") to override.
  final Color confirmColor;

  final double width;

  /// See `BentoCard.isDarkMode` — pass explicitly since this renders
  /// through `showDialog`'s root-navigator Overlay, outside any per-page
  /// Theme.
  final bool? isDarkMode;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: SizedBox(
        width: width,
        child: BentoCard(
          backgroundColor: backgroundColor,
          borderColor: borderColor,
          isDarkMode: isDarkMode,
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: titleColor,
                ),
              ),
              const SizedBox(height: 14),
              content,
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Material(
                    color: cancelFillColor,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      onTap: onCancel,
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        child: Text(
                          cancelLabel,
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: titleColor,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Material(
                    color: confirmColor,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      onTap: onConfirm,
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        child: Text(
                          confirmLabel,
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
