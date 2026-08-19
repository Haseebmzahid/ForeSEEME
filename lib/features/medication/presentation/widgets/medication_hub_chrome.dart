import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:fyp_foreseeme/core/theme/a11y.dart';
import 'package:fyp_foreseeme/core/widgets/app_motion.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/medication_hub_state.dart';

import 'medication_hub_style.dart';
import 'medication_hub_objects.dart';
import '../../../profile/presentation/widgets/profile_hub_motion.dart';

/// Chrome for the Medications screen, transcribed from the approved prototype
/// (`docs/Design/ForeSeeMe Medications.html`).
///
/// Every widget here is presentation only — it takes values and callbacks and
/// owns no state, no provider and no navigation decision. Scope is the
/// Medications screen; nothing else in the app imports this file.
///
/// Motion reuses `AmbientLoop` / `pingPong` from the Profile Hub, which are the
/// app's existing CSS-keyframe primitives; a second copy would be a second
/// implementation of the same thing.

// ── The glass slab every card is built from ──────────────────────────────────

/// The prototype's card material: a blurred, gradient-filled glass slab with a
/// hairline border, a lit top lip and a soft drop shadow.
///
/// Press behaviour is the prototype's `style-active`, verbatim: the slab sinks
/// `translateY(3px)`, scales to [pressedScale], and its shadow tightens — over
/// `.25s cubic-bezier(.2,.8,.2,1)`. There is no ripple and no glow; a Material
/// [InkWell] would introduce both, so the press is drawn here instead.
///
/// Under reduced transparency the blur is dropped and the fill goes opaque;
/// under reduced motion the press transition is instant.
class MedHubSlab extends StatefulWidget {
  const MedHubSlab({
    super.key,
    required this.child,
    this.onTap,
    this.radius = 20,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
    this.pressedScale = 0.986,
    this.sinkY = 3,
    this.blur = 18,
    this.fill,
    this.borderColor,
    this.dashedBorder = false,
    this.shadow,
    this.underlay,
    this.semanticLabel,
    this.semanticHint,
  });

  final Widget child;

  /// Null renders an inert slab with no press feedback and no button semantics.
  final VoidCallback? onTap;

  final double radius;
  final EdgeInsets padding;

  /// The prototype varies this per surface (`.986` for the medication cards,
  /// `.985` for the Check-In slab, `.96` for the rail tiles, `.93` for the FAB).
  final double pressedScale;

  /// The prototype's `translateY` under `style-active`.
  final double sinkY;

  final double blur;

  /// Defaults to [MedicationHubTheme.slabFill].
  final Gradient? fill;

  /// Defaults to `--line`.
  final Color? borderColor;

  /// The prototype's `border: 1px dashed` — carried by the missed dose tile,
  /// where the broken outline is what marks the dose as unresolved.
  final bool dashedBorder;

  /// Defaults to `--shadow`.
  final List<BoxShadow>? shadow;

  /// Ornament painted **inside** the slab's clip and **behind** its content —
  /// the prototype's absolutely-positioned children under `overflow: hidden`
  /// (the Check-In slab's light sweep). Passing them here rather than stacking
  /// them outside is what keeps them clipped to the corner radius.
  final Widget? underlay;

  final String? semanticLabel;
  final String? semanticHint;

  @override
  State<MedHubSlab> createState() => _MedHubSlabState();
}

class _MedHubSlabState extends State<MedHubSlab> {
  bool _pressed = false;

  bool get _interactive => widget.onTap != null;

