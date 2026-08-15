import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Flutter's default [ScrollBehavior] leaves [PointerDeviceKind.mouse] out
/// of `dragDevices` (mouse click-drag is reserved for text selection etc.
/// by default), which leaves a horizontally-scrolling widget like a sub-nav
/// tab bar with no usable desktop input: a plain vertical mouse wheel
/// doesn't drive a horizontal `Scrollable`, and click-drag is disabled too
/// — the content past the visible edge becomes genuinely unreachable for a
/// mouse user, even though it scrolls fine on touch.
///
/// Wrap a horizontal `SingleChildScrollView` (or any other `Scrollable`)
/// with `ScrollConfiguration(behavior: mouseDraggableScrollBehavior, ...)`
/// so it can also be click-and-dragged.
final mouseDraggableScrollBehavior = _MouseDraggableScrollBehavior();

class _MouseDraggableScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        ...super.dragDevices,
        PointerDeviceKind.mouse,
      };
}
