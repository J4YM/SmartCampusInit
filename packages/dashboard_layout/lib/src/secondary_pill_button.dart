import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'brightness_x.dart';
import 'control_metrics.dart';
import 'nav_hover_underline.dart' show kSubNavActiveDarkColor;

/// The app-wide SECONDARY button: a tinted pill — pale fill, brand-blue label
/// and 16px icon, 12px w600 text, 12x8 padding, 10px radius, no border. It is
/// the look of "Change Section", "View Logs", "Add Schedule", "Upload GPA
/// Records" and every other non-primary action across the dashboards, so any
/// new secondary action should use this instead of an `OutlinedButton`,
/// `TextButton` or a module-local pill.
///
/// Primary actions (the solid navy/azure buttons) are a different style and
/// stay as they are.
///
/// With [expand] the pill stretches to the width its parent gives it (label
/// centered) instead of sizing to its content. [destructive] swaps the
/// brand-blue label for red (e.g. "Remove Photo"). [loading] swaps the icon
/// for a small spinner and blocks taps.
///
/// Reads `context.isDarkMode` for the dark variant by default; pass
/// [isDarkMode] explicitly when the button sits somewhere outside the page's
/// own Theme (a root-overlay popover).
class SecondaryPillButton extends StatelessWidget {
  const SecondaryPillButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.expand = false,
    this.loading = false,
    this.destructive = false,
    this.tooltip,
    this.isDarkMode,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool expand;
  final bool loading;
  final bool destructive;
  final String? tooltip;
  final bool? isDarkMode;

  // Brand azure (Registrar/Professor/IT `azureBlue`) and its fill — the
  // light fill is the dashboards' page background.
  static const _lightFill = Color(0xFFF0F5F8);
  static const _darkFill = Color(0xFF22242B);
  static const _lightLabel = Color(0xFF345892);
  static const _lightDanger = Color(0xFFDC2626);
  static const _darkDanger = Color(0xFFF87171);

  @override
  Widget build(BuildContext context) {
    final dark = isDarkMode ?? context.isDarkMode;
    final fill = dark ? _darkFill : _lightFill;
    final accent = destructive
        ? (dark ? _darkDanger : _lightDanger)
        : (dark ? kSubNavActiveDarkColor : _lightLabel);
    final disabled = onTap == null || loading;
    final foreground = onTap == null ? accent.withOpacity(0.5) : accent;

    final button = Material(
      color: onTap == null ? fill.withOpacity(0.5) : fill,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: disabled ? null : onTap,
        borderRadius: BorderRadius.circular(10),
        // Never shorter than the toolbar controls (search fields, dropdowns)
        // it sits beside.
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: kDashboardControlHeight),
          // widthFactor/heightFactor 1: size to the content (then to the
          // minimum height above) while keeping the label vertically
          // centered, instead of expanding to the parent's maximum.
          child: Align(
            widthFactor: 1,
            heightFactor: 1,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (loading) ...[
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: foreground,
                      ),
                    ),
                    const SizedBox(width: 6),
                  ] else if (icon != null) ...[
                    Icon(icon, size: 16, color: foreground),
                    const SizedBox(width: 6),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: foreground,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}