  void _set(bool value) {
    if (!_interactive || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = MedicationHubTheme.of(context);
    final opaque = A11y.reduceTransparency(context);
    final reduceMotion = AppMotion.reduceMotion(context);
    final pressed = _pressed && _interactive;

    // `transition: transform .25s cubic-bezier(.2,.8,.2,1), box-shadow .25s`.
    const duration = Duration(milliseconds: 250);
    const curve = Cubic(0.2, 0.8, 0.2, 1);

    final radius = BorderRadius.circular(widget.radius);

    final slab = AnimatedContainer(
      duration: reduceMotion ? Duration.zero : duration,
      curve: curve,
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: pressed
            // `box-shadow: … 0 10px 18px rgba(0,0,0,.45)`
            ? [
                BoxShadow(
                  color: theme.shadowColor.withValues(
                    alpha: theme.isDark ? 0.45 : 0.12,
                  ),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ]
            : (widget.shadow ?? theme.slabShadow),
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: medHubBlur(context, widget.blur),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: radius,
              gradient: opaque ? null : (widget.fill ?? theme.slabFill),
              color: opaque ? theme.bg2 : null,
              border: Border.all(
                color: opaque
                    ? theme.txt2
                    : widget.dashedBorder
                    ? Colors.transparent
                    : (widget.borderColor ?? theme.line),
              ),
            ),
            child: Stack(
              children: [
                if (widget.underlay != null)
                  Positioned.fill(child: widget.underlay!),
                // `inset 0 1px 0 var(--hi)`.
                if (!opaque)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: 1,
                    child: ColoredBox(color: theme.hi),
                  ),
                if (widget.dashedBorder && !opaque)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _DashedBorderPainter(
                          color: widget.borderColor ?? theme.line,
                          radius: widget.radius,
                        ),
                      ),
                    ),
                  ),
                Padding(padding: widget.padding, child: widget.child),
              ],
            ),
          ),
        ),
      ),
    );

    final transformed = AnimatedContainer(
      duration: reduceMotion ? Duration.zero : duration,
      curve: curve,
      transform: pressed
          ? (Matrix4.identity()
              ..translateByDouble(0.0, widget.sinkY, 0.0, 1.0)
              ..scaleByDouble(
                widget.pressedScale,
                widget.pressedScale,
                1.0,
                1.0,
              ))
          : Matrix4.identity(),
      transformAlignment: Alignment.center,
      child: slab,
    );

    if (!_interactive) {
      return Semantics(label: widget.semanticLabel, child: transformed);
    }

    return Semantics(
      button: true,
      label: widget.semanticLabel,
      hint: widget.semanticHint,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _set(true),
        onTapUp: (_) => _set(false),
        onTapCancel: () => _set(false),
        onTap: widget.onTap,
        child: transformed,
      ),
    );
  }
}

/// `border: 1px dashed` around a rounded rectangle.
///
/// CSS picks its own dash length; `4 on / 4 off` is what a 1px dashed border
/// measures at these radii, and it divides evenly enough that the corners stay
/// symmetrical.
class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0.5, 0.5, size.width - 1, size.height - 1),
      Radius.circular(radius),
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = color;

    for (final metric in (Path()..addRRect(rrect)).computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = math.min(distance + 4, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + 4;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter old) =>
      old.color != color || old.radius != radius;
}

// ── Section header ───────────────────────────────────────────────────────────

/// `TODAY'S SCHEDULE ······ 2 TAKEN · 1 MISSED` — a mono label with an optional
/// mono readout on the right.
class MedHubSectionHeader extends StatelessWidget {
  const MedHubSectionHeader({
    super.key,
    required this.label,
    this.trailing,
    this.trailingColor,
    this.onTrailingTap,
    this.trailingHint,
  });

  final String label;
  final String? trailing;
  final Color? trailingColor;

  /// Makes the readout a control. Used for the schedule header, which is the
  /// screen's way through to the adherence history — see the note on
  /// `MedicationScreen`.
  final VoidCallback? onTrailingTap;

  final String? trailingHint;

  @override
  Widget build(BuildContext context) {
    final theme = MedicationHubTheme.of(context);
    return Row(
      // The prototype aligns the two labels on their baseline; both are the
      // same size, so centring them reads identically — and it keeps them
      // aligned when the readout carries a taller tap target.
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            label,
            style: medHubMono(
              context,
              size: 10,
              em: 0.2,
              color: theme.txt2,
            ),
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 8),
          // Flexible so a large text scale shortens the readout rather than
          // pushing it off the row.
          Flexible(
            child: _TrailingReadout(
              text: trailing!,
              color: trailingColor ?? theme.txt2,
              onTap: onTrailingTap,
              hint: trailingHint,
            ),
          ),
        ],
      ],
    );
  }
}

