import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'it_technician_dashboard_page.dart' show ItTechnicianColors;

/// Small building blocks shared by this package's own dialogs/toolbars
/// (reader form, student form, ticket detail, filter bars).
///
/// The popup pieces here — the dialog shell, the field label, the field
/// decoration, the primary and secondary pills — are thin wrappers over
/// `dashboard_layout`'s shared popup components (`AppPopup` and friends), so
/// an IT popup is built from exactly the same parts as every other popup in
/// the app instead of keeping a look of its own.

/// The primary pill — brand blue (or [background], e.g. the danger red for a
/// "Delete"), Poppins 12/w600, rounded-10. A thin wrapper over
/// [AppPopupPrimaryButton].
class PillButton extends StatelessWidget {
  const PillButton({
    super.key,
    required this.label,
    this.icon,
    required this.onTap,
    this.background,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;

  /// Defaults to the shared brand accent — pass e.g.
  /// [ItTechnicianColors.dangerRed] for a destructive action like "Delete".
  final Color? background;

  @override
  Widget build(BuildContext context) => AppPopupPrimaryButton(
        label: label,
        icon: icon,
        color: background,
        onPressed: onTap,
      );
}

/// The "Cancel"-style counterpart to [PillButton]: the app-wide secondary
/// pill.
class PaleButton extends StatelessWidget {
  const PaleButton({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) =>
      AppPopupSecondaryButton(label: label, onPressed: onTap);
}

/// Selectable filter pill — matches Registrar's own `SelectionPill` shape
/// (height 35, radius 10, solid azureBlue+white when selected, pale
/// fieldFill+rowText when not). Used in place of stock `ChoiceChip`s for
/// quick-filter rows (year level, status, …).
class FilterPill extends StatelessWidget {
  const FilterPill({
    super.key,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected
          ? ItTechnicianColors.azureBlue
          : ItTechnicianColors.fieldFill(context),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 35,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          child: Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: context.isMobileWidth ? 10 : 12,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              color: isSelected
                  ? Colors.white
                  : ItTechnicianColors.rowText(context),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small label placed above a field — the shared popup field label.
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) => AppPopupFieldLabel(label);
}

/// The popup field: pale, borderless, rounded-10 — the shared
/// [appPopupInputDecoration], reused by this package's `TextField` /
/// `DropdownButtonFormField`s.
InputDecoration fieldDecoration(
  BuildContext context, {
  String? hintText,
  Widget? prefixIcon,
}) =>
    appPopupInputDecoration(context, hint: hintText, prefixIcon: prefixIcon);

TextStyle fieldTextStyle(BuildContext context) => appPopupFieldStyle(context);

/// The dropdown arrow every reference `DropdownButtonFormField` uses.
Icon dropdownArrowIcon(BuildContext context) => Icon(
      Icons.keyboard_arrow_down_rounded,
      size: 20,
      color: ItTechnicianColors.mutedText(context),
    );

/// This package's dialog shell — [AppPopup], so it matches every other popup:
/// title + close header, scrollable body, right-aligned actions. [actions]
/// may still carry the old `SizedBox` spacers between buttons; the popup
/// spaces its own, so those are dropped.
class DialogShell extends StatelessWidget {
  const DialogShell({
    super.key,
    required this.title,
    required this.onClose,
    required this.body,
    required this.actions,
    this.width = 420,
  });

  final String title;

  /// Null disables the close button (a busy dialog).
  final VoidCallback? onClose;
  final Widget body;
  final List<Widget> actions;
  final double width;

  @override
  Widget build(BuildContext context) {
    return AppPopup(
      title: title,
      width: width,
      closeEnabled: onClose != null,
      onClose: onClose,
      body: body,
      actions: [
        for (final a in actions)
          if (!(a is SizedBox && a.child == null)) a,
      ],
    );
  }
}
