import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'brightness_x.dart';

/// A table's rows, stacked top to bottom, that animate when new data arrives.
///
/// Give every row a stable [Key] (`ValueKey(record.id)`). On each rebuild the
/// rows whose key was not there before *arrive*: each one expands from zero
/// height and drops in from the top edge — pushing the rows beneath it smoothly
/// down — while fading in and glowing briefly, so a new record is easy to
/// spot. Rows that were already there keep their place, their state (hover,
/// expansion) and are not disturbed.
///
/// Only genuine arrivals animate. The first paint, a whole-page swap
/// (pagination, a different filter or tab: none of the old rows survive) and a
/// bulk change of more than [maxAnimatedArrivals] rows all update in place
/// without motion. A row list without keys never animates.
///
/// [rows] are the already-built row widgets. While it is empty [empty] (if
/// any) is shown instead; the arrival tracking survives that swap, so the
/// first record to land in an empty table animates in too.
class DashboardTableRows extends StatefulWidget {
  const DashboardTableRows({
    super.key,
    required this.rows,
    this.empty,
    this.scrollable = false,
    this.shrinkWrap = true,
    this.controller,
    this.physics,
    this.padding = EdgeInsets.zero,
    this.maxAnimatedArrivals = 6,
  });

  final List<Widget> rows;
  final Widget? empty;

  /// Space around the rows (not around [empty]).
  final EdgeInsetsGeometry padding;

  /// `false` (default): a non-scrolling column that is as tall as its rows.
  /// `true`: a [ListView], for a body that sits in a bounded-height card and
  /// scrolls its rows within it.
  final bool scrollable;

  /// Only for [scrollable]: shrink-wrap the list to its rows (a card whose
  /// height is capped) rather than filling the height it is given.
  final bool shrinkWrap;
  final ScrollController? controller;
  final ScrollPhysics? physics;

  /// More arrivals than this in one update are a reload, not news — they just
  /// appear, so a filter being cleared does not set 20 rows dancing.
  final int maxAnimatedArrivals;

  @override
  State<DashboardTableRows> createState() => _DashboardTableRowsState();
}

class _DashboardTableRowsState extends State<DashboardTableRows> {
  /// Row identities from the previous build.
  Set<Object> _known = const {};

  /// Identities that arrived with the latest update, in display order.
  List<Object> _fresh = const [];

  @override
  void initState() {
    super.initState();
    // The first paint never animates.
    _known = _identities(widget.rows).toSet();
  }

  @override
  void didUpdateWidget(covariant DashboardTableRows oldWidget) {
    super.didUpdateWidget(oldWidget);
    final current = _identities(widget.rows);
    final currentSet = current.toSet();
    final incoming = current.where((id) => !_known.contains(id)).toList();

    var animate = incoming.isNotEmpty &&
        incoming.length <= widget.maxAnimatedArrivals &&
        current.length == widget.rows.length &&
        widget.rows.every((r) => r.key != null);
    // Nothing from before is still here: a different page/filter, not news —
    // except out of an empty table, where the first arrivals are news.
    if (animate && _known.isNotEmpty && !currentSet.any(_known.contains)) {
      animate = false;
    }
    _fresh = animate ? incoming : const [];
    _known = currentSet;
  }

  /// One identity per row, in order. A repeated key is disambiguated by its
  /// occurrence so a duplicate id can never collide the element tree.
  static List<Object> _identities(List<Widget> rows) {
    final seen = <Object, int>{};
    final ids = <Object>[];
    for (var i = 0; i < rows.length; i++) {
      final key = rows[i].key;
      final base = key ?? ValueKey<String>('#row-index-$i');
      final n = seen.update(base, (v) => v + 1, ifAbsent: () => 0);
      ids.add(n == 0 ? base : (base, n));
    }
    return ids;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.rows.isEmpty) {
      return widget.empty ?? const SizedBox.shrink();
    }

    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final ids = _identities(widget.rows);
    final freshOrder = <Object, int>{
      if (!reduceMotion)
        for (var i = 0; i < _fresh.length; i++) _fresh[i]: i,
    };

    final children = <Widget>[
      for (var i = 0; i < widget.rows.length; i++)
        _RowEntrance(
          key: ValueKey<Object>(ids[i]),
          arrivalOrder: freshOrder[ids[i]],
          child: widget.rows[i],
        ),
    ];

    if (widget.scrollable) {
      return ListView(
        shrinkWrap: widget.shrinkWrap,
        controller: widget.controller,
        physics: widget.physics,
        padding: widget.padding,
        children: children,
      );
    }
    final column = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
    return widget.padding == EdgeInsets.zero
        ? column
        : Padding(padding: widget.padding, child: column);
  }
}

/// How long a new row takes to drop in, and how long its glow lingers.
const Duration _kRevealDuration = Duration(milliseconds: 520);
const Duration _kGlowDuration = Duration(milliseconds: 1500);

/// Delay between successive arrivals in the same update, so a small burst
/// stacks in one after another instead of all at once.
const Duration _kStagger = Duration(milliseconds: 90);

