import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'it_technician_dashboard_page.dart' show ItTechnicianColors;

/// Small building blocks shared by this package's own dialogs/toolbars
/// (reader form, student form, ticket detail, filter bars) — extracted here
/// rather than duplicated a third time, same reasoning as
/// `discipline_officer_module`'s `mailbox_list_scaffold.dart`. Match the
/// shared design language's own dialog-action pill (`ReportTechnicalIssueDialog`)
/// and field (`_fieldDecoration`) conventions used across every other
/// dashboard's own dialogs.

/// Solid azureBlue pill button — the primary-action pill used across every
/// dashboard (rounded-10, Poppins 12/w600).
class PillButton extends StatelessWidget {
  const PillButton({
    super.key,
    required this.label,
    this.icon,
    required this.onTap,
    this.background = ItTechnicianColors.azureBlue,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;

  /// Defaults to the shared brand accent — pass e.g.
  /// [ItTechnicianColors.dangerRed] for a destructive action like "Delete".
  final Color background;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return Material(
      color: disabled ? background.withOpacity(0.5) : background,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon,
                    size: 16, color: Colors.white.withOpacity(disabled ? 0.6 : 1)),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: context.isMobileWidth ? 10 : 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withOpacity(disabled ? 0.6 : 1),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pale-background secondary pill — the "Cancel"-style counterpart to
/// [PillButton].
class PaleButton extends StatelessWidget {
  const PaleButton({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return Material(
      color: ItTechnicianColors.fieldFill(context),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: context.isMobileWidth ? 11 : 13,
              fontWeight: FontWeight.w600,
              color: disabled
                  ? ItTechnicianColors.rowText(context).withOpacity(0.6)
                  : ItTechnicianColors.rowText(context),
            ),
          ),
        ),
      ),
    );
  }
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
      color: isSelected ? ItTechnicianColors.azureBlue : ItTechnicianColors.fieldFill(context),
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
              color: isSelected ? Colors.white : ItTechnicianColors.rowText(context),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small label placed above a field — matches every other dashboard's own
/// form-field label convention.
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        label,
        style: GoogleFonts.poppins(
          fontSize: context.isMobileWidth ? 10 : 12,
          fontWeight: FontWeight.w500,
          color: ItTechnicianColors.rowText(context),
        ),
      ),
    );
  }
}

/// Pale, borderless rounded-10 field decoration — matches
/// `ReportTechnicalIssueDialog`'s own `_fieldDecoration` shape, reused by
/// this package's `TextField`/`DropdownButtonFormField`s.
InputDecoration fieldDecoration(
  BuildContext context, {
  String? hintText,
  Widget? prefixIcon,
}) {
  final borderless = OutlineInputBorder(
    borderRadius: BorderRadius.circular(10),
    borderSide: BorderSide.none,
  );
  return InputDecoration(
    hintText: hintText,
    hintStyle: GoogleFonts.poppins(
      fontSize: context.isMobileWidth ? 11 : 13,
      color: ItTechnicianColors.mutedText(context),
    ),
    prefixIcon: prefixIcon,
    isDense: true,
    filled: true,
    fillColor: ItTechnicianColors.fieldFill(context),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    border: borderless,
    enabledBorder: borderless,
    disabledBorder: borderless,
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: ItTechnicianColors.azureBlue, width: 1.5),
    ),
  );
}

TextStyle fieldTextStyle(BuildContext context) => GoogleFonts.poppins(
      fontSize: context.isMobileWidth ? 11 : 13,
      color: ItTechnicianColors.rowText(context),
    );

/// The dropdown arrow every reference `DropdownButtonFormField` uses.
Icon dropdownArrowIcon(BuildContext context) => Icon(
      Icons.keyboard_arrow_down_rounded,
      size: 20,
      color: ItTechnicianColors.mutedText(context),
    );

/// Rounded-16 dialog card shell — matches `ReportTechnicalIssueDialog`'s own
/// shell (title + close-X header, scrollable body, right-aligned actions).
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
  final VoidCallback? onClose;
  final Widget body;
  final List<Widget> actions;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        width: width,
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
        decoration: BoxDecoration(
          color: ItTechnicianColors.card(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: ItTechnicianColors.cardBorder(context)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: GoogleFonts.poppins(
                      fontSize: context.isMobileWidth ? 16 : 18,
                      fontWeight: FontWeight.w600,
                      color: ItTechnicianColors.rowText(context),
                    ),
                  ),
                ),
                InkWell(
                  onTap: onClose,
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.close_rounded,
                      size: 22,
                      color: ItTechnicianColors.rowText(context),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Flexible(child: SingleChildScrollView(child: body)),
            const SizedBox(height: 20),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: actions),
          ],
        ),
      ),
    );
  }
}
