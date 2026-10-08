import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'bento_card.dart';
import 'brightness_x.dart';
import 'control_metrics.dart';
import 'danger_color.dart';
import 'nav_hover_underline.dart' show kSubNavActiveDarkColor;
import 'poppins_theme.dart' show kDarkCheckboxCheckColor;
import 'responsive_x.dart';
import 'secondary_pill_button.dart';

/// THE popup design. Every dialog in the app — confirmations, forms, detail
/// views, pickers — is built from [AppPopup] and the pieces in this file, so
/// they all share one shell (a rounded, bordered, softly-shadowed card), one
/// header (a 18px title — 16px on a phone — with a close button and an
/// optional one-line subtitle), one palette, one set of field and button
/// styles, and one footer (secondary action left of the primary action, right
/// aligned). Only a popup's body differs.
///
/// (The Filter popup keeps its own, separate design — see `FilterMenuButton`.)

/// The popup palette — one set of colors for every popup, in both themes.
class AppPopupColors {
  const AppPopupColors(this.dark);

  /// The palette for [context]'s theme, or for [isDarkMode] when given (a
  /// popup renders in the root overlay, outside the page's own Theme).
  factory AppPopupColors.of(BuildContext context, {bool? isDarkMode}) =>
      AppPopupColors(isDarkMode ?? context.isDarkMode);

  final bool dark;

  Color get card => dark ? const Color(0xFF191A1F) : Colors.white;
  Color get border => dark ? const Color(0xFF22242B) : const Color(0x0DE2E8F0);
  Color get text => dark ? const Color(0xFFF5F5F5) : const Color(0xFF1E293B);
  Color get muted => dark ? const Color(0xFFA1A1AA) : const Color(0xFF64748B);

  /// Fill of fields and of the sunken "well" cards inside a popup.
  Color get fieldFill => dark ? const Color(0xFF0E0E0E) : const Color(0xFFF1F5F9);

  /// Fill of the secondary (Cancel-style) pill.
  Color get secondaryFill =>
      dark ? const Color(0xFF22242B) : const Color(0xFFF0F5F8);

  /// The brand blue every primary action uses.
  static const Color accent = Color(0xFF345892);

  /// Danger / error text, and a destructive action's fill.
  static const Color danger = kDangerTextColor;
}

/// Opens a popup built by [builder] — a [AppPopup], usually — through the root
/// navigator, carrying the CALLING page's theme into it. A dialog lives in the
/// root overlay, outside the dashboard's own per-page Theme, so without this
/// its colors would follow the app's ambient (light) theme instead of the
/// dashboard's dark-mode toggle. Use this instead of a bare `showDialog` for
/// every popup.
Future<T?> showAppPopup<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  final theme = Theme.of(context);
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (dialogContext) =>
        Theme(data: theme, child: Builder(builder: builder)),
  );
}

/// The popup shell: header (title, close, subtitle), a scrolling [body], and
/// right-aligned [actions]. See the library comment above.
class AppPopup extends StatelessWidget {
  const AppPopup({
    super.key,
    required this.title,
    required this.body,
    this.subtitle,
    this.actions = const [],
    this.width = 460,
    this.onClose,
    this.closeEnabled = true,
    this.scrollBody = true,
    this.isDarkMode,
  });

  final String title;

  /// One muted line under the title.
  final String? subtitle;
  final Widget body;

  /// Footer buttons, laid out right-aligned with 10px between: put the
  /// secondary action first (left), the primary last.
  final List<Widget> actions;
  final double width;

  /// What the close button does; by default it pops the popup.
  final VoidCallback? onClose;

  /// False while the popup is busy (saving, uploading): the close button dims.
  final bool closeEnabled;

  /// Wrap [body] in a scroll view. Turn off when the body scrolls on its own
  /// (a list) and needs a bounded height instead.
  final bool scrollBody;

  /// Overrides the theme lookup — see [AppPopupColors.of].
  final bool? isDarkMode;