/// The header's right-hand readout, optionally a control.
///
/// When it is a control it grows a chevron and a 44dp tap target, so nothing on
/// the screen is tappable without saying so.
class _TrailingReadout extends StatelessWidget {
  const _TrailingReadout({
    required this.text,
    required this.color,
    this.onTap,
    this.hint,
  });

  final String text;
  final Color color;
  final VoidCallback? onTap;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final label = Text(
      text,
      textAlign: TextAlign.right,
      style: medHubMono(context, size: 10, em: 0.12, color: color),
    );

    if (onTap == null) return label;

    return Semantics(
      button: true,
      label: text,
      hint: hint,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          // Lifts the 10px label to a 44dp target without moving it.
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Flexible(child: label),
              const SizedBox(width: 2),
              Icon(Icons.chevron_right_rounded, size: 14, color: color),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Hero ─────────────────────────────────────────────────────────────────────

/// The prototype's 244px hero: two counter-rotating orbit rings behind a
/// floating capsule, an `N ACTIVE` chip on the left, a `TODAY / n of m taken`
/// slab on the right, and the `Next <med> · <time>` headline beneath.
///
/// Every number is passed in already derived — the hero computes nothing.
class MedHubHero extends StatelessWidget {
  const MedHubHero({
    super.key,
    required this.activeCount,
    required this.takenCount,
    required this.scheduledCount,
    required this.nextName,
    required this.nextTime,
  });

  final int activeCount;
  final int takenCount;
  final int scheduledCount;

  /// Null when the day holds nothing still to confirm.
  final String? nextName;
  final String? nextTime;

  @override
  Widget build(BuildContext context) {
    final theme = MedicationHubTheme.of(context);

    return SizedBox(
      height: 244,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // The rings + capsule, masked out toward the bottom by the prototype's
          // `mask-image: linear-gradient(to bottom, black 62%, transparent)`.
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: 206,
            child: IgnorePointer(
              child: ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (rect) => const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.white, Colors.transparent],
                  stops: [0.62, 1.0],
                ).createShader(rect),
                child: const _HeroOrbit(),
              ),
            ),
          ),

          // `N ACTIVE` chip — `left: 22px; top: 34px`.
          Positioned(
            left: 22,
            top: 34,
            child: _HeroChip(count: activeCount),
          ),

          // `TODAY / n of m taken` — `right: 22px; top: 62px`.
          Positioned(
            right: 22,
            top: 62,
            child: _TodaySlab(
              taken: takenCount,
              scheduled: scheduledCount,
            ),
          ),

          // The headline — `bottom: 4px`, centred.
          Positioned(
            left: 12,
            right: 12,
            bottom: 4,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'MEDICATIONS',
                  textAlign: TextAlign.center,
                  style: medHubMono(
                    context,
                    size: 10,
                    em: 0.28,
                    color: theme.txt2,
                  ),
                ),
                const SizedBox(height: 4),
                _NextHeadline(name: nextName, time: nextTime),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// `Next <med> · <time>`, with the time in the accent — or an honest line when
/// there is no dose left to confirm today.
class _NextHeadline extends StatelessWidget {
  const _NextHeadline({required this.name, required this.time});

  final String? name;
  final String? time;

  @override
  Widget build(BuildContext context) {
    final theme = MedicationHubTheme.of(context);
    final base = medHubSans(
      context,
      size: 22,
      em: -0.02,
      color: theme.txt,
      weight: FontWeight.w600,
      height: 1.15,
    );

    if (name == null || time == null) {
      return Text(
        'Nothing due right now',
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: base,
      );
    }

    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: 'Next ${name!} · '),
          TextSpan(
            text: time!,
            style: TextStyle(color: theme.accent),
          ),
        ],
      ),
      textAlign: TextAlign.center,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: base,
    );
  }
}

/// The two counter-rotating orbit rings, the contact shadow and the floating
/// capsule at the hero's centre.
class _HeroOrbit extends StatelessWidget {
  const _HeroOrbit();

