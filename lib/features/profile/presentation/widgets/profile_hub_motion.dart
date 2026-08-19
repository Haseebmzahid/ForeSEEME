import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:fyp_foreseeme/core/widgets/app_motion.dart';

/// A looping ambient animation, the Flutter counterpart of a CSS
/// `animation: name Xs ease-in-out infinite` declaration.
///
/// The Profile Hub prototype runs nine such loops at once (orbit rings, float,
/// core glow, two pulses, the equalizer, the sweep and the operator breathe).
/// This is the single primitive all of them use, so their lifecycle is handled
/// in one place rather than nine:
///
///  * **Reduced motion** — when the platform asks for less motion no controller
///    is created at all, and the builder is called once at [restT]. Each loop
///    picks a rest phase that reads as a deliberate still frame rather than an
///    arbitrary freeze.
///  * **Off-screen** — [active] stops the ticker without disposing it, so a loop
///    that has scrolled out of view costs nothing and resumes in place.
///  * **Repaint isolation** — the subtree is wrapped in a [RepaintBoundary], so
///    a loop repainting at 60fps never dirties the scrolling content around it.
///
/// [builder] receives `t` in `0..1`, the loop's normalised phase.
class AmbientLoop extends StatefulWidget {
  const AmbientLoop({
    super.key,
    required this.period,
    required this.builder,
    this.active = true,
    this.restT = 0,
    this.child,
  });

  /// One full cycle. Taken from the prototype's own `animation` duration.
  final Duration period;

  /// Called with the normalised phase `t` in `0..1`.
  final Widget Function(BuildContext context, double t, Widget? child) builder;

  /// False pauses the loop (e.g. the hero has scrolled out of view).
  final bool active;

  /// The phase held under reduced motion.
  final double restT;

  /// Passed straight through to [builder]; use it for the subtree that does not
  /// depend on `t` so it is not rebuilt every frame.
  final Widget? child;

  @override
  State<AmbientLoop> createState() => _AmbientLoopState();
}

class _AmbientLoopState extends State<AmbientLoop>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant AmbientLoop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.period != widget.period) {
      _controller?.duration = widget.period;
    }
    _sync();
  }

  /// Creates, starts, stops or tears down the ticker to match the current
  /// reduced-motion setting and [AmbientLoop.active].
  void _sync() {
    final reduce = AppMotion.reduceMotion(context);

    if (reduce) {
      // Nothing to animate: drop the ticker entirely rather than leave one
      // parked, so reduced motion costs nothing at all.
      if (_controller != null) {
        _controller!.dispose();
        _controller = null;
        // Rebuild so the static rest frame replaces the animated subtree.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() {});
        });
      }
      return;
    }

    _controller ??= AnimationController(vsync: this, duration: widget.period);

    if (widget.active) {
      if (!_controller!.isAnimating) _controller!.repeat();
    } else {
      if (_controller!.isAnimating) _controller!.stop();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return RepaintBoundary(
        child: widget.builder(context, widget.restT, widget.child),
      );
    }
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: controller,
        child: widget.child,
        builder: (context, child) =>
            widget.builder(context, controller.value, child),
      ),
    );
  }
}

/// A CSS `0% / 50% / 100%` keyframe pair evaluated with `ease-in-out` easing —
/// the shape used by every ping-pong loop in the prototype (`fsm-float`,
/// `fsm-pulse`, `fsm-eq`, `fsm-breathe`, `fsm-coreglow`).
///
/// Returns `0` at `t = 0`, `1` at `t = 0.5` and `0` again at `t = 1`, eased at
/// both ends. A raised cosine matches CSS's `ease-in-out` between two keyframes
/// closely enough that the two are indistinguishable in motion, and it is
/// continuous across the loop seam — which a piecewise `Curves.easeInOut` is
/// not.
double pingPong(double t) => 0.5 - 0.5 * math.cos(2 * math.pi * t);

/// Linear interpolation driven by [pingPong].
double pingPongBetween(double t, double from, double to) =>
    from + (to - from) * pingPong(t);