  @override
  Widget build(BuildContext context) {
    final c = AppPopupColors.of(context, isDarkMode: isDarkMode);
    final mobile = context.isMobileWidth;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: SizedBox(
        width: width,
        child: BentoCard(
          backgroundColor: c.card,
          borderColor: c.border,
          isDarkMode: c.dark,
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppPopupHeader(
                title: title,
                subtitle: subtitle,
                onClose: closeEnabled
                    ? (onClose ?? () => Navigator.of(context).pop())
                    : null,
                isDarkMode: c.dark,
              ),
              const SizedBox(height: 20),
              Flexible(
                child: scrollBody ? SingleChildScrollView(child: body) : body,
              ),
              if (actions.isNotEmpty) ...[
                SizedBox(height: mobile ? 16 : 20),
                // Right-aligned with 10px between; on a very narrow popup the
                // buttons wrap onto a second line rather than overflow.
                SizedBox(
                  width: double.infinity,
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 10,
                    runSpacing: 10,
                    children: actions,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A popup's header: the title, a close button, and an optional subtitle. Used
/// by [AppPopup] and by popups that open as a bottom sheet on a phone (see
/// `showResponsiveSheet`), so a sheet and a dialog read the same.
class AppPopupHeader extends StatelessWidget {
  const AppPopupHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.onClose,
    this.isDarkMode,
  });

  final String title;
  final String? subtitle;

  /// Null dims the close button (a busy popup).
  final VoidCallback? onClose;
  final bool? isDarkMode;

  @override
  Widget build(BuildContext context) {
    final c = AppPopupColors.of(context, isDarkMode: isDarkMode);
    final mobile = context.isMobileWidth;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: GoogleFonts.poppins(
                  fontSize: mobile ? 16 : 18,
                  fontWeight: FontWeight.w600,
                  color: c.text,
                ),
              ),
            ),
            Tooltip(
              message: 'Close',
              child: InkWell(
                key: const Key('popup-close'),
                onTap: onClose,
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.close_rounded,
                    size: 22,
                    color: onClose == null ? c.muted : c.text,
                  ),
                ),
              ),
            ),
          ],
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            style: GoogleFonts.poppins(
              fontSize: mobile ? 11 : 12,
              fontWeight: FontWeight.w400,
              color: c.muted,
            ),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Buttons
// ---------------------------------------------------------------------------

/// The popup's primary action: the brand-blue pill (a destructive action
/// passes [destructive] for the danger fill). A disabled one is the same color
/// at half strength — never Material's grey. A [FilledButton] underneath, so a
/// caller can give it a `key` and read its `onPressed`.
class AppPopupPrimaryButton extends StatelessWidget {
  const AppPopupPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.destructive = false,
    this.color,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final bool destructive;

  /// An explicit fill, overriding the brand blue / danger red.
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: loading ? null : onPressed,
      style: appPrimaryButtonStyle(destructive: destructive, color: color),
      child: loading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 16, color: Colors.white),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

/// The primary pill's [ButtonStyle], for a [FilledButton] that needs its own
/// child (an icon beside a label, a spinner): brand blue (or the danger red),
/// 12x8 padding, 10px radius, 34px tall, half-strength when disabled.
ButtonStyle appPrimaryButtonStyle({bool destructive = false, Color? color}) {
  final fill =
      color ?? (destructive ? AppPopupColors.danger : AppPopupColors.accent);
  return FilledButton.styleFrom(
    backgroundColor: fill,
    foregroundColor: Colors.white,
    disabledBackgroundColor: fill.withOpacity(0.5),
    disabledForegroundColor: Colors.white.withOpacity(0.6),
    elevation: 0,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    minimumSize: const Size(0, kDashboardControlHeight),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    visualDensity: VisualDensity.standard,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
  );
}

/// The popup's secondary action — the app-wide secondary pill.
class AppPopupSecondaryButton extends StatelessWidget {
  const AppPopupSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.isDarkMode,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool? isDarkMode;

  @override
  Widget build(BuildContext context) => SecondaryPillButton(
        label: label,
        icon: icon,
        onTap: onPressed,
        isDarkMode: isDarkMode,
      );
}

// ---------------------------------------------------------------------------
// Form pieces
// ---------------------------------------------------------------------------

/// The field every popup form uses: pale, borderless, rounded-10, a hint
/// inside, a blue outline on focus and a red one on an error.
InputDecoration appPopupInputDecoration(
  BuildContext context, {
  String? hint,
  String? errorText,
  String? helperText,
  Widget? suffixIcon,
  Widget? prefixIcon,
  bool? isDarkMode,
}) {
  final c = AppPopupColors.of(context, isDarkMode: isDarkMode);
  final mobile = context.isMobileWidth;
  OutlineInputBorder outline(Color color, double width) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: color, width: width),
      );
  final borderless = OutlineInputBorder(
    borderRadius: BorderRadius.circular(10),
    borderSide: BorderSide.none,
  );
  return InputDecoration(
    hintText: hint,
    hintStyle: GoogleFonts.poppins(
      fontSize: mobile ? 11 : 13,
      color: c.muted,
    ),
    errorText: errorText,
    errorStyle: GoogleFonts.poppins(
      fontSize: mobile ? 10 : 11,
      color: AppPopupColors.danger,
    ),
    helperText: helperText,
    helperMaxLines: 3,
    helperStyle: GoogleFonts.poppins(
      fontSize: mobile ? 10 : 11,
      color: c.muted,
    ),
    suffixIcon: suffixIcon,
    prefixIcon: prefixIcon,
    isDense: true,
    filled: true,
    fillColor: c.fieldFill,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    border: borderless,
    enabledBorder: borderless,
    disabledBorder: borderless,
    focusedBorder: outline(AppPopupColors.accent, 1.5),
    errorBorder: outline(AppPopupColors.danger, 1),
    focusedErrorBorder: outline(AppPopupColors.danger, 1.5),
  );
}