  @override
  Widget build(BuildContext context) {
    final theme = MedicationHubTheme.of(context);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // `med-ringA 30s linear infinite` — a 226px ring tilted 76°.
        Positioned(
          left: 0,
          right: 0,
          top: 96,
          height: 226,
          child: Center(
            child: AmbientLoop(
              period: const Duration(seconds: 30),
              restT: 0.12,
              builder: (context, t, _) => CustomPaint(
                size: const Size(226, 226),
                painter: _OrbitRingPainter(
                  color: theme.accent.withValues(alpha: 0.22),
                  beadColor: theme.accent,
                  beadRadius: 3,
                  tilt: 76,
                  phase: t,
                  dashed: false,
                ),
              ),
            ),
          ),
        ),
        // `med-ringB 40s linear infinite` (reversed) — a 166px dashed ring.
        Positioned(
          left: 0,
          right: 0,
          top: 112,
          height: 166,
          child: Center(
            child: AmbientLoop(
              period: const Duration(seconds: 40),
              restT: 0.62,
              builder: (context, t, _) => CustomPaint(
                size: const Size(166, 166),
                painter: _OrbitRingPainter(
                  color: theme.txt.withValues(alpha: 0.14),
                  beadColor: theme.txt.withValues(alpha: 0.7),
                  beadRadius: 2.5,
                  tilt: 66,
                  phase: 1 - t,
                  dashed: true,
                ),
              ),
            ),
          ),
        ),
        // `med-contact 6s` — the capsule's shadow on the floor.
        Positioned(
          left: 0,
          right: 0,
          top: 168,
          height: 22,
          child: Center(
            child: AmbientLoop(
              period: const Duration(seconds: 6),
              restT: 0.5,
              builder: (context, t, _) {
                final scale = pingPongBetween(t, 1.0, 0.86);
                final opacity = pingPongBetween(t, 0.5, 0.3);
                return Transform.scale(
                  scaleX: scale,
                  child: Opacity(
                    opacity: opacity,
                    child: SizedBox(
                      width: 150,
                      height: 22,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: theme.bloom(
                            theme.shadowColor.withValues(
                              alpha: theme.isDark ? 0.65 : 0.22,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        // `med-float 6s` — the hero capsule.
        Positioned(
          left: 0,
          right: 0,
          top: 74,
          height: 66,
          child: Center(
            child: AmbientLoop(
              period: const Duration(seconds: 6),
              restT: 0.5,
              builder: (context, t, child) => Transform.translate(
                offset: Offset(0, pingPongBetween(t, 0, -12)),
                child: Transform.rotate(
                  angle: pingPongBetween(t, -18, -14) * math.pi / 180,
                  child: child,
                ),
              ),
              child: MedHubCapsule(
                width: 148,
                height: 66,
                glow: theme.glow,
                shadowColor: theme.shadowColor,
                isDark: theme.isDark,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// One orbit ring: an ellipse (a circle seen at [tilt]°) carrying a single
/// travelling bead. Painted rather than transformed, because a 76° `rotateX`
/// on a bordered box resamples the hairline into mush.
class _OrbitRingPainter extends CustomPainter {
  const _OrbitRingPainter({
    required this.color,
    required this.beadColor,
    required this.beadRadius,
    required this.tilt,
    required this.phase,
    required this.dashed,
  });

  final Color color;
  final Color beadColor;
  final double beadRadius;

  /// The prototype's `rotateX` in degrees; the ring's vertical extent is
  /// foreshortened by its cosine.
  final double tilt;

  /// `0..1` around the ring.
  final double phase;

  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final rx = size.width / 2 - 1;
    final ry = rx * math.cos(tilt * math.pi / 180);

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = color;

    final rect = Rect.fromCenter(
      center: Offset(cx, cy),
      width: rx * 2,
      height: ry * 2,
    );

    if (dashed) {
      // `border: 1px dashed` — 12 segments reads the same at this radius.
      const segments = 24;
      for (var i = 0; i < segments; i += 2) {
        final start = i / segments * 2 * math.pi;
        final sweep = 1 / segments * 2 * math.pi;
        canvas.drawArc(rect, start, sweep, false, paint);
      }
    } else {
      canvas.drawOval(rect, paint);
    }

    // The bead, travelling the ring.
    final angle = phase * 2 * math.pi - math.pi / 2;
    final bead = Offset(cx + rx * math.cos(angle), cy + ry * math.sin(angle));
    canvas.drawCircle(
      bead,
      beadRadius * 3,
      Paint()..color = beadColor.withValues(alpha: 0.35 * beadColor.a),
    );
    canvas.drawCircle(bead, beadRadius, Paint()..color = beadColor);
  }

  @override
  bool shouldRepaint(covariant _OrbitRingPainter old) =>
      old.phase != phase || old.color != color || old.beadColor != beadColor;
}

/// `● N ACTIVE` — a glass pill with a pulsing accent dot.
class _HeroChip extends StatelessWidget {
  const _HeroChip({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = MedicationHubTheme.of(context);

    return MedHubSlab(
      radius: 999,
      blur: 14,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      fill: LinearGradient(colors: [theme.glass2, theme.glass2]),
      shadow: theme.tileShadow,
      semanticLabel: '$count active medications',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // `med-pulse 2.4s`.
          AmbientLoop(
            period: const Duration(milliseconds: 2400),
            restT: 0.5,
            builder: (context, t, _) => Opacity(
              opacity: pingPongBetween(t, 0.35, 1.0),
              child: Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.accent,
                ),
              ),
            ),
          ),
          const SizedBox(width: 7),
          Text(
            '$count ACTIVE',
            style: medHubMono(
              context,
              size: 10,
              em: 0.14,
              color: theme.txt,
            ),
          ),
        ],
      ),
    );
  }
}

/// `TODAY / n of m taken`.
class _TodaySlab extends StatelessWidget {
  const _TodaySlab({required this.taken, required this.scheduled});

  final int taken;
  final int scheduled;

  @override
  Widget build(BuildContext context) {
    final theme = MedicationHubTheme.of(context);

    return MedHubSlab(
      radius: 12,
      blur: 14,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      fill: LinearGradient(colors: [theme.glass2, theme.glass2]),
      shadow: theme.tileShadow,
      semanticLabel: scheduled == 0
          ? 'No doses scheduled today'
          : 'Today, $taken of $scheduled doses taken',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'TODAY',
            style: medHubMono(context, size: 9, em: 0.16, color: theme.txt2),
          ),
          const SizedBox(height: 2),
          Text(
            scheduled == 0 ? 'No doses' : '$taken of $scheduled taken',
            style: medHubSans(
              context,
              size: 13,
              color: theme.txt,
              weight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Today's schedule rail ────────────────────────────────────────────────────

/// One dose tile on the rail. The promoted `NEXT UP` tile is wider (92 vs 76),
/// lifted 6px, accent-bordered and glowing — the prototype's own difference.
class MedHubDoseTile extends StatelessWidget {
  const MedHubDoseTile({
    super.key,
    required this.dose,
    required this.onTap,
  });

  final HubDose dose;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = MedicationHubTheme.of(context);
    final isNext = dose.phase == HubDosePhase.next;
    final ink = theme.inkFor(dose.phase);

    final tile = MedHubSlab(
      radius: isNext ? 18 : 16,
      blur: isNext ? 16 : 14,
      pressedScale: 0.96,
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: isNext ? 14 : 12),
      fill: isNext
          ? theme.accentFill()
          : dose.phase.isWarn
          ? LinearGradient(
              colors: [
                theme.warn.withValues(alpha: 0.05),
                theme.warn.withValues(alpha: 0.05),
              ],
            )
          : LinearGradient(colors: [theme.glass, theme.glass]),
      borderColor: isNext
          ? theme.accent.withValues(alpha: 0.5)
          : dose.phase.isWarn
          ? theme.warn.withValues(alpha: 0.45)
          : theme.line,
      dashedBorder: dose.phase.isWarn,
      shadow: isNext
          ? [
              BoxShadow(
                color: theme.shadowColor.withValues(
                  alpha: theme.isDark ? 0.50 : 0.12,
                ),
                blurRadius: 34,
                offset: const Offset(0, 20),
              ),
              BoxShadow(color: theme.glow, blurRadius: 26),
            ]
          : theme.tileShadow,
      onTap: onTap,
      semanticLabel:
          '${dose.medication.name} at ${dose.time}, ${dose.phase.label}',
      semanticHint: 'Opens medication details',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            dose.time,
            style: medHubMono(
              context,
              size: isNext ? 12 : 11,
              color: isNext ? theme.txt : theme.txt2,
            ),
          ),
          const SizedBox(height: 8),
          _DoseGlyph(phase: dose.phase),
          const SizedBox(height: 8),
          Text(
            dose.phase.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: medHubMono(context, size: 9, em: 0.12, color: ink),
          ),
        ],
      ),
    );

    // The prototype lifts the promoted tile out of the row and fades a `LATER`
    // tile to `.82`.
    return SizedBox(
      width: medHubTileWidth(context, isNext: isNext),
      child: Transform.translate(
        offset: Offset(0, isNext ? -6 : 0),
        child: dose.phase == HubDosePhase.later
            ? Opacity(opacity: 0.82, child: tile)
            : tile,
      ),
    );
  }
}

/// The 30/34px disc at a tile's centre: a filled check for `TAKEN`, an amber
/// `!` for missed/skipped, a pulsing ring for `NEXT UP`, an inert dot for
/// `LATER`.
class _DoseGlyph extends StatelessWidget {
  const _DoseGlyph({required this.phase});

  final HubDosePhase phase;

  @override
  Widget build(BuildContext context) {
    final theme = MedicationHubTheme.of(context);

    switch (phase) {
      case HubDosePhase.taken:
        return Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: theme.accent,
            border: Border.all(color: theme.accent),
          ),
          child: Icon(Icons.check_rounded, size: 17, color: theme.onAccent),
        );

      case HubDosePhase.missed:
      case HubDosePhase.skipped:
        // `border: 1px dashed var(--warn)` — the disc is broken too.
        return Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: theme.warn.withValues(alpha: 0.12),
          ),
          foregroundDecoration: ShapeDecoration(
            shape: _DashedCircleBorder(color: theme.warn),
          ),
          child: Text(
            '!',
            style: medHubSans(
              context,
              size: 15,
              color: theme.warn,
              weight: FontWeight.w700,
            ),
          ),
        );

      case HubDosePhase.next:
        return SizedBox(
          width: 34,
          height: 34,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              // `med-pulse 2.6s` — the halo ring outside the disc.
              Positioned(
                left: -6,
                right: -6,
                top: -6,
                bottom: -6,
                child: AmbientLoop(
                  period: const Duration(milliseconds: 2600),
                  restT: 0.5,
                  builder: (context, t, child) => Opacity(
                    opacity: pingPongBetween(t, 0.25, 0.9),
                    child: Transform.scale(
                      scale: pingPongBetween(t, 1.0, 1.28),
                      child: child,
                    ),
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: theme.accent),
                    ),
                  ),
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: theme.accent, width: 2),
                  boxShadow: [BoxShadow(color: theme.glow, blurRadius: 16)],
                ),
                child: const SizedBox(width: 34, height: 34),
              ),
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.accent,
                ),
              ),
            ],
          ),
        );

      case HubDosePhase.later:
        return Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: theme.track2),
          ),
          child: Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: theme.track2,
            ),
          ),
        );
    }
  }
}

