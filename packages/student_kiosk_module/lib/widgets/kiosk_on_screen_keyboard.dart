import 'package:flutter/material.dart';

import '../theme/kiosk_colors.dart';
import 'kiosk_layout.dart' show kioskPoppins;

/// A big, touch-first on-screen keyboard for the kiosk's own text fields.
///
/// The kiosk runs full-screen on a touch display with no reliable OS soft
/// keyboard, so a staff member tapping a search box had no way to type.
/// This edits [controller] in place — inserting at the caret, honoring a
/// selection, and keeping focus on the field because its keys never take
/// focus — and calls [onChanged] after each edit, since `TextField.onChanged`
/// only fires for input the field itself received.
///
/// Pair it with `keyboardType: TextInputType.none` on the field so the OS
/// keyboard stays out of the way (a physical keyboard still types normally).
class KioskOnScreenKeyboard extends StatefulWidget {
  const KioskOnScreenKeyboard({
    super.key,
    required this.controller,
    this.onChanged,
    this.onDone,
    this.multiline = false,
  });

  final TextEditingController controller;

  /// Called with the new text after every key press.
  final ValueChanged<String>? onChanged;

  /// "Done" key — typically hides the keyboard.
  final VoidCallback? onDone;

  /// Adds an Enter key that inserts a line break (for notes fields).
  final bool multiline;

  @override
  State<KioskOnScreenKeyboard> createState() => _KioskOnScreenKeyboardState();
}

class _KioskOnScreenKeyboardState extends State<KioskOnScreenKeyboard> {
  static const _numberRow = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'];
  static const _letterRows = [
    ['q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p'],
    ['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l'],
    ['z', 'x', 'c', 'v', 'b', 'n', 'm'],
  ];

  /// One-shot shift: the next letter is upper-case, then it releases.
  bool _shift = false;

  TextEditingController get _c => widget.controller;

  void _apply(String text, int caret) {
    _c.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: caret),
    );
    widget.onChanged?.call(text);
  }

  (int, int) _range() {
    final value = _c.value;
    final sel = value.selection;
    final length = value.text.length;
    if (!sel.isValid) return (length, length);
    return (sel.start.clamp(0, length), sel.end.clamp(0, length));
  }

  void _type(String s) {
    final (start, end) = _range();
    final text = _c.text.replaceRange(start, end, s);
    _apply(text, start + s.length);
    if (_shift) setState(() => _shift = false);
  }

  void _backspace() {
    final (start, end) = _range();
    if (start != end) {
      _apply(_c.text.replaceRange(start, end, ''), start);
    } else if (start > 0) {
      _apply(_c.text.replaceRange(start - 1, start, ''), start - 1);
    }
  }

  void _clear() => _apply('', 0);

  Widget _key(
    String label, {
    required VoidCallback onTap,
    double flex = 1,
    Color? background,
    Color? foreground,
    IconData? icon,
    String? semanticLabel,
  }) {
    final fg = foreground ?? KioskColors.textPrimary;
    return Expanded(
      flex: (flex * 10).round(),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Semantics(
          button: true,
          label: semanticLabel ?? label,
          child: Material(
            color: background ?? KioskColors.cardWhite,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              // Never steal focus from the text field being edited.
              canRequestFocus: false,
              borderRadius: BorderRadius.circular(8),
              onTap: onTap,
              child: Container(
                height: 58,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: KioskColors.itemBorder),
                ),
                child: icon != null
                    ? Icon(icon, size: 28, color: fg)
                    : Text(
                        label,
                        style: kioskPoppins(
                          fontSize: 24,
                          fontWeight: FontWeight.w500,
                          color: fg,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(List<Widget> keys) => Row(children: keys);

  @override
  Widget build(BuildContext context) {
    String cased(String s) => _shift ? s.toUpperCase() : s;
    const accent = KioskColors.enabledButton;

    return Material(
      color: KioskColors.gradientTop,
      elevation: 12,
      child: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _row([
                    for (final n in _numberRow) _key(n, onTap: () => _type(n)),
                  ]),
                  _row([
                    for (final k in _letterRows[0])
                      _key(cased(k), onTap: () => _type(cased(k))),
                  ]),
                  _row([
                    const Spacer(flex: 5),
                    for (final k in _letterRows[1])
                      _key(cased(k), onTap: () => _type(cased(k))),
                    const Spacer(flex: 5),
                  ]),
                  _row([
                    _key(
                      '',
                      icon: Icons.keyboard_capslock_rounded,
                      semanticLabel: 'Shift',
                      flex: 1.5,
                      background: _shift ? accent : null,
                      foreground: _shift ? Colors.white : null,
                      onTap: () => setState(() => _shift = !_shift),
                    ),
                    for (final k in _letterRows[2])
                      _key(cased(k), onTap: () => _type(cased(k))),
                    _key(
                      '',
                      icon: Icons.backspace_outlined,
                      semanticLabel: 'Backspace',
                      flex: 1.5,
                      onTap: _backspace,
                    ),
                  ]),
                  _row([
                    _key('Clear', flex: 1.6, onTap: _clear),
                    _key('.', onTap: () => _type('.')),
                    _key('-', onTap: () => _type('-')),
                    _key(
                      'space',
                      flex: 4,
                      onTap: () => _type(' '),
                    ),
                    if (widget.multiline)
                      _key(
                        '',
                        icon: Icons.keyboard_return_rounded,
                        semanticLabel: 'New line',
                        flex: 1.4,
                        onTap: () => _type('\n'),
                      ),
                    _key(
                      'Done',
                      flex: 1.8,
                      background: accent,
                      foreground: Colors.white,
                      onTap: widget.onDone ?? () {},
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
