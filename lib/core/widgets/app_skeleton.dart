import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

/// Shared loading-skeleton primitive for Design System v2 (Sprint 3) surfaces.
///
/// This is the single source of the shimmer treatment described in the design
/// system (§12 "Skeleton · Empty · Error"): opaque placeholder shapes toned by a
/// left-to-right shimmer from `white @ .05` to `white @ .13`, on a 1.5 s loop.
///
/// Wrap a tree of [SkeletonBar] / [SkeletonBox] shapes in a single [AppSkeleton]
/// so the shimmer runs once for the whole placeholder. The shapes are painted at
/// full opacity; [AppSkeleton] recolours them via the shimmer gradient, so the
/// individual shapes never need to know about colours.
///
/// Accessibility (§14): honours `prefers-reduced-motion`. When the platform
/// requests reduced motion the animation is dropped and the shapes render as a
/// static placeholder fill. The subtree is announced to screen readers as
/// "Loading" and its decorative shapes are excluded from semantics.
class AppSkeleton extends StatelessWidget {
  /// A tree of skeleton shapes ([SkeletonBar], [SkeletonBox]) to shimmer.
  final Widget child;

  const AppSkeleton({super.key, required this.child});

  /// Shimmer base — white @ ~.05 (design token).
  static const Color base = Color(0x0DFFFFFF);

  /// Shimmer highlight — white @ ~.13 (design token).
  static const Color highlight = Color(0x21FFFFFF);

  /// Shimmer sweep period.
  static const Duration period = Duration(milliseconds: 1500);

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    final content = Semantics(
      label: 'Loading',
      container: true,
      child: ExcludeSemantics(child: child),
    );

    // Reduced motion: no shimmer sweep — paint the base tone over the opaque
    // shapes so they read as a calm, static placeholder (a frozen shimmer frame).
    if (reduceMotion) {
      return ColorFiltered(
        colorFilter: const ColorFilter.mode(base, BlendMode.srcATop),
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
        color: Colors.white,
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}