/// The dashed counterpart of a circular border, for the missed dose glyph.
class _DashedCircleBorder extends OutlinedBorder {
  const _DashedCircleBorder({required this.color})
    : super(side: BorderSide.none);

  final Color color;

  @override
  EdgeInsetsGeometry get dimensions => const EdgeInsets.all(1);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      Path()..addOval(rect.deflate(1));

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      Path()..addOval(rect);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = color;
    final path = Path()..addOval(rect.deflate(0.5));
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = math.min(distance + 3.5, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + 3.5;
      }
    }
  }

  @override
  ShapeBorder scale(double t) => this;

  @override
  _DashedCircleBorder copyWith({BorderSide? side, Color? color}) =>
      _DashedCircleBorder(color: color ?? this.color);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _DashedCircleBorder && other.color == color;

  @override
  int get hashCode => color.hashCode;
}

// ── Medication card ──────────────────────────────────────────────────────────

/// The prototype's medication row: a floating 3D object, name + `dosage ·
/// frequency`, the reminder times and today's standing, and a chevron.
class MedHubMedicationCard extends StatelessWidget {
  const MedHubMedicationCard({
    super.key,
    required this.entry,
    required this.onTap,
    required this.floatIndex,
  });

  final HubMedication entry;
  final VoidCallback onTap;