/// The text inside a popup field.
TextStyle appPopupFieldStyle(BuildContext context, {bool? isDarkMode}) =>
    GoogleFonts.poppins(
      fontSize: context.isMobileWidth ? 11 : 13,
      color: AppPopupColors.of(context, isDarkMode: isDarkMode).text,
    );

/// A small label above a field.
class AppPopupFieldLabel extends StatelessWidget {
  const AppPopupFieldLabel(this.label, {super.key, this.isDarkMode});

  final String label;
  final bool? isDarkMode;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        label,
        style: GoogleFonts.poppins(
          fontSize: context.isMobileWidth ? 10 : 12,
          fontWeight: FontWeight.w500,
          color: AppPopupColors.of(context, isDarkMode: isDarkMode).text,
        ),
      ),
    );
  }
}

/// A label above a text field — one row of a popup form.
class AppPopupTextField extends StatelessWidget {
  const AppPopupTextField({
    super.key,
    required this.label,
    required this.controller,
    this.fieldKey,
    this.hint,
    this.errorText,
    this.keyboardType,
    this.onChanged,
    this.obscureText = false,
    this.maxLines = 1,
    this.minLines,
    this.enabled = true,
    this.suffixIcon,
    this.isDarkMode,
  });

  final String label;
  final TextEditingController controller;

  /// The key of the [TextField] itself (the wrapper takes [key]).
  final Key? fieldKey;
  final String? hint;
  final String? errorText;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  final bool obscureText;
  final int? maxLines;
  final int? minLines;
  final bool enabled;
  final Widget? suffixIcon;
  final bool? isDarkMode;

  @override
  Widget build(BuildContext context) {
    final c = AppPopupColors.of(context, isDarkMode: isDarkMode);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppPopupFieldLabel(label, isDarkMode: c.dark),
        TextField(
          key: fieldKey,
          controller: controller,
          keyboardType: keyboardType,
          onChanged: onChanged,
          obscureText: obscureText,
          maxLines: maxLines,
          minLines: minLines,
          enabled: enabled,
          style: appPopupFieldStyle(context, isDarkMode: c.dark),
          cursorColor: AppPopupColors.accent,
          decoration: appPopupInputDecoration(
            context,
            hint: hint,
            errorText: errorText,
            suffixIcon: suffixIcon,
            isDarkMode: c.dark,
          ),
        ),
      ],
    );
  }
}

/// The gap between two popup form rows.
const SizedBox kAppPopupFieldGap = SizedBox(height: 14);

/// A group heading inside a popup form: an icon, the title, and a hairline
/// running out to the edge — "Student Information", "Parent / Guardian".
class AppPopupSection extends StatelessWidget {
  const AppPopupSection(this.title, {super.key, this.icon, this.isDarkMode});

  final String title;

  /// A leading 18px brand-blue icon; none for a plain heading.
  final IconData? icon;
  final bool? isDarkMode;

  @override
  Widget build(BuildContext context) {
    final c = AppPopupColors.of(context, isDarkMode: isDarkMode);
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 10),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: AppPopupColors.accent),
            const SizedBox(width: 8),
          ],
          Text(
            title,
            style: GoogleFonts.poppins(
              fontSize: context.isMobileWidth ? 12 : 13.5,
              fontWeight: FontWeight.w600,
              color: c.text,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Divider(height: 1, color: c.border)),
        ],
      ),
    );
  }
}

/// One labelled field of an [AppPopupFormRow], sized by [flex] when the row is
/// side by side.
class AppPopupFormCell extends StatelessWidget {
  const AppPopupFormCell({
    super.key,
    required this.label,
    required this.child,
    this.flex = 1,
    this.isDarkMode,
  });

  final String label;
  final Widget child;
  final int flex;
  final bool? isDarkMode;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [AppPopupFieldLabel(label, isDarkMode: isDarkMode), child],
    );
  }
}

