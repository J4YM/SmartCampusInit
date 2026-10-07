import 'package:flutter/material.dart';

import 'app_popup.dart';

/// The app's confirm / small-form dialog — a title, arbitrary [content],
/// Cancel and a single confirm action — as an [AppPopup], so it is identical
/// to every other popup: same shell, header, palette, and footer pills.
///
/// Kept as its own entry point (many dialogs: "Rename X", "Delete X",
/// "Unsaved changes", "Sign out"), now a thin wrapper over [AppPopup]. The
/// colour parameters older call sites still pass ([backgroundColor] and
/// friends) are ignored: the popup palette is one shared set
/// ([AppPopupColors]), so no module can drift from it.
class BentoFormDialog extends StatelessWidget {
  const BentoFormDialog({
    super.key,
    required this.title,
    required this.content,
    required this.cancelLabel,
    required this.onCancel,
    required this.confirmLabel,
    required this.onConfirm,
    @Deprecated('Ignored: popups share one palette (AppPopupColors).')
    this.backgroundColor,
    @Deprecated('Ignored: popups share one palette (AppPopupColors).')
    this.borderColor,
    @Deprecated('Ignored: popups share one palette (AppPopupColors).')
    this.titleColor,
    @Deprecated('Ignored: popups share one palette (AppPopupColors).')
    this.cancelFillColor,
    this.confirmColor = AppPopupColors.accent,
    this.width = 380,
    this.isDarkMode,
    this.confirmEnabled = true,
    this.confirmKey,
    this.cancelKey,
  });

  final String title;
  final Widget content;
  final String cancelLabel;
  final VoidCallback onCancel;
  final String confirmLabel;
  final VoidCallback onConfirm;

  final Color? backgroundColor;
  final Color? borderColor;
  final Color? titleColor;
  final Color? cancelFillColor;

  /// Fill for the confirm pill — the shared brand blue; pass a danger color
  /// (e.g. for "Delete") to override.
  final Color confirmColor;

  final double width;

  /// See [AppPopup.isDarkMode] — pass it (or open the popup with
  /// [showAppPopup]) since this renders through the root navigator's overlay,
  /// outside any per-page Theme.
  final bool? isDarkMode;

  /// When false the confirm pill is dimmed and does nothing — e.g. a "Send"
  /// that needs a non-empty message first.
  final bool confirmEnabled;

  /// Keys for the two pills, for tests and callers that need to find them.
  final Key? confirmKey;
  final Key? cancelKey;

  @override
  Widget build(BuildContext context) {
    return AppPopup(
      title: title,
      width: width,
      isDarkMode: isDarkMode,
      onClose: onCancel,
      body: content,
      actions: [
        AppPopupSecondaryButton(
          key: cancelKey,
          label: cancelLabel,
          onPressed: onCancel,
          isDarkMode: isDarkMode,
        ),
        AppPopupPrimaryButton(
          key: confirmKey,
          label: confirmLabel,
          color: confirmColor,
          onPressed: confirmEnabled ? onConfirm : null,
        ),
      ],
    );
  }
}