  /// Staggers the object's float loop, as the prototype does with its
  /// `5s / 5.6s .4s / 6.2s .8s / 5.2s 1.1s` animation set.
  final int floatIndex;

  @override
  Widget build(BuildContext context) {
    final theme = MedicationHubTheme.of(context);
    final medication = entry.medication;
    final status = _statusLabel(entry);

    return MedHubSlab(
      onTap: onTap,
      radius: 20,
      borderColor: entry.status == HubMedicationStatus.behind
          ? theme.warn.withValues(alpha: 0.28)
          : theme.line,
      semanticLabel:
          '${medication.name}, ${medication.dosage}, '
          '${medication.frequency.label}. $status',
      semanticHint: 'Opens medication details',
      child: Row(
        children: [
          MedHubObject(
            type: medication.type,
            floatIndex: floatIndex,
            shadowColor: theme.shadowColor,
            isDark: theme.isDark,
            warn: theme.warn,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  medication.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: medHubSans(
                    context,
                    size: 17,
                    em: -0.02,
                    color: theme.txt,
                    weight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${medication.dosage} · ${medication.frequency.label}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: medHubSans(
                    context,
                    size: 12.5,
                    color: theme.txt2,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _timesLabel(entry.times),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: medHubMono(context, size: 12, color: theme.txt),
                ),
                const SizedBox(height: 6),
                _StatusChip(entry: entry, label: status),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Icon(
            Icons.chevron_right_rounded,
            size: 18,
            color: theme.txt2,
          ),
        ],
      ),
    );
  }

  /// The prototype's own compression: full `HH:mm` for one or two times, and
  /// hour-only (`08 · 14 · 20`) once there are three, which is where the full
  /// form stops fitting.
  static String _timesLabel(List<String> times) {
    if (times.isEmpty) return '—';
    if (times.length >= 3) {
      return times.map((t) => t.split(':').first).join(' · ');
    }
    return times.join(' · ');
  }

  static String _statusLabel(HubMedication entry) => switch (entry.status) {
    HubMedicationStatus.allTaken => 'TAKEN',
    HubMedicationStatus.onTrack => 'ON TRACK',
    HubMedicationStatus.behind => entry.missedCount == 1
        ? '1 MISSED'
        : '${entry.missedCount} MISSED',
    HubMedicationStatus.noSchedule => 'NO REMINDERS',
  };
}

/// `● ON TRACK` — a dot in the status ink plus the mono label. The dot breathes
/// only when something is behind, as the prototype's `med-breathe` does.
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.entry, required this.label});

  final HubMedication entry;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = MedicationHubTheme.of(context);
    final ink = theme.inkForStatus(entry.status);

    final dot = Container(
      width: 5,
      height: 5,
      decoration: BoxDecoration(shape: BoxShape.circle, color: ink),
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (entry.status == HubMedicationStatus.behind)
          AmbientLoop(
            period: const Duration(milliseconds: 2600),
            restT: 0.5,
            builder: (context, t, child) =>
                Opacity(opacity: pingPongBetween(t, 0.55, 1.0), child: child),
            child: dot,
          )
        else
          dot,
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: medHubMono(context, size: 9, em: 0.1, color: ink),
          ),
        ),
      ],
    );
  }
}

