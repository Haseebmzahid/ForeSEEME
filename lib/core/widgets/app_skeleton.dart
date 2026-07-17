import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';

/// Shared loading-skeleton primitive.
///
/// The single source of the shimmer treatment: opaque placeholder shapes toned
/// by a left-to-right shimmer sweep on a 1.5 s loop. The base/highlight tones
/// are resolved from the ForeSeeMe design system for the **ambient brightness**,
/// so the skeleton reads correctly on both the light and dark surfaces (the old
/// fixed white-on-dark tokens were invisible on a light background).
///
/// Wrap a tree of [SkeletonBar] / [SkeletonBox] shapes in a single [AppSkeleton]
/// so the shimmer runs once for the whole placeholder. The shapes are painted at
/// full opacity; [AppSkeleton] recolours them via the shimmer gradient, so the
/// individual shapes never need to know about colours.
///
/// Accessibility: honours `prefers-reduced-motion`. When the platform requests
/// reduced motion the animation is dropped and the shapes render as a static
/// placeholder fill. The subtree is announced to screen readers as "Loading" and
/// its decorative shapes are excluded from semantics.
class AppSkeleton extends StatelessWidget {
  /// A tree of skeleton shapes ([SkeletonBar], [SkeletonBox]) to shimmer.
  final Widget child;

  const AppSkeleton({super.key, required this.child});

  /// Shimmer sweep period.
  static const Duration period = Duration(milliseconds: 1500);

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final palette = context.fsmPalette;

    // Placeholder tones from the design system: a low container tint as the
    // base, a brighter surface as the moving highlight.
    final base = palette.surfaceContainerHigh;
    final highlight = palette.surfaceBright;

    final content = Semantics(
      label: 'Loading',
      container: true,
      child: ExcludeSemantics(child: child),
    );

    // Reduced motion: no shimmer sweep — paint the base tone over the opaque
    // shapes so they read as a calm, static placeholder (a frozen shimmer frame).
    if (reduceMotion) {
      return ColorFiltered(
        colorFilter: ColorFilter.mode(base, BlendMode.srcATop),
        child: content,
      );
    }

    return Shimmer.fromColors(
      baseColor: base,
      highlightColor: highlight,
      period: period,
      child: content,
    );
  }
}

/// A single skeleton line/bar, e.g. a stand-in for a heading or a caption.
///
/// Must be placed inside an [AppSkeleton], which supplies the shimmer colour.
class SkeletonBar extends StatelessWidget {
  final double width;
  final double height;
  final double radius;

  const SkeletonBar({
    super.key,
    required this.width,
    required this.height,
    this.radius = 8,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        // Opaque fill (recoloured by the enclosing [AppSkeleton]'s shimmer).
        color: context.fsmPalette.surfaceBright,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// A rectangular/circular skeleton block, e.g. a stand-in for a chart, an avatar
/// (square [width] == [height] with a full [radius]), or a card body.
///
/// Must be placed inside an [AppSkeleton], which supplies the shimmer colour.
/// A null [width] lets the block expand to its parent's constraints.
class SkeletonBox extends StatelessWidget {
  final double? width;
  final double height;
  final double radius;

  const SkeletonBox({
    super.key,
    this.width,
    required this.height,
    this.radius = 20,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: context.fsmPalette.surfaceBright,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}
