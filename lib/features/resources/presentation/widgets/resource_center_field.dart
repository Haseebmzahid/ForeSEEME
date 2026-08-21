import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:fyp_foreseeme/core/widgets/app_motion.dart';
import 'package:fyp_foreseeme/features/resources/presentation/widgets/resource_center_style.dart';

/// The Resource Center's **knowledge field** — the prototype's 296px hero, and
/// the one piece of the screen that is genuinely 2.5D.
///
/// The prototype builds it out of a `perspective:900px` stage holding three
/// CSS-transformed orbit rings (`spinA`/`spinB`/`spinC`), a gradient sphere
/// with a sweeping specular (`sheen`), a breathing halo (`breathe`), a contact
/// shadow, and eight drifting particles (`drift`) — the whole group rising and
/// falling on `float`. All of it is reproduced here with Flutter's own
/// primitives: a real [Matrix4] perspective + `rotateX/Y/Z` per ring, gradients
/// for every glow, and a [CustomPainter] for the dashed ring.
///
/// Motion is driven by a **single** [Ticker] publishing elapsed seconds, rather
/// than seven [AnimationController]s — each animation reads the phase it needs
/// from that one clock, which is both cheaper and keeps the periods in the
/// prototype's own units (12s float, 52s outer ring, and so on).
///
/// Under `MediaQuery.disableAnimations` the ticker is never started and the
/// field renders its `t = 0` frame: the composition, depth and lighting are all
/// still there, nothing moves.

/// Elapsed seconds since the field was mounted. One clock, many phases.
class _FieldClock extends ChangeNotifier {
  _FieldClock(TickerProvider vsync) {
    _ticker = vsync.createTicker(_onTick);
  }

  late final Ticker _ticker;
  double _seconds = 0;

  double get seconds => _seconds;

  void start() {
    if (!_ticker.isActive) _ticker.start();
  }

  void _onTick(Duration elapsed) {
    _seconds = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }
}

/// A `0 → 1` sawtooth over [period] seconds, the shape every `linear infinite`
/// keyframe in the prototype uses.
double _phase(double t, double period, [double delay = 0]) {
  final v = (t - delay) / period;
  return v - v.floorToDouble();
}

/// The prototype's `ease-in-out` `0 → 1 → 0` shuttle over [period] seconds,
/// used by `float` and `breathe`.
double _shuttle(double t, double period) =>
    (1 - math.cos(_phase(t, period) * 2 * math.pi)) / 2;

/// The hero field object.
class ResourceField extends StatefulWidget {
  const ResourceField({
    super.key,
    required this.theme,
    required this.fieldLabel,
    required this.contextLine,
    required this.pad,
  });

  final ResourceCenterTheme theme;

  /// The right-hand channel caption — which topic the catalogue is currently
  /// weighted toward.
  final String fieldLabel;

  /// The pill under the object: the live environmental read.
  final String contextLine;

  final double pad;

  /// `height:296px` — the prototype's hero box.
  static const double height = 296;

  @override
  State<ResourceField> createState() => _ResourceFieldState();
}

