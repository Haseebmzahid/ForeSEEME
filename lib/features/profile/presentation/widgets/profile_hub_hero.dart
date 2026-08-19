import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:fyp_foreseeme/core/theme/a11y.dart';

import 'profile_hub_motion.dart';
import 'profile_hub_style.dart';

/// The Profile Hub's hero: three orbiting rings, a completeness gauge and the
/// user's photo in a lit glass core, all floating as one body.
///
/// Transcribed from the prototype's hero block. Geometry, periods and easing are
/// the prototype's; nothing here is approximated for convenience.
///
/// Presentation only — it takes values and renders them. It reads no provider
/// and owns no state beyond its own tickers.
class ProfileHubHero extends StatelessWidget {
  const ProfileHubHero({
    super.key,
    required this.percent,
    required this.photoUrl,
    required this.initial,
    required this.isReady,
    this.animate = true,
  });

  /// 0–100 completeness. Drives the gauge arc and the chip readout.
  final int percent;

  /// The signed-in user's photo, or null.
  final String? photoUrl;

  /// Fallback glyph drawn in the core when there is no photo.
  final String initial;

  /// Whether the profile is on file — drives the chip's `Verified` line.
  final bool isReady;

  /// False once the hero has scrolled out of view, which parks every loop.
  final bool animate;

  /// The prototype's hero block height.
  static const double height = 268;

  @override
  Widget build(BuildContext context) {
    final theme = ProfileHubTheme.of(context);

    return SizedBox(
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // The floating body: `animation: fsm-float 7s ease-in-out infinite`,
          // translateY 0 → -9px → 0.
          Positioned.fill(
            child: AmbientLoop(
              period: const Duration(seconds: 7),
              active: animate,
              restT: 0.25, // mid-drift, so the still frame is not a hard edge
              builder: (context, t, child) => Transform.translate(
                offset: Offset(0, -pingPongBetween(t, 0, 9)),
                child: child,
              ),
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  // `margin-top: 6px` on the 230px orbit box.
                  padding: const EdgeInsets.only(top: 6),
                  child: _Orbit(
                    percent: percent,
                    photoUrl: photoUrl,
                    initial: initial,
                    animate: animate,
                  ),
                ),
              ),
            ),
          ),

          // `left: 14px; top: 42px` — SYSTEM LIVE.
          Positioned(left: 14, top: 42, child: _SystemLiveChip(animate: animate)),

          // `right: 14px; top: 96px` — the profile state chip.
          Positioned(
            right: 14,
            top: 96,
            child: _ProfileChip(
              percent: percent,
              isReady: isReady,
              theme: theme,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Orbit ────────────────────────────────────────────────────────────────────

/// The 230×230 orbit box: three tilted rings, the core halo, the gauge and the
/// core itself, stacked centre-aligned exactly as the prototype's flex box does.
class _Orbit extends StatelessWidget {
  const _Orbit({
    required this.percent,
    required this.photoUrl,
    required this.initial,
    required this.animate,
  });

  final int percent;
  final String? photoUrl;
  final String initial;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final theme = ProfileHubTheme.of(context);

    return SizedBox(
      width: 230,
      height: 230,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // ringC is the widest (262px) and slowest, so it sits furthest back.
          _OrbitRing(
            size: 262,
            period: const Duration(seconds: 46),
            tiltX: 82,
            tiltY: -12,
            clockwise: true,
            borderColor: theme.isDark
                ? const Color(0x12FFFFFF) // rgba(255,255,255,0.07)
                : theme.line,
            dotSize: 4,
            dotColor: theme.accent.withValues(alpha: 0.7),
            animate: animate,
          ),
          _OrbitRing(
            size: 226,
            period: const Duration(seconds: 26),
            tiltX: 74,
            clockwise: true,
            borderColor: theme.accent.withValues(alpha: 0.30),
            dotSize: 6,
            dotColor: theme.accent,
            dotGlow: theme.accent,
            animate: animate,
          ),
          _OrbitRing(
            size: 182,
            period: const Duration(seconds: 34),
            tiltX: 64,
            tiltY: 18,
            // `rotateZ(360deg) → rotateZ(0deg)`: this one runs backwards.
            clockwise: false,
            dashed: true,
            borderColor: theme.isDark
                ? const Color(0x29FFFFFF) // rgba(255,255,255,0.16)
                : theme.track2,
            dotSize: 5,
            dotColor: theme.isDark
                ? const Color(0xBFFFFFFF) // rgba(255,255,255,0.75)
                : theme.txt.withValues(alpha: 0.55),
            animate: animate,
          ),

          // `fsm-coreglow 5.5s`: opacity .55 → .9, scale 1 → 1.06, blur(2px).
          AmbientLoop(
            period: const Duration(milliseconds: 5500),
            active: animate,
            restT: 0.5,
            builder: (context, t, child) => Opacity(
              opacity: pingPongBetween(t, 0.55, 0.9),
              child: Transform.scale(
                scale: pingPongBetween(t, 1.0, 1.06),
                child: child,
              ),
            ),
            child: IgnorePointer(
              child: Container(
                width: 190,
                height: 190,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: theme.bloomFill,
                ),
              ),
            ),
          ),

          // The completeness gauge — an SVG in the prototype, a painter here.
          RepaintBoundary(
            child: CustomPaint(
              size: const Size(168, 168),
              painter: _GaugePainter(
                percent: percent,
                track: theme.track,
                accent: theme.accent,
              ),
            ),
          ),

          _Core(photoUrl: photoUrl, initial: initial, theme: theme),
        ],
      ),
    );
  }
}

