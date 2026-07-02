import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:fyp_foreseeme/core/theme/app_design_v2.dart';
import 'package:fyp_foreseeme/core/theme/app_theme.dart';

/// Branded indeterminate loading indicator built on the ForeSeeMe mark.
///
/// Use this in place of a bare [CircularProgressIndicator] for indeterminate
/// waits. It renders the SVG brand icon centered, gives it a subtle "breathing"
/// pulse (a paired scale + opacity ease — never a spinner), and fades itself in
/// smoothly on appearance.
///
/// Design System v2:
/// * Theme-aware — shows the white mark on dark surfaces and the black mark on
///   light ones (`foreseeme-icon-white` / `foreseeme-icon-black`, the sanctioned
///   dark/light UI logos). The branding assets are used as-is; nothing is
///   recoloured or redrawn.
/// * Optional [message] beneath the mark, styled with the v2 body token.
///
/// Accessibility (§14):
/// * Honours `prefers-reduced-motion`. When the platform requests reduced motion
///   the pulse and fade are dropped and the mark renders statically.
/// * The subtree is announced to screen readers as "Loading" (plus [message]);
///   the decorative logo/text are excluded from semantics so nothing is read
///   twice.
///
/// This is a pure presentation primitive — no providers, repositories, or
/// business logic. It only reads the ambient [Theme] and [MediaQuery].
class BrandLoading extends StatefulWidget {
  /// Optional caption shown beneath the mark, e.g. "Loading your risk…".
  final String? message;

  /// Rendered size (width & height) of the logo mark, in logical pixels.
  final double size;

  const BrandLoading({super.key, this.message, this.size = 72});

  @override
  State<BrandLoading> createState() => _BrandLoadingState();
}

class _BrandLoadingState extends State<BrandLoading>
    with SingleTickerProviderStateMixin {
  /// Breathing pulse — a slow, calm loop (well under the 3 Hz flash guard).
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Start/stop the pulse to match the current reduced-motion preference.
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      _controller.stop();
      _controller.value = 1.0; // resting frame: full scale / full opacity
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final logo = SvgPicture.asset(
      isDark
          ? 'assets/branding/logo/foreseeme-icon-white.svg'
          : 'assets/branding/logo/foreseeme-icon-black.svg',
      width: widget.size,
      height: widget.size,
      fit: BoxFit.contain,
    );

    // Breathing: pair a gentle scale with an opacity ease so the mark reads as
    // "alive" without spinning. Held on its resting frame under reduced motion.
    final Widget pulsing = reduceMotion
        ? logo
        : AnimatedBuilder(
            animation: _controller,
            child: logo,
            builder: (context, child) {
              final t = Curves.easeInOut.transform(_controller.value);
              return Opacity(
                opacity: 0.55 + 0.45 * t,
                child: Transform.scale(scale: 0.94 + 0.06 * t, child: child),
              );
            },
          );

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        pulsing,
        if (widget.message != null) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            widget.message!,
            textAlign: TextAlign.center,
            style: AppTextStylesV2.body,
          ),
        ],
      ],
    );

    // Smooth fade-in on appearance (skipped under reduced motion).
    final faded = TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: reduceMotion ? 1.0 : 0.0, end: 1.0),
      duration:
          reduceMotion ? Duration.zero : const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      builder: (context, value, child) =>
          Opacity(opacity: value, child: child),
      child: content,
    );

    return Center(
      child: Semantics(
        label: widget.message == null
            ? 'Loading'
            : 'Loading. ${widget.message}',
        liveRegion: true,
        container: true,
        child: ExcludeSemantics(child: faded),
      ),
    );
  }
}
