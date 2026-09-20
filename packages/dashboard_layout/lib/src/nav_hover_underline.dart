import 'package:flutter/material.dart';

/// Wraps a sub-navigation item so a blue underline grows out from its center
/// while the mouse hovers it — the same 2px underline the active tab already
/// shows, previewed on inactive tabs.
///
/// [child] must have a bounded size (e.g. a tab stretched to the bar's
/// height by its parent `Row`). The underline is drawn along [child]'s bottom
/// edge, so it lands exactly on top of the bar's own active-tab indicator.
/// Pass [isActive] for the currently selected tab — it already shows its own
/// underline, so nothing extra is drawn.
class NavHoverUnderline extends StatefulWidget {
  const NavHoverUnderline({
    super.key,
    required this.child,
    this.isActive = false,
    this.color = const Color(0xFF345892),
    this.thickness = 2,
  });

  final Widget child;
  final bool isActive;
  final Color color;
  final double thickness;

  @override
  State<NavHoverUnderline> createState() => _NavHoverUnderlineState();
}

class _NavHoverUnderlineState extends State<NavHoverUnderline> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final show = _hovered && !widget.isActive;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Stack(
        children: [
          widget.child,
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: widget.thickness,
            child: IgnorePointer(
              child: AnimatedFractionallySizedBox(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOut,
                widthFactor: show ? 1 : 0,
                alignment: Alignment.center,
                child: ColoredBox(color: widget.color),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