/// A row of [AppPopupFormCell]s: side by side (by their flex) when there is
/// room, stacked into a single column on a narrow popup or a phone. 14px
/// below, so rows keep the popup's even rhythm.
class AppPopupFormRow extends StatelessWidget {
  const AppPopupFormRow({super.key, required this.children});

  final List<AppPopupFormCell> children;

  static const double _gap = 16;
  static const double _stackBelow = 520;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < _stackBelow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) const SizedBox(height: 14),
                  children[i],
                ],
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(width: _gap),
                Expanded(flex: children[i].flex, child: children[i]),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// An error line at the top or bottom of a popup body.
class AppPopupError extends StatelessWidget {
  const AppPopupError(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) => Text(
        message,
        style: GoogleFonts.poppins(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: AppPopupColors.danger,
        ),
      );
}

// ---------------------------------------------------------------------------
// Message dialog
// ---------------------------------------------------------------------------

/// A plain message popup: a title, a block of text (scrolls if long) and a
/// single OK button — for results and errors ("Some rows could not be
/// imported", "Import failed"). Pass [selectable] for text a person may want
/// to copy (an error's details).
Future<void> showAppMessage(
  BuildContext context, {
  required String title,
  required String message,
  bool selectable = false,
  String buttonLabel = 'OK',
  double width = 460,
}) {
  return showAppPopup<void>(
    context: context,
    builder: (dialogContext) {
      final style = GoogleFonts.poppins(
        fontSize: dialogContext.isMobileWidth ? 11 : 13,
        height: 1.5,
        color: AppPopupColors.of(dialogContext).text,
      );
      return AppPopup(
        title: title,
        width: width,
        body: selectable
            ? SelectableText(message, style: style)
            : Text(message, style: style),
        actions: [
          AppPopupPrimaryButton(
            key: const Key('popup-message-ok'),
            label: buttonLabel,
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
        ],
      );
    },
  );
}

/// A label over a dropdown — one row of a popup form, in the same field style
/// as [AppPopupTextField].
class AppPopupDropdown<T> extends StatelessWidget {
  const AppPopupDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.hint,
    this.isDarkMode,
  });

  final String label;
  final T? value;
  final List<DropdownMenuItem<T>> items;

  /// Null disables the dropdown.
  final ValueChanged<T?>? onChanged;
  final String? hint;
  final bool? isDarkMode;

  @override
  Widget build(BuildContext context) {
    final c = AppPopupColors.of(context, isDarkMode: isDarkMode);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppPopupFieldLabel(label, isDarkMode: c.dark),
        DropdownButtonFormField<T>(
          value: value,
          isExpanded: true,
          icon: Icon(Icons.keyboard_arrow_down_rounded,
              size: 20, color: c.muted),
          style: appPopupFieldStyle(context, isDarkMode: c.dark),
          dropdownColor: c.card,
          decoration:
              appPopupInputDecoration(context, hint: hint, isDarkMode: c.dark),
          items: items,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

/// A tick-box row for a popup: the field fill as its background, the brand-blue
/// check, a title and an optional muted subtitle. The whole row toggles.
class AppPopupCheckboxTile extends StatelessWidget {
  const AppPopupCheckboxTile({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.isDarkMode,
  });

  final String title;
  final String? subtitle;
  final bool value;

  /// Null disables the row.
  final ValueChanged<bool>? onChanged;
  final bool? isDarkMode;

  @override
  Widget build(BuildContext context) {
    final c = AppPopupColors.of(context, isDarkMode: isDarkMode);
    final mobile = context.isMobileWidth;
    return Material(
      color: c.fieldFill,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onChanged == null ? null : () => onChanged!(!value),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              SizedBox(
                width: 32,
                height: 32,
                child: Checkbox(
                  value: value,
                  // Light blue (#A9C6FD) in dark mode, like every checkbox.
                  activeColor:
                      c.dark ? kSubNavActiveDarkColor : AppPopupColors.accent,
                  checkColor: c.dark ? kDarkCheckboxCheckColor : null,
                  side: BorderSide(color: c.muted, width: 1.5),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.standard,
                  onChanged:
                      onChanged == null ? null : (v) => onChanged!(v ?? false),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.poppins(
                        fontSize: mobile ? 11 : 13,
                        fontWeight: FontWeight.w500,
                        color: c.text,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: GoogleFonts.poppins(
                          fontSize: mobile ? 10 : 11,
                          color: c.muted,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
            ],
          ),
        ),
      ),
    );
  }
}