/// One tilted, slowly spinning ring carrying a single bead.
///
/// The prototype puts `perspective: 900px` on the hero and gives each ring a
/// `rotateX(...) rotateY(...) rotateZ(t)` transform under `preserve-3d`. That is
/// reproduced literally: the same perspective entry, the same rotation order
/// (CSS composes left-to-right, which is the order `Matrix4`'s `rotate*` methods
/// post-multiply in), and the bead carries the inverse `rotateX` so it stays
/// face-on to the viewer as the prototype's does.
class _OrbitRing extends StatelessWidget {
  const _OrbitRing({
    required this.size,
    required this.period,
    required this.tiltX,
    this.tiltY = 0,
    required this.clockwise,
    required this.borderColor,
    required this.dotSize,
    required this.dotColor,
    this.dotGlow,
    this.dashed = false,
    required this.animate,
  });

  final double size;
  final Duration period;
  final double tiltX;
  final double tiltY;
  final bool clockwise;
  final Color borderColor;
  final double dotSize;
  final Color dotColor;
  final Color? dotGlow;
  final bool dashed;
  final bool animate;

  static double _rad(double degrees) => degrees * math.pi / 180;

  @override
  Widget build(BuildContext context) {
    final ring = IgnorePointer(
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: dashed
                  ? CustomPaint(
                      painter: _DashedCirclePainter(color: borderColor),
                    )
                  : DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: borderColor),
                      ),
                    ),
            ),
            // `top: -(d/2); left: 50%; margin-left: -(d/2)` — centred on the
            // ring's top edge, then counter-tilted to face the viewer.
            Positioned(
              top: -dotSize / 2,
              left: size / 2 - dotSize / 2,
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()..rotateX(_rad(-tiltX)),
                child: Container(
                  width: dotSize,
                  height: dotSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: dotColor,
                    boxShadow: dotGlow == null
                        ? null
                        : [BoxShadow(color: dotGlow!, blurRadius: 10)],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return AmbientLoop(
      period: period,
      active: animate,
      builder: (context, t, child) {
        final spin = (clockwise ? t : 1 - t) * 2 * math.pi;
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            // `perspective: 900px` on the hero.
            ..setEntry(3, 2, 1 / 900)
            ..rotateX(_rad(tiltX))
            ..rotateY(_rad(tiltY))
            ..rotateZ(spin),
          child: child,
        );
      },
      child: ring,
    );
  }
}

/// The prototype's `border: 1px dashed`. Chrome renders a dashed ring; Flutter
/// has no dashed border, so the ring is stroked by hand at a dash rhythm that
/// matches Chrome's for a circle this size.
class _DashedCirclePainter extends CustomPainter {
  const _DashedCirclePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = color;

    final path = Path()
      ..addOval(
        Rect.fromLTWH(0.5, 0.5, size.width - 1, size.height - 1),
      );

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = math.min(distance + 3.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + 3.0;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedCirclePainter old) => old.color != color;
}

/// The completeness arc: `<circle r="76" stroke-width="3" stroke-linecap="round"
/// stroke-dasharray="C·p/100 C">` under `transform: rotate(-90deg)`.
class _GaugePainter extends CustomPainter {
  const _GaugePainter({
    required this.percent,
    required this.track,
    required this.accent,
  });

