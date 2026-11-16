import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../../core/theme/a11y.dart';
import '../../../../core/theme/foreseeme_surface.dart';
import '../../../../core/theme/foreseeme_theme.dart';
import '../../../../core/theme/foreseeme_tokens.dart';

/// Feature-local optics; fill, edges and shadows remain design-system owned.
/// Blur is opt-in so scrolling cards do not each filter the backdrop.
class DiseaseGlass extends StatelessWidget {
  const DiseaseGlass({
    super.key,
    required this.child,
    this.accent,
    this.blur = false,
    this.radius = ForeSeeMeRadius.xl,
    this.padding = const EdgeInsets.all(ForeSeeMeSpacing.lg),
  });
  final Widget child;
  final Color? accent;
  final bool blur;
  final double radius;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) {
    final p = context.fsmPalette;
    final opaque = A11y.reduceTransparency(context);
    final tint = accent ?? p.secondary;
    Widget panel = DecoratedBox(
      decoration: ForeSeeMeSurface.card(
        context,
        radius: radius,
        shadow: const [],
      ),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          gradient: opaque
              ? null
              : LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    tint.withValues(alpha: p.isDark ? .13 : .07),
                    p.surfaceBright.withValues(alpha: .03),
                    tint.withValues(alpha: .015),
                  ],
                ),
        ),
        child: child,
      ),
    );
    if (blur && !opaque) {
      panel = BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: panel,
      );
    }
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: context.fsmColors.shadows.medium,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: panel,
      ),
    );
  }
}

/// Stationary atmospheric light, independent of model data and scroll position.
class DiseaseAtmosphere extends StatelessWidget {
  const DiseaseAtmosphere({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final p = context.fsmPalette;
    return DecoratedBox(
      decoration: BoxDecoration(gradient: context.fsmColors.gradients.surface),
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(.9, -.85),
                    radius: .9,
                    colors: [
                      p.secondary.withValues(alpha: p.isDark ? .16 : .08),
                      p.secondary.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(-1, .25),
                    radius: 1.1,
                    colors: [
                      p.tertiary.withValues(alpha: p.isDark ? .12 : .055),
                      p.tertiary.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}