/// Plays the arrival animation once, when it is built with [arrivalOrder] set.
/// Its structure is the same whether it animates or not, so a row is never
/// rebuilt (and loses its state) when its entrance ends.
class _RowEntrance extends StatefulWidget {
  const _RowEntrance({super.key, required this.child, this.arrivalOrder});

  final Widget child;

  /// `null` for a row that was already there; otherwise its position among
  /// this update's arrivals (0 = first).
  final int? arrivalOrder;

  @override
  State<_RowEntrance> createState() => _RowEntranceState();
}

class _RowEntranceState extends State<_RowEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _reveal;
  late final Animation<double> _glow;

  @override
  void initState() {
    super.initState();
    final order = widget.arrivalOrder;
    final delay = _kStagger * math.min(order ?? 0, 5);
    final total = delay + _kGlowDuration;
    final totalMs = total.inMilliseconds.toDouble();
    final start = delay.inMilliseconds / totalMs;
    final revealEnd =
        (delay + _kRevealDuration).inMilliseconds / totalMs;

    _controller = AnimationController(vsync: this, duration: total);
    _reveal = CurvedAnimation(
      parent: _controller,
      curve: Interval(start, revealEnd, curve: Curves.easeOutCubic),
    );
    _glow = CurvedAnimation(
      parent: _controller,
      curve: Interval(start, 1, curve: Curves.easeOut),
    );

    if (order == null) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final glowColor = context.isDarkMode
        ? const Color(0xFFA9C6FD)
        : const Color(0xFF2563EB);
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        // The same widget types whether animating or at rest (at rest the
        // opacity is 1, the glow fully transparent and the box full height,
        // all of which paint nothing extra), so a row's own state survives
        // the end of its entrance.
        final reveal = _reveal.value;
        final glow = (1 - _glow.value) * 0.16;
        return _RevealBox(
          factor: reveal,
          child: Opacity(
            opacity: reveal.clamp(0.0, 1.0).toDouble(),
            child: DecoratedBox(
              decoration: BoxDecoration(color: glowColor.withOpacity(glow)),
              child: child,
            ),
          ),
        );
      },
    );
  }
}

/// Takes [factor] (0..1) of its child's height and shows the child sliding in
/// from above: at 0 the box is empty and the child sits fully above it; at 1
/// it is the child, untouched. Unlike a stock `SizeTransition` it hands the
/// child the exact constraints it was given, so a row lays out identically
/// whether or not it is mid-entrance.
class _RevealBox extends SingleChildRenderObjectWidget {
  const _RevealBox({required this.factor, super.child});

  final double factor;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderRevealBox(factor);

  @override
  void updateRenderObject(
      BuildContext context, covariant _RenderRevealBox renderObject) {
    renderObject.factor = factor;
  }
}

class _RenderRevealBox extends RenderBox
    with RenderObjectWithChildMixin<RenderBox> {
  _RenderRevealBox(this._factor);

  double _factor;
  double get factor => _factor;
  set factor(double value) {
    final clamped = value.clamp(0.0, 1.0).toDouble();
    if (clamped == _factor) return;
    _factor = clamped;
    markNeedsLayout();
  }

  /// Where the child's top edge sits relative to this box's: the child is
  /// bottom-aligned, so it slides down into place.
  double get _childDy => child == null ? 0 : size.height - child!.size.height;

  @override
  double computeMinIntrinsicWidth(double height) =>
      child?.getMinIntrinsicWidth(height) ?? 0;

  @override
  double computeMaxIntrinsicWidth(double height) =>
      child?.getMaxIntrinsicWidth(height) ?? 0;

  @override
  double computeMinIntrinsicHeight(double width) =>
      (child?.getMinIntrinsicHeight(width) ?? 0) * _factor;

  @override
  double computeMaxIntrinsicHeight(double width) =>
      (child?.getMaxIntrinsicHeight(width) ?? 0) * _factor;

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final c = child;
    if (c == null) return constraints.smallest;
    final s = c.getDryLayout(constraints);
    return constraints.constrain(Size(s.width, s.height * _factor));
  }

  @override
  void performLayout() {
    final c = child;
    if (c == null) {
      size = constraints.smallest;
      return;
    }
    c.layout(constraints, parentUsesSize: true);
    size = constraints.constrain(Size(c.size.width, c.size.height * _factor));
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) {
    final d = child?.getDistanceToActualBaseline(baseline);
    return d == null ? null : d + _childDy;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final c = child;
    if (c == null) return;
    if (_factor >= 1) {
      context.paintChild(c, offset);
      return;
    }
    if (size.isEmpty) return;
    context.pushClipRect(
      needsCompositing,
      offset,
      Offset.zero & size,
      (context, offset) => context.paintChild(c, offset + Offset(0, _childDy)),
    );
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final c = child;
    if (c == null) return false;
    return result.addWithPaintOffset(
      offset: Offset(0, _childDy),
      position: position,
      hitTest: (result, transformed) =>
          c.hitTest(result, position: transformed),
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    transform.translate(0.0, _childDy);
  }
}
