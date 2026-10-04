import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'mouse_draggable_scroll_behavior.dart';

/// A horizontally scrolling strip for a row of tabs that can be wider than
/// the screen. Scrolls by touch swipe, by mouse click-drag (Flutter's default
/// ignores the mouse), and by the mouse wheel / trackpad (a plain vertical
/// wheel turns the strip sideways while the pointer is over it, instead of
/// scrolling the page).
///
class HorizontalTabScroller extends StatefulWidget {
  const HorizontalTabScroller({
    super.key,
    required this.child,
    this.onOverflowChanged,
  });

  final Widget child;

  /// Told whether the content is currently wider than the strip (so it
  /// scrolls) — a tab then runs to the strip's right edge, which a
  /// caller may want to square off the corner beneath it.
  final ValueChanged<bool>? onOverflowChanged;

  @override
  State<HorizontalTabScroller> createState() => _HorizontalTabScrollerState();
}

class _HorizontalTabScrollerState extends State<HorizontalTabScroller> {
  final _controller = ScrollController();
  bool? _overflowing;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_controller.hasClients) return;
    final position = _controller.position;
    if (position.maxScrollExtent <= 0) return; // fits: let the page scroll
    // Horizontal gestures (trackpad / shift+wheel) already scroll natively;
    // translate a plain vertical wheel into sideways movement.
    final delta = event.scrollDelta.dx != 0
        ? event.scrollDelta.dx
        : event.scrollDelta.dy;
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      _controller.jumpTo(
        (position.pixels + delta).clamp(0.0, position.maxScrollExtent),
      );
    });
  }

  bool _onMetrics(ScrollMetricsNotification n) {
    final overflowing = n.metrics.maxScrollExtent > 0;
    if (overflowing != _overflowing) {
      _overflowing = overflowing;
      // Notifications arrive during layout; setState must wait.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onOverflowChanged?.call(overflowing);
      });
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: _onSignal,
      child: NotificationListener<ScrollMetricsNotification>(
        onNotification: _onMetrics,
        child: ScrollConfiguration(
          behavior: mouseDraggableScrollBehavior,
          child: SingleChildScrollView(
            controller: _controller,
            scrollDirection: Axis.horizontal,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