  final int percent;
  final Color track;
  final Color accent;

  static const double _radius = 76;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    canvas.drawCircle(
      center,
      _radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = track,
    );

    final fraction = (percent / 100).clamp(0.0, 1.0);
    if (fraction <= 0) return;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: _radius),
      -math.pi / 2, // the SVG's rotate(-90deg)
      fraction * 2 * math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = accent,
    );
  }

  @override
  bool shouldRepaint(covariant _GaugePainter old) =>
      old.percent != percent || old.track != track || old.accent != accent;
}

/// The 132px glass core holding the user's photo.
///
/// The prototype's four-part `box-shadow` is split the way CSS resolves it:
/// the two outer shadows become [BoxShadow]s, and the two `inset` shadows —
/// which Flutter's box model has no equivalent for — become clipped gradient
/// overlays inside the circle. The prototype already uses that technique itself
/// for its own extra inner shade, so this follows its lead rather than
/// inventing one.
class _Core extends StatelessWidget {
  const _Core({
    required this.photoUrl,
    required this.initial,
    required this.theme,
  });

  final String? photoUrl;
  final String initial;
  final ProfileHubTheme theme;

  @override
  Widget build(BuildContext context) {
    final url = photoUrl;

    return Container(
      width: 132,
      height: 132,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: theme.coreFill,
        border: Border.all(
          color: theme.isDark
              ? const Color(0x24FFFFFF) // rgba(255,255,255,0.14)
              : const Color(0x33FFFFFF),
        ),
        boxShadow: [
          // `0 22px 48px rgba(0,0,0,0.55)`
          BoxShadow(
            color: theme.shadowColor.withValues(
              alpha: theme.isDark ? 0.55 : 0.22,
            ),
            blurRadius: 48,
            offset: const Offset(0, 22),
          ),
          // `0 0 40px var(--glow)`
          BoxShadow(color: theme.glow, blurRadius: 40),
        ],
      ),
      child: ClipOval(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // `top: 6px; left: 6px; width: 120px; height: 120px`.
            Center(
              child: SizedBox(
                width: 120,
                height: 120,
                child: ClipOval(
                  child: url == null || url.isEmpty
                      ? _Initial(initial: initial, theme: theme)
                      : Image.network(
                          url,
                          fit: BoxFit.cover,
                          // A photo that will not load must not leave a hole in
                          // the hero, so the same glyph the no-photo case uses
                          // stands in.
                          errorBuilder: (context, _, _) =>
                              _Initial(initial: initial, theme: theme),
                          loadingBuilder: (context, child, progress) =>
                              progress == null
                              ? child
                              : _Initial(initial: initial, theme: theme),
                        ),
                ),
              ),
            ),

            // `inset 0 2px 14px rgba(255,255,255,0.16)` — the lit upper lip.
            _CoreOverlay(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withValues(alpha: 0.16),
                  Colors.white.withValues(alpha: 0),
                ],
                stops: const [0.0, 0.22],
              ),
            ),

