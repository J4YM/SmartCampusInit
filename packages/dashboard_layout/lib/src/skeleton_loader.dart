import 'package:flutter/material.dart';

/// Drives one shared pulse animation for descendant [SkeletonBox]es via
/// [builder] — use this instead of letting each [SkeletonBox] animate
/// independently when a screen has many of them (a whole table of skeleton
/// rows, a stat-tile row, a card list), so there's one [AnimationController]
/// driving the lot instead of dozens ticking (and drifting) independently.
///
/// Same 1100ms / 0.4→0.9 opacity pulse every hand-rolled per-page skeleton
/// in this app already used before this widget existed (see
/// admin_dashboard's `_SkeletonTableBody`, discipline_officer_module's
/// `_QueueSkeletonList`, rfid_management_module's student records tab) —
/// formalized here as the one shared version every dashboard's loading
/// state should build on.
class SkeletonPulse extends StatefulWidget {
  const SkeletonPulse({super.key, required this.builder});

  final Widget Function(BuildContext context, double opacity) builder;

  @override
  State<SkeletonPulse> createState() => _SkeletonPulseState();
}

class _SkeletonPulseState extends State<SkeletonPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);
  late final Animation<double> _opacity = Tween<double>(begin: 0.4, end: 0.9)
      .animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _opacity,
      builder: (context, _) => widget.builder(context, _opacity.value),
    );
  }
}

/// A single pulsing placeholder bar — the basic unit every dashboard's
/// skeleton loading screen is built from.
///
/// Pass [opacity] when several boxes should pulse together under one
/// [SkeletonPulse] (a row of stat tiles, a table's worth of rows) — that's
/// the common case for a whole skeleton *screen*. Omit it for a one-off box
/// used on its own, which then drives its own pulse independently.
///
/// [color] is required rather than defaulted, since every dashboard module
/// already owns its own per-page dark-mode color tokens (no shared color
/// class) — pass that module's muted/placeholder-fill token through, same
/// convention as [BentoCard]'s `backgroundColor`/`borderColor`.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    required this.color,
    this.width,
    this.height = 12,
    this.borderRadius = 6,
    this.opacity,
  });

  final Color color;
  final double? width;
  final double height;
  final double borderRadius;

  /// Current pulse value from an enclosing [SkeletonPulse]. Leave `null` to
  /// have this box drive its own independent pulse instead.
  final double? opacity;

  @override
  Widget build(BuildContext context) {
    final fixedOpacity = opacity;
    if (fixedOpacity != null) return _box(fixedOpacity);
    return SkeletonPulse(builder: (context, o) => _box(o));
  }

  Widget _box(double o) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color.withOpacity(o),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}

/// Circular pulsing placeholder — avatars, status dots, icon badges. Same
/// shared/standalone-pulse rule as [SkeletonBox].
class SkeletonCircle extends StatelessWidget {
  const SkeletonCircle({
    super.key,
    required this.color,
    required this.diameter,
    this.opacity,
  });

  final Color color;
  final double diameter;
  final double? opacity;

  @override
  Widget build(BuildContext context) {
    final fixedOpacity = opacity;
    if (fixedOpacity != null) return _circle(fixedOpacity);
    return SkeletonPulse(builder: (context, o) => _circle(o));
  }

  Widget _circle(double o) {
    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        color: color.withOpacity(o),
        shape: BoxShape.circle,
      ),
    );
  }
}
