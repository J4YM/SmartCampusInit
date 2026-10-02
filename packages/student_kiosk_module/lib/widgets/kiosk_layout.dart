import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/violation_models.dart';
import '../theme/kiosk_colors.dart';

/// Shared building blocks of the kiosk's big, touch-first layout — the
/// student self-report screen (`ViolationKioskScreen`) and the Security
/// report screen are both assembled from these so they stay visually
/// identical: navy header, soft gradient page, a centered 920px column of
/// white cards, 24px Poppins text, and full-width confirm button.

TextStyle kioskPoppins({
  double fontSize = 14,
  FontWeight fontWeight = FontWeight.w400,
  Color color = KioskColors.textPrimary,
  double height = 1.35,
}) {
  return GoogleFonts.poppins(
    fontSize: fontSize,
    fontWeight: fontWeight,
    color: color,
    height: height,
  );
}

/// Full kiosk page: [KioskHeader] over a gradient, scrolling, centered
/// column of [children] capped at 920px.
class KioskPage extends StatelessWidget {
  const KioskPage({
    super.key,
    required this.children,
    this.headerSubtitle = 'Virtual Admission Kiosk',
  });

  final List<Widget> children;
  final String headerSubtitle;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KioskColors.gradientTop,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KioskHeader(subtitle: headerSubtitle),
          Expanded(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    KioskColors.gradientTop,
                    KioskColors.gradientBottom,
                  ],
                ),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 920),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: children,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class KioskHeader extends StatelessWidget {
  const KioskHeader({super.key, this.subtitle = 'Virtual Admission Kiosk'});

  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: KioskColors.dashboardHeaderNavy,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
          child: Column(
            children: [
              Text(
                'STI College Baliuag',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w400,
                  color: Colors.white.withOpacity(0.95),
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// White, rounded, softly shadowed kiosk card.
class KioskCard extends StatelessWidget {
  const KioskCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: KioskColors.cardWhite,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// The small muted "‹ Back" action that pops the kiosk screen.
class KioskBackButton extends StatelessWidget {
  const KioskBackButton({super.key});

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: () {
        // Drop the button's focus first so it doesn't stay highlighted (or get
        // restored) on the screen this returns to.
        FocusManager.instance.primaryFocus?.unfocus();
        Navigator.of(context).maybePop();
      },
      style: TextButton.styleFrom(
        foregroundColor: KioskColors.textSecondary,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),
      icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 16),
      label: Text(
        'Back',
        style: kioskPoppins(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: KioskColors.textSecondary,
        ),
      ),
    );
  }
}

/// Muted 24px card heading (e.g. "Teacher / Adviser").
class KioskFieldLabel extends StatelessWidget {
  const KioskFieldLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: kioskPoppins(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: KioskColors.textSecondary,
      ),
    );
  }
}

/// Input decoration shared by the kiosk's dropdowns and text fields: pale
/// fill, light border, 8px corners.
InputDecoration kioskInputDecoration({String? hintText, Widget? suffixIcon}) {
  const border = OutlineInputBorder(
    borderRadius: BorderRadius.all(Radius.circular(8)),
    borderSide: BorderSide(color: KioskColors.itemBorder),
  );
  return InputDecoration(
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    filled: true,
    fillColor: KioskColors.gradientTop,
    hintText: hintText,
    hintStyle: kioskPoppins(
      fontSize: 24,
      fontWeight: FontWeight.w400,
      color: KioskColors.textMuted,
    ),
    suffixIcon: suffixIcon,
    border: border,
    enabledBorder: border,
    focusedBorder: const OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(8)),
      borderSide: BorderSide(color: KioskColors.alertBorder, width: 1.5),
    ),
  );
}

class KioskInstructionAlert extends StatelessWidget {
  const KioskInstructionAlert({
    super.key,
    required this.title,
    required this.body,
  });

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: KioskColors.alertBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: KioskColors.alertBorder.withOpacity(0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: KioskColors.alertBorder,
            size: 26,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: kioskPoppins(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: KioskColors.alertTitle,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: kioskPoppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: KioskColors.alertBody,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class KioskViolationCategoryCard extends StatelessWidget {
  const KioskViolationCategoryCard({
    super.key,
    required this.category,
    required this.selectedCodes,
    required this.onToggle,
  });

  final ViolationCategoryData category;
  final Set<String> selectedCodes;
  final void Function(String code) onToggle;

  @override
  Widget build(BuildContext context) {
    return KioskCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: category.badgeBackground,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              category.badgeLabel,
              style: kioskPoppins(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: category.badgeForeground,
              ),
            ),
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < category.items.length; i++) ...[
            if (i > 0) const SizedBox(height: 16),
            KioskSelectableRow(
              selected: selectedCodes.contains(category.items[i].code),
              onTap: () => onToggle(category.items[i].code),
              child: Text(
                category.items[i].title,
                style: kioskPoppins(
                  fontSize: 24,
                  fontWeight: FontWeight.w500,
                  color: KioskColors.textPrimary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Bordered, full-width tappable row; shows a [KioskCheckbox] when
/// [selected] is non-null.
class KioskSelectableRow extends StatelessWidget {
  const KioskSelectableRow({
    super.key,
    required this.onTap,
    required this.child,
    this.selected,
  });

  final VoidCallback onTap;
  final Widget child;
  final bool? selected;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          FocusManager.instance.primaryFocus?.unfocus();
          onTap();
        },
        borderRadius: BorderRadius.circular(10),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: KioskColors.cardWhite,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: KioskColors.itemBorder),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (selected != null) ...[
                KioskCheckbox(checked: selected!),
                const SizedBox(width: 14),
              ],
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

class KioskCheckbox extends StatelessWidget {
  const KioskCheckbox({super.key, required this.checked});

  final bool checked;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: checked ? KioskColors.headerNavy : Colors.white,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: checked ? KioskColors.headerNavy : KioskColors.checkboxBorder,
          width: 1.5,
        ),
      ),
      child: checked
          ? const Icon(Icons.check, size: 14, color: Colors.white)
          : null,
    );
  }
}

class KioskSelectedCountCard extends StatelessWidget {
  const KioskSelectedCountCard({
    super.key,
    required this.selectedCount,
    required this.caption,
  });

  final int selectedCount;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return KioskCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$selectedCount violation(s) selected',
            style: kioskPoppins(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: KioskColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            caption,
            style: kioskPoppins(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: KioskColors.textSecondary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// Sized to match the "Print" button on the virtual admission slip preview
/// screen (`admission_slip_generated_view.dart`'s `_ActionArea`): same label
/// font size, vertical padding, and corner radius, stretched full-width.
class KioskConfirmButton extends StatelessWidget {
  const KioskConfirmButton({
    super.key,
    required this.label,
    required this.enabled,
    required this.busy,
    required this.onPressed,
    this.busyLabel = 'Submitting...',
  });

  final String label;
  final String busyLabel;
  final bool enabled;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed == null
          ? null
          : () {
              FocusManager.instance.primaryFocus?.unfocus();
              onPressed!();
            },
      icon: busy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Icon(Icons.check_rounded, size: 20),
      label: Text(
        busy ? busyLabel : label,
        style: kioskPoppins(
          fontSize: 23,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
      style: FilledButton.styleFrom(
        backgroundColor:
            enabled ? KioskColors.enabledButton : KioskColors.disabledButton,
        foregroundColor: Colors.white,
        disabledBackgroundColor: KioskColors.disabledButton,
        disabledForegroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        elevation: 0,
      ),
    );
  }
}