            // `inset 0 -18px 30px rgba(0,0,0,0.5)` plus the prototype's own
            // second inner shade `inset 0 -16px 26px rgba(0,0,0,0.35)`.
            _CoreOverlay(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.62),
                  Colors.black.withValues(alpha: 0),
                ],
                stops: const [0.0, 0.42],
              ),
            ),

            // The raked specular band, verbatim:
            // `linear-gradient(115deg, transparent 40%, white .16 50%,
            //  transparent 60%)`.
            _CoreOverlay(
              gradient: LinearGradient(
                begin: const Alignment(-0.9, -1.0),
                end: const Alignment(0.9, 1.0),
                colors: [
                  Colors.white.withValues(alpha: 0),
                  Colors.white.withValues(alpha: 0.16),
                  Colors.white.withValues(alpha: 0),
                ],
                stops: const [0.4, 0.5, 0.6],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CoreOverlay extends StatelessWidget {
  const _CoreOverlay({required this.gradient});

  final Gradient gradient;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: DecoratedBox(
      decoration: BoxDecoration(shape: BoxShape.circle, gradient: gradient),
    ),
  );
}

/// The no-photo fallback: the user's initial, in the core's own ink.
class _Initial extends StatelessWidget {
  const _Initial({required this.initial, required this.theme});

  final String initial;
  final ProfileHubTheme theme;

  @override
  Widget build(BuildContext context) => Center(
    // The glyph is decoration: the name it stands for is announced by the
    // heading directly beneath the hero.
    child: ExcludeSemantics(
      child: Text(
      initial,
      style: hubSans(
        context,
        size: 34,
        em: -0.02,
        color: theme.coreTxt,
        weight: FontWeight.w600,
        height: 1,
      ),
      ),
    ),
  );
}

// ── Floating chips ───────────────────────────────────────────────────────────

/// `SYSTEM LIVE` — the prototype's liveness pill, with its pulsing bead.
class _SystemLiveChip extends StatelessWidget {
  const _SystemLiveChip({required this.animate});

  final bool animate;

  @override
  Widget build(BuildContext context) {
    final theme = ProfileHubTheme.of(context);

    // The two hero chips are absolutely positioned at opposite edges, as the
    // prototype places them. At large text scales they would grow into each
    // other, so each is capped at a share of the width that leaves the pair
    // clear (0.48 + 0.42 of the width, plus the two 14px insets).
    final maxWidth = MediaQuery.sizeOf(context).width * 0.48;

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: _GlassChip(
      radius: 999,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      shadowBlur: 24,
      shadowOffsetY: 12,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // `fsm-pulse 2.4s`: opacity .35 → 1, scale 1 → 1.5.
          AmbientLoop(
            period: const Duration(milliseconds: 2400),
            active: animate,
            restT: 0.5,
            builder: (context, t, child) => Opacity(
              opacity: pingPongBetween(t, 0.35, 1.0),
              child: Transform.scale(
                scale: pingPongBetween(t, 1.0, 1.5),
                child: child,
              ),
            ),
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.accent,
              ),
            ),
          ),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              'SYSTEM LIVE',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: hubMono(context, size: 10, em: 0.14, color: theme.txt),
            ),
          ),
        ],
      ),
      ),
    );
  }
}

/// The `PROFILE / Verified / n% READY` chip.
class _ProfileChip extends StatelessWidget {
  const _ProfileChip({
    required this.percent,
    required this.isReady,
    required this.theme,
  });

  final int percent;
  final bool isReady;
  final ProfileHubTheme theme;

  @override
  Widget build(BuildContext context) {
    // The prototype's static "Verified" is bound to the app's own onboarding
    // signal — whether a health profile is on file — which is what the router
    // already treats as the completed-setup gate.
    final state = isReady ? 'Verified' : 'Setup';

    return Semantics(
      container: true,
      label: 'Profile $state, $percent percent ready',
      child: ExcludeSemantics(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.42,
          ),
          child: _GlassChip(
          radius: 12,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          shadowBlur: 26,
          shadowOffsetY: 14,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'PROFILE',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: hubMono(context, size: 9, em: 0.16, color: theme.txt2),
              ),
              Text(
                state,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: hubSans(
                  context,
                  size: 13,
                  em: -0.01,
                  color: theme.txt,
                  weight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 5),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: theme.accent,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      '$percent% READY',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: hubMono(
                        context,
                        size: 10,
                        em: 0.1,
                        color: theme.accent,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          ),
        ),
      ),
    );
  }
}

/// The blurred `--glass2` pill/plate both hero chips are built from.
class _GlassChip extends StatelessWidget {
  const _GlassChip({
    required this.child,
    required this.radius,
    required this.padding,
    required this.shadowBlur,
    required this.shadowOffsetY,
  });

  final Widget child;
  final double radius;
  final EdgeInsets padding;
  final double shadowBlur;
  final double shadowOffsetY;

  @override
  Widget build(BuildContext context) {
    final theme = ProfileHubTheme.of(context);
    final opaque = A11y.reduceTransparency(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: theme.shadowColor.withValues(
              alpha: theme.isDark ? 0.45 : 0.16,
            ),
            blurRadius: shadowBlur,
            offset: Offset(0, shadowOffsetY),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: hubBlur(context, 14),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              // Under reduced transparency the plate goes solid, so the mono
              // labels never rest on an unpredictable translucent bed.
              color: opaque ? theme.bg2 : theme.glass2,
              border: Border.all(
                color: opaque ? theme.txt2 : theme.line,
              ),
            ),
            child: Stack(
              children: [
                // `inset 0 1px 0 var(--hi)` — the lit lip, drawn at the plate's
                // own top edge rather than inside its padding.
                if (!opaque)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: 1,
                    child: ColoredBox(color: theme.hi),
                  ),
                Padding(padding: padding, child: child),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