// ── Check-In call to action ──────────────────────────────────────────────────

/// The prototype's fixed Check-In slab: an accent-tinted glass bar with a
/// target glyph, a subtitle naming the dose to confirm, an arrow chip, and a
/// light sweep across its top edge.
class MedHubCheckInCta extends StatelessWidget {
  const MedHubCheckInCta({
    super.key,
    required this.subtitle,
    required this.onTap,
  });

  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = MedicationHubTheme.of(context);

    return MedHubSlab(
      onTap: onTap,
      radius: 22,
      blur: 22,
      sinkY: 4,
      pressedScale: 0.985,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      fill: theme.checkInFill,
      borderColor: theme.accent.withValues(alpha: 0.38),
      shadow: [
        BoxShadow(
          color: theme.shadowColor.withValues(
            alpha: theme.isDark ? 0.60 : 0.14,
          ),
          blurRadius: 44,
          offset: const Offset(0, 24),
        ),
        BoxShadow(color: theme.glow, blurRadius: 34),
      ],
      semanticLabel: 'Check-In Now. $subtitle',
      underlay: const _SweepLine(),
      child: Row(
        children: [
          // The target glyph.
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: theme.isDark
                  ? const Color(0x66061412)
                  : theme.accent.withValues(alpha: 0.06),
              border: Border.all(color: theme.accent.withValues(alpha: 0.5)),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: theme.accent, width: 2),
                    boxShadow: [
                      BoxShadow(color: theme.glow, blurRadius: 12),
                    ],
                  ),
                ),
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: theme.accent,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Check-In Now',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: medHubSans(
                    context,
                    size: 16,
                    em: -0.01,
                    color: theme.txt,
                    weight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: medHubSans(
                    context,
                    size: 12,
                    color: theme.isDark
                        ? theme.txt.withValues(alpha: 0.72)
                        : theme.txt2,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: theme.accent,
              boxShadow: [
                BoxShadow(
                  color: theme.shadowColor.withValues(
                    alpha: theme.isDark ? 0.45 : 0.12,
                  ),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Icon(
              Icons.arrow_forward_rounded,
              size: 17,
              color: theme.onAccent,
            ),
          ),
        ],
      ),
    );
  }
}

