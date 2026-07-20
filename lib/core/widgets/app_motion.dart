import 'package:flutter/material.dart';

/// The app's shared **motion language** (Design System v2).
///
/// A single source of truth for durations, the house curve, and the reusable
/// motion primitives ([PressableScale], [AppReveal]) plus the state- and
/// route-transition helpers. It mirrors the feel already established by
/// `AppButton` (an easeOutCubic scale press), rather than inventing a new one.
///
/// Every primitive honours `prefers-reduced-motion`
/// (`MediaQuery.disableAnimations`): motion collapses to an instant, non-animated
/// result so the UI stays fully usable and nothing is lost. Motion is kept
/// subtle by design — small offsets, short durations, no bounce.
class AppMotion {
  AppMotion._();

  /// Press / quick feedback.
  static const Duration fast = Duration(milliseconds: 120);

  /// Standard state / reveal transition.
  static const Duration medium = Duration(milliseconds: 240);

  /// Page / route transition.
  static const Duration page = Duration(milliseconds: 320);

  /// House curve — matches the existing button feel.
  static const Curve curve = Curves.easeOutCubic;

  /// Whether the platform asked us to minimise motion.
  static bool reduceMotion(BuildContext context) =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  /// Cross-fade between async states (loading ↔ data ↔ empty ↔ error ↔ offline).
  /// Collapses to an instant swap under reduced motion.
  static Widget stateSwitcher(BuildContext context, Widget child) {
    return AnimatedSwitcher(
      duration: reduceMotion(context) ? Duration.zero : medium,
      switchInCurve: curve,
      switchOutCurve: curve,
      child: child,
    );
  }

  /// Reduced-motion-aware route transition — a soft fade with a whisper of
  /// scale. Wired into the app router's Sprint-3/4 pushed routes.
  static Widget pageTransition(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (reduceMotion(context)) return child;
    final curved = CurvedAnimation(parent: animation, curve: curve);
    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.985, end: 1.0).animate(curved),
        child: child,
      ),
    );
  }

  /// A soft upward slide + fade for a surface that **swaps** based on
  /// selection (e.g. the map's tapped-city sheet) via
  /// [AnimatedSwitcher.transitionBuilder] — the same house feel as
  /// [pageTransition], reused instead of a one-off inline recipe. Pair with
  /// an [AnimatedSwitcher.duration] of [medium] (or `Duration.zero` under
  /// reduced motion — see [reduceMotion] — mirroring [stateSwitcher]).
  static Widget sheetTransition(Widget child, Animation<double> animation) {
    final curved = CurvedAnimation(parent: animation, curve: curve);
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 0.15),
        end: Offset.zero,
      ).animate(curved),
      child: FadeTransition(opacity: curved, child: child),
    );
  }
}

/// A tap target that scales down slightly while pressed — the premium
/// "card / button press" feel, mirroring [AppButton]'s frame.
///
/// Pass [onTap] to own the tap, or leave it null and let an inner `InkWell`
/// handle the tap + ripple while this only supplies the scale. Honours reduced
/// motion (no scale, tap still fires).
class PressableScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double pressedScale;

  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.pressedScale = 0.97,
  });

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _pressed = false;

  void _set(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final reduce = AppMotion.reduceMotion(context);
    final scale = (_pressed && !reduce) ? widget.pressedScale : 1.0;

    return GestureDetector(
      behavior: HitTestBehavior.deferToChild,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: scale,
        duration: reduce ? Duration.zero : AppMotion.fast,
        curve: AppMotion.curve,
        child: widget.child,
      ),
    );
  }
}

/// A one-shot entrance: a gentle fade + upward drift, staggered by [delayMs].
///
/// Timer-free (a single [TweenAnimationBuilder] with an [Interval] does the
/// stagger), so it never leaves pending timers in tests and the child stays in
/// the tree throughout (only its opacity animates — always findable). Honours
/// reduced motion (renders the child immediately, unanimated).
class AppReveal extends StatelessWidget {
  final Widget child;
  final int delayMs;
  final double offsetY;

  const AppReveal({
    super.key,
    required this.child,
    this.delayMs = 0,
    this.offsetY = 12,
  });

  @override
  Widget build(BuildContext context) {
    if (AppMotion.reduceMotion(context)) return child;
    const base = 380;
    final total = delayMs + base;
    final start = (delayMs / total).clamp(0.0, 0.9);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: Duration(milliseconds: total),
      curve: Interval(start, 1.0, curve: AppMotion.curve),
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * offsetY),
          child: child,
        ),
      ),
      child: child,
    );
  }
}