class _ResourceFieldState extends State<ResourceField>
    with SingleTickerProviderStateMixin {
  late final _FieldClock _clock = _FieldClock(this);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduced motion keeps the composition and drops the movement — the ticker
    // is simply never started, so the field paints its t = 0 frame forever.
    if (!_started && !AppMotion.reduceMotion(context)) {
      _started = true;
      _clock.start();
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;

    return SizedBox(
      height: ResourceField.height,
      child: AnimatedBuilder(
        animation: _clock,
        builder: (context, _) {
          final t = _clock.seconds;
          return LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              const h = ResourceField.height;

              return Stack(
                clipBehavior: Clip.none,
                children: [
                  // `width:330;height:330;left:50%;top:50%;margin:-165 0 0 -165`
                  // with `animation: breathe 9s`. The CSS `filter:blur(16px)` is
                  // folded into the gradient's own falloff.
                  Positioned(
                    left: w / 2 - 165,
                    top: h * 0.5 - 165,
                    width: 330,
                    height: 330,
                    child: _Breathing(
                      t: t,
                      period: 9,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: theme.fieldHalo,
                        ),
                      ),
                    ),
                  ),

                  // The `float 12s` group: everything with depth rides it.
                  Positioned.fill(
                    child: Transform.translate(
                      // `0%,100% { translate3d(0,-7px,0) } 50% { 0,9px }`
                      offset: Offset(0, -7 + 16 * _shuttle(t, 12)),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          // The three orbit rings, painted as their FAR
                          // halves only: everything behind the sphere.
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _OrbitPainter(
                                rings: _orbits(theme, t, w, h),
                                front: false,
                              ),
                            ),
                          ),

                          // Contact shadow — `top:78%`, 150×26, blurred.
                          Positioned(
                            left: w / 2 - 75,
                            top: h * 0.78 - 13,
                            width: 150,
                            height: 26,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: theme.bloom(
                                  Colors.black.withValues(
                                    alpha: theme.isDark ? 0.33 : 0.12,
                                  ),
                                  stop: 0.85,
                                ),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),

                          // The sphere — `top:52%`, 142px.
                          Positioned(
                            left: w / 2 - 71,
                            top: h * 0.52 - 71,
                            width: 142,
                            height: 142,
                            child: _FieldSphere(theme: theme, t: t),
                          ),

                          // The same rings' NEAR halves, over the sphere —
                          // the depth cue CSS gets from `preserve-3d` and
                          // Flutter has to be told about explicitly.
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _OrbitPainter(
                                rings: _orbits(theme, t, w, h),
                                front: true,
                              ),
                            ),
                          ),

                          // The faint accent ring around it — 196px, opacity .16.
                          Positioned(
                            left: w / 2 - 98,
                            top: h * 0.52 - 98,
                            width: 196,
                            height: 196,
                            child: Opacity(
                              opacity: 0.16,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: theme.accent),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Eight `drift 14s` particles.
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          for (final p in _particles)
                            _Particle(t: t, spec: p, box: Size(w, h), theme: theme),
                        ],
                      ),
                    ),
                  ),

                  // `FIELD · LIVE`, top-left.
                  Positioned(
                    left: widget.pad,
                    top: 22,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'FIELD · LIVE',
                          style: rcMono(
                            context,
                            size: 8.5,
                            em: 0.18,
                            color: theme.mono,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Container(width: 34, height: 1, color: theme.line2),
                      ],
                    ),
                  ),

                  // The weighting caption, bottom-right.
                  Positioned(
                    left: widget.pad,
                    right: widget.pad,
                    bottom: 52,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(width: 34, height: 1, color: theme.line2),
                        const SizedBox(height: 3),
                        Text(
                          widget.fieldLabel,
                          textAlign: TextAlign.right,
                          style: rcMono(
                            context,
                            size: 8.5,
                            em: 0.18,
                            color: theme.mono,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // The live-read pill, bottom-centre.
                  Positioned(
                    left: widget.pad,
                    right: widget.pad,
                    bottom: 8,
                    child: Center(
                      child: _ContextPill(
                        theme: theme,
                        label: widget.contextLine,
                        t: t,
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

// ── Rings ────────────────────────────────────────────────────────────────────

/// A marker riding on a ring, at the prototype's own offset from the ring's
/// centre **in the ring's own plane** (which is what the CSS offsets are,
/// since the dots are children of the transformed ring).
@immutable
class _RingDot {
  const _RingDot({
    required this.offset,
    required this.size,
    required this.color,
    this.opacity = 1,
    this.glow,
    this.glowBlur = 0,
  });

  final Offset offset;
  final double size;
  final Color color;
  final double opacity;
  final Color? glow;
  final double glowBlur;
}

/// One orbit ring: a circle in its own plane, spun by `rotateZ`, then tilted by
/// `rotateY` and `rotateX`, then projected through the stage's 900px
/// perspective — the prototype's transform stack, in order.
@immutable
class _Orbit {
  const _Orbit({
    required this.centre,
    required this.radius,
    required this.rotateX,
    required this.spin,
    required this.color,
    this.rotateY = 0,
    this.opacity = 1,
    this.dashed = false,
    this.dots = const [],
  });

  /// Where the ring sits on the stage, in hero coordinates.
  final Offset centre;
  final double radius;

  /// Degrees.
  final double rotateX;
  final double rotateY;

  /// Radians; the `spinA`/`spinB`/`spinC` phase.
  final double spin;

  final Color color;
  final double opacity;
  final bool dashed;
  final List<_RingDot> dots;
}

/// The prototype's own three rings at time [t].
List<_Orbit> _orbits(ResourceCenterTheme theme, double t, double w, double h) {
  return [
    // `spinB 52s` — rotateX(62) rotateY(26), running backwards. `top:56%`.
    _Orbit(
      centre: Offset(w / 2, h * 0.56),
      radius: 145,
      rotateX: 62,
      rotateY: 26,
      spin: -2 * math.pi * _phase(t, 52),
      color: theme.line,
      opacity: 0.7,
      dots: [
        // `top:-3px;left:50%` — 6px cyan with a 10px glow.
        _RingDot(
          offset: const Offset(0, -145),
          size: 6,
          color: theme.cyan,
          opacity: 0.7,
          glow: theme.cyan,
          glowBlur: 10,
        ),
        // `bottom:14%;right:6%` — 4px accent.
        _RingDot(
          offset: const Offset(125.6, 102.4),
          size: 4,
          color: theme.accent,
          glow: theme.halo,
          glowBlur: 8,
        ),
      ],
    ),
    // `spinA 34s` — rotateX(73). `top:54%`.
    _Orbit(
      centre: Offset(w / 2, h * 0.54),
      radius: 113,
      rotateX: 73,
      spin: 2 * math.pi * _phase(t, 34),
      color: theme.line2,
      dots: [
        _RingDot(
          offset: const Offset(0, -113),
          size: 8,
          color: theme.accent,
          glow: theme.halo,
          glowBlur: 14,
        ),
        _RingDot(
          offset: const Offset(-113.5, -24.6),
          size: 5,
          color: theme.accent,
          opacity: 0.75,
        ),
        _RingDot(
          offset: const Offset(74.3, 60.4),
          size: 5,
          color: theme.cyan,
          opacity: 0.6,
        ),
      ],
    ),
    // `spinC 24s` — rotateX(84), dashed. `top:53%`.
    _Orbit(
      centre: Offset(w / 2, h * 0.53),
      radius: 84,
      rotateX: 84,
      spin: 2 * math.pi * _phase(t, 24),
      color: theme.line,
      opacity: 0.55,
      dashed: true,
    ),
  ];
}

/// Paints the rings' far or near halves.
///
/// CSS gets the interleaving free from `transform-style: preserve-3d`, which
/// depth-sorts the sphere against the rings. Flutter composites in paint order,
/// so the split is made explicit: this painter is asked twice — once under the
/// sphere for everything with `z <= 0`, once over it for everything in front.
/// Perspective foreshortening (`900px`, about the stage centre) is applied to
/// the outline and to each marker's size, so a marker swelling as it swings
/// toward the viewer reads as depth rather than as a size change.
class _OrbitPainter extends CustomPainter {
  const _OrbitPainter({required this.rings, required this.front});

  final List<_Orbit> rings;
  final bool front;

  /// `perspective: 900px`.
  static const double _d = 900;

  static const double _rad = math.pi / 180;

  @override
  void paint(Canvas canvas, Size size) {
    final origin = Offset(size.width / 2, size.height / 2);

    for (final ring in rings) {
      final cosA = math.cos(ring.rotateX * _rad);
      final sinA = math.sin(ring.rotateX * _rad);
      final cosB = math.cos(ring.rotateY * _rad);
      final sinB = math.sin(ring.rotateY * _rad);

      /// Projects a point in the ring's own plane, applying `rotateZ` (the
      /// spin), `rotateY`, `rotateX` and the perspective divide, in that order.
      (Offset, double) project(double lx, double ly) {
        final cs = math.cos(ring.spin);
        final sn = math.sin(ring.spin);
        final x0 = lx * cs - ly * sn;
        final y0 = lx * sn + ly * cs;

        final x1 = x0 * cosB;
        final z1 = -x0 * sinB;

        final y2 = y0 * cosA - z1 * sinA;
        final z2 = y0 * sinA + z1 * cosA;

        final world = ring.centre + Offset(x1, y2);
        final scale = _d / (_d - z2);
        return (origin + (world - origin) * scale, z2);
      }

      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..isAntiAlias = true
        ..color = ring.color.withValues(
          alpha: ring.color.a * ring.opacity,
        );

      // The outline, sampled finely enough that the curve stays smooth and the
      // z-sign flip lands within a pixel of the true silhouette.
      const steps = 180;
      Path? run;
      var dashOn = true;
      for (var i = 0; i <= steps; i++) {
        final psi = i / steps * 2 * math.pi;
        final (p, z) = project(
          ring.radius * math.cos(psi),
          ring.radius * math.sin(psi),
        );
        final visible = front ? z > 0 : z <= 0;
        // `border: 1px dashed` — roughly a 3px on / 3px off cadence.
        if (ring.dashed && i % 3 == 0) dashOn = !dashOn;
        if (!visible || (ring.dashed && !dashOn)) {
          if (run != null) {
            canvas.drawPath(run, stroke);
            run = null;
          }
          continue;
        }
        if (run == null) {
          run = Path()..moveTo(p.dx, p.dy);
        } else {
          run.lineTo(p.dx, p.dy);
        }
      }
      if (run != null) canvas.drawPath(run, stroke);

      for (final dot in ring.dots) {
        final (p, z) = project(dot.offset.dx, dot.offset.dy);
        if (front ? z <= 0 : z > 0) continue;
        final scale = _d / (_d - z);
        final r = dot.size / 2 * scale;
        if (dot.glow != null && dot.glowBlur > 0) {
          canvas.drawCircle(
            p,
            r,
            Paint()
              ..color = dot.glow!
              ..maskFilter = MaskFilter.blur(
                BlurStyle.normal,
                dot.glowBlur / 2,
              ),
          );
        }
        canvas.drawCircle(
          p,
          r,
          Paint()..color = dot.color.withValues(alpha: dot.color.a * dot.opacity),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_OrbitPainter old) =>
      old.front != front || old.rings != rings;
}

// ── Sphere ───────────────────────────────────────────────────────────────────

/// The field object itself: the `--sphere` gradient body, its two inset
/// shadows, the breathing core, the tilted equator, the travelling `sheen`
/// specular and the fixed highlight.
class _FieldSphere extends StatelessWidget {
  const _FieldSphere({required this.theme, required this.t});

  final ResourceCenterTheme theme;
  final double t;

  @override
  Widget build(BuildContext context) {
    // `sheen 9s`: translateX(-140% → 160%) of the 38px bar, fading in at 18%
    // and out by 45% of the cycle.
    final sheenPhase = _phase(t, 9);
    final sheenX = -53.2 + (60.8 - -53.2) * (sheenPhase / 0.45).clamp(0.0, 1.0);
    final sheenOpacity = sheenPhase <= 0.18
        ? sheenPhase / 0.18 * 0.55
        : sheenPhase <= 0.45
        ? (1 - (sheenPhase - 0.18) / 0.27) * 0.55
        : 0.0;

    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        // The CSS list is `0 26px 54px rgba(0,0,0,.45), 0 0 66px var(--halo)`,
        // and CSS paints a shadow list **front to back** — the first entry sits
        // on top. Flutter paints it back to front, so the order is reversed
        // here. It matters: the sphere's own fill is barely 16% opaque across
        // its lit half, so whichever of these two shadows ends up on top is
        // what shows through it. Painted the other way round the teal glow sits
        // over the drop shadow and floods the whole object.
        boxShadow: [
          // `0 0 66px var(--halo)`
          BoxShadow(color: theme.halo, blurRadius: 66),
          // `0 26px 54px rgba(0,0,0,.45)`
          BoxShadow(
            color: Colors.black.withValues(alpha: theme.isDark ? 0.45 : 0.16),
            blurRadius: 54,
            offset: const Offset(0, 26),
          ),
        ],
      ),
      child: ClipOval(
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // The body.
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(gradient: theme.sphere),
              ),
            ),
            // `inset -10px -14px 34px rgba(0,0,0,.55)` — the terminator, drawn
            // as an inward falloff biased up-left so the lower-right rim goes
            // dark. Flutter has no inset shadow.
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  // A Flutter radial radius is a fraction of the box's
                  // shortest side, so the sphere's own rim sits at 0.5. Offset
                  // by the CSS shadow's (-10,-14), the far rim is 88px out
                  // (0.62 of 142) and the 34px band starts at 0.61 of that.
                  gradient: RadialGradient(
                    center: const Alignment(-0.14, -0.20),
                    radius: 0.62,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: theme.isDark ? 0.55 : 0.22),
                    ],
                    stops: const [0.61, 1.0],
                  ),
                ),
              ),
            ),
            // `inset 0 0 42px var(--haloS)` — the rim light.
            //
            // An inset shadow with no offset and no spread is the blur of a
            // hard edge that sits exactly on the rim, so only half the kernel
            // lands inside: it peaks at *half* the declared colour right at the
            // edge and is spent about half the blur radius inward. Reading the
            // 42px literally floods the whole face with accent and the object
            // stops reading as lit from one side.
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    radius: 0.5,
                    colors: [
                      theme.haloS.withValues(alpha: 0),
                      theme.haloS.withValues(alpha: theme.haloS.a * 0.5),
                    ],
                    stops: const [0.7, 1.0],
                  ),
                ),
              ),
            ),
            // The breathing core — 96px at `top:58%`, `breathe 6.5s`.
            Positioned(
              left: 71 - 48,
              top: 142 * 0.58 - 48,
              width: 96,
              height: 96,
              child: _Breathing(
                t: t,
                period: 6.5,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: theme.bloom(theme.halo),
                  ),
                ),
              ),
            ),
            // The equator: 150% wide hairline, rotated -8°.
            Positioned(
              left: -0.25 * 142,
              top: 71,
              width: 213,
              height: 1,
              child: Transform.rotate(
                angle: -8 * math.pi / 180,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        theme.line2.withValues(alpha: 0),
                        theme.line2,
                        theme.line2.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // The travelling specular bar (`sheen`), rotated 18°.
            Positioned(
              left: sheenX,
              top: -0.4 * 142,
              width: 38,
              height: 142 * 1.9,
              child: Transform.rotate(
                angle: 18 * math.pi / 180,
                child: Opacity(
                  opacity: sheenOpacity,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.white.withValues(alpha: 0),
                          Colors.white.withValues(alpha: 0.5),
                          Colors.white.withValues(alpha: 0),
                        ],
                        stops: const [0.0, 0.5, 1.0],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // The fixed highlight at 26% / 20%.
            Positioned(
              left: 142 * 0.26,
              top: 142 * 0.20,
              width: 34,
              height: 22,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: theme.bloom(
                    Colors.white.withValues(alpha: 0.5),
                    stop: 0.7,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Small motion primitives ──────────────────────────────────────────────────

/// `@keyframes breathe{0%,100%{opacity:.55;transform:scale(.94)}
/// 50%{opacity:1;transform:scale(1.06)}}`.
class _Breathing extends StatelessWidget {
  const _Breathing({
    required this.t,
    required this.period,
    required this.child,
  });

  final double t;
  final double period;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final k = _shuttle(t, period);
    return Opacity(
      opacity: 0.55 + 0.45 * k,
      child: Transform.scale(scale: 0.94 + 0.12 * k, child: child),
    );
  }
}

/// One `drift 14s` mote: rises 46px and 14px to the right while fading in at
/// 12% of its cycle and out by the end.
class _Particle extends StatelessWidget {
  const _Particle({
    required this.t,
    required this.spec,
    required this.box,
    required this.theme,
  });

  final double t;
  final _ParticleSpec spec;
  final Size box;
  final ResourceCenterTheme theme;

  @override
  Widget build(BuildContext context) {
    final k = _phase(t, 14, spec.delay);
    final opacity = k < 0.12 ? (k / 0.12) * 0.7 : (1 - (k - 0.12) / 0.88) * 0.7;
    return Positioned(
      left: box.width * spec.x / 100 + 14 * k,
      top: box.height * spec.y / 100 - 46 * k,
      width: 2,
      height: 2,
      child: Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: theme.accent,
          ),
        ),
      ),
    );
  }
}

@immutable
class _ParticleSpec {
  const _ParticleSpec(this.x, this.y, this.delay);
  final double x;
  final double y;
  final double delay;
}

/// The prototype's own eight particle seeds — position in per-cent of the hero
/// box, plus an animation delay.
const List<_ParticleSpec> _particles = [
  _ParticleSpec(12, 72, 0),
  _ParticleSpec(26, 40, 2.4),
  _ParticleSpec(38, 84, 5.1),
  _ParticleSpec(52, 30, 7.3),
  _ParticleSpec(63, 66, 1.2),
  _ParticleSpec(74, 46, 3.8),
  _ParticleSpec(86, 74, 6.4),
  _ParticleSpec(46, 58, 9.1),
];

/// The glass pill under the field: a pinging accent dot and the live read.
class _ContextPill extends StatelessWidget {
  const _ContextPill({
    required this.theme,
    required this.label,
    required this.t,
  });

  final ResourceCenterTheme theme;
  final String label;
  final double t;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: rcBlur(context),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
          decoration: BoxDecoration(
            color: theme.solidify(context, theme.glass),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: theme.line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 12,
                height: 12,
                child: Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: [
                    // `@keyframes ping{0%{scale(.4);opacity:.55}
                    // 100%{scale(1.9);opacity:0}}` over 2.6s.
                    Builder(
                      builder: (context) {
                        final k = _phase(t, 2.6);
                        return Opacity(
                          opacity: 0.55 * (1 - k),
                          child: Transform.scale(
                            scale: 0.4 + 1.5 * k,
                            child: Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: theme.accent,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: theme.accent,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: rcMono(
                    context,
                    size: 9.5,
                    em: 0.14,
                    color: theme.fg,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Care-near-you radar ──────────────────────────────────────────────────────

/// The `CARE NEAR YOU` card's 150px radar head: three bottom-anchored rings, a
/// pinging origin, and pulsing blips. Purely a spatial motif — the prototype
/// itself labels it `APPROXIMATE POSITIONS`, and nothing here encodes a real
/// bearing.
class ResourceRadar extends StatefulWidget {
  const ResourceRadar({super.key, required this.theme, required this.label});

  final ResourceCenterTheme theme;
  final String label;

  @override
  State<ResourceRadar> createState() => _ResourceRadarState();
}

class _ResourceRadarState extends State<ResourceRadar>
    with SingleTickerProviderStateMixin {
  late final _FieldClock _clock = _FieldClock(this);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started && !AppMotion.reduceMotion(context)) {
      _started = true;
      _clock.start();
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;

    return SizedBox(
      height: 150,
      child: ClipRect(
        child: AnimatedBuilder(
          animation: _clock,
          builder: (context, _) {
            final t = _clock.seconds;
            return LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth;
                Widget ring(double size, double bottom, Color color, double o) {
                  return Positioned(
                    left: w / 2 - size / 2,
                    bottom: bottom,
                    width: size,
                    height: size,
                    child: Opacity(
                      opacity: o,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: color),
                        ),
                      ),
                    ),
                  );
                }

                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ring(300, -96, theme.line, 0.7),
                    ring(200, -46, theme.line, 1),
                    ring(120, -6, theme.line2, 1),
                    // The pinging origin.
                    Positioned(
                      left: w / 2 - 5,
                      bottom: 16,
                      width: 10,
                      height: 10,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned(
                            left: -4,
                            top: -4,
                            width: 18,
                            height: 18,
                            child: Builder(
                              builder: (context) {
                                final k = _phase(t, 3.4);
                                return Opacity(
                                  opacity: 0.55 * (1 - k),
                                  child: Transform.scale(
                                    scale: 0.4 + 1.5 * k,
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: theme.accent,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          Positioned.fill(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: theme.accent,
                                boxShadow: [
                                  BoxShadow(color: theme.halo, blurRadius: 18),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // `pulse 4s` blips.
                    for (final b in _blips)
                      Positioned(
                        left: w * b.x / 100,
                        bottom: b.y,
                        width: 6,
                        height: 6,
                        child: Builder(
                          builder: (context) {
                            final k = _shuttle(t - b.delay, 4);
                            return Opacity(
                              opacity: (0.35 + 0.55 * k) * 0.75,
                              child: Transform.scale(
                                scale: 1 + 0.5 * k,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: theme.cyan,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    Positioned(
                      left: 14,
                      top: 12,
                      right: 14,
                      child: Text(
                        widget.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: rcMono(
                          context,
                          size: 8.5,
                          em: 0.16,
                          color: theme.mono,
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

@immutable
class _BlipSpec {
  const _BlipSpec(this.x, this.y, this.delay);
  final double x;
  final double y;
  final double delay;
}

const List<_BlipSpec> _blips = [
  _BlipSpec(26, 64, 0),
  _BlipSpec(62, 88, 1.3),
  _BlipSpec(78, 44, 2.6),
];