/// `med-sweep 5s` — a highlight travelling along the slab's top edge.
class _SweepLine extends StatelessWidget {
  const _SweepLine();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          return AmbientLoop(
            period: const Duration(seconds: 5),
            restT: 0.5,
            builder: (context, t, child) => Stack(
              children: [
                Positioned(
                  top: 0,
                  left: width * (-1.3 + 3.7 * Curves.easeInOut.transform(t)),
                  width: width,
                  height: 1,
                  child: child!,
                ),
              ],
            ),
            child: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0x00FFFFFF),
                    Color(0xB3FFFFFF),
                    Color(0x00FFFFFF),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Floating action button ───────────────────────────────────────────────────

/// The prototype's 60×60 `+` FAB: an accent-tinted glass square with a 22px
/// radius and an accent glow.
class MedHubFab extends StatelessWidget {
  const MedHubFab({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = MedicationHubTheme.of(context);

    return SizedBox(
      width: 60,
      height: 60,
      child: MedHubSlab(
        onTap: onTap,
        radius: 22,
        blur: 20,
        sinkY: 4,
        pressedScale: 0.93,
        padding: EdgeInsets.zero,
        fill: LinearGradient(
          begin: const Alignment(-0.42, -1.0),
          end: const Alignment(0.42, 1.0),
          colors: [
            theme.accent.withValues(alpha: 0.24),
            theme.txt.withValues(alpha: theme.isDark ? 0.06 : 0.04),
          ],
        ),
        borderColor: theme.accent.withValues(alpha: 0.45),
        shadow: [
          BoxShadow(
            color: theme.shadowColor.withValues(
              alpha: theme.isDark ? 0.60 : 0.16,
            ),
            blurRadius: 38,
            offset: const Offset(0, 22),
          ),
          BoxShadow(color: theme.glow, blurRadius: 30),
        ],
        semanticLabel: 'Add medication',
        child: Center(
          child: Icon(Icons.add_rounded, size: 26, color: theme.accent),
        ),
      ),
    );
  }
}
