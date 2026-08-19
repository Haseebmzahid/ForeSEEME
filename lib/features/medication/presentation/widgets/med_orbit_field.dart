import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:fyp_foreseeme/core/widgets/app_motion.dart';

import 'med_orbit_style.dart';

/// The spatial stage of the Daily Check-In screen, transcribed from the
/// approved prototype (`docs/Design/Medication Orbit (standalone).html`).
///
/// Presentation only: it takes a already-ordered list of [MedOrbitDoseView]s
/// plus callbacks and owns no provider, no state and no scheduling decision.
///
/// ## How the 2.5D is produced
///
/// The prototype is a CSS `perspective: 900px` scene whose children are placed
/// with `translate3d(x, y, z)`. Rather than pushing a perspective matrix
/// through Flutter (which forces a layer per object and makes hit-testing
/// awkward), the same projection is evaluated directly: a point at depth `z`
/// behind the screen is drawn at `scale = 900 / (900 + z)` and its planar
/// offset from the vanishing point is scaled by the same factor. That is
/// exactly what the browser does, costs nothing but arithmetic, and keeps the
/// objects as ordinary hit-testable widgets.

/// Which corner glyph a dose object carries.
enum MedDoseBadge { none, taken, skipped, missed }

/// The beat a dose object is playing while the user's check-in is committing.
///
/// The screen drives these in sequence (see `_markDose`); each maps to a target
/// transform that the object animates toward, so Take and Skip read as two
/// physically different events rather than the same generic acknowledgement.
///
/// The final beat of each sequence deliberately lands *close to* where the
/// spatial system will put the resolved dose (a past-slot object), so when the
/// state commits the object hands off to its normal depth animation without a
/// visible jump.
enum MedDoseAction {
  /// Not committing — the object obeys its slot alone.
  none,

  /// Take, beat 1: the dose lifts toward the viewer, as if picked up.
  lift,

  /// Take, beat 2: the dose is drawn inward and down — consumed, not deleted.
  consume,

  /// Skip, beat 1: the dose is pushed gently back, away from the hand.
  push,

  /// Skip, beat 2: the dose withdraws off the path and dims.
  recede,

  /// Either action, final beat: the resolved dose rests just off the hero
  /// plane while it holds focus for one confirmation beat. It reads as put
  /// away rather than springing back to full size, which is what returning
  /// straight to the neutral pose would look like.
  settled,
}

/// How a dose object is transformed for a [MedDoseAction], on top of whatever
/// its slot already dictates.
@immutable
class _Choreography {
  const _Choreography({
    this.scale = 1,
    this.dx = 0,
    this.dy = 0,
    this.rotateX = 0,
    this.rotateZ = 0,
    this.opacity = 1,
    this.blur = 0,
    this.bloom = 0,
    this.duration = const Duration(milliseconds: 260),
    this.curve = Curves.easeOutCubic,
  });

  /// Multiplier on the object's projected scale.
  final double scale;

  /// Offsets in design space, scaled with the stage.
  final double dx;
  final double dy;

  final double rotateX;
  final double rotateZ;

  /// Multiplier on the object's slot opacity.
  final double opacity;

  final double blur;

  /// Strength of the specular bloom across the object's body.
  final double bloom;

  final Duration duration;
  final Curve curve;

  static const _Choreography none = _Choreography();

  static _Choreography of(MedDoseAction action) => switch (action) {
    MedDoseAction.none => none,
    // Picked up: rises, tips its face toward the viewer, catches the light.
    MedDoseAction.lift => const _Choreography(
      scale: 1.06,
      dy: -10,
      rotateX: -0.10,
      bloom: 1,
      duration: Duration(milliseconds: 150),
    ),
    // Consumed: accelerates inward and down, shrinking and softening. easeIn is
    // the point — it leaves rather than arrives.
    MedDoseAction.consume => const _Choreography(
      scale: 0.62,
      dy: 34,
      rotateX: 0.34,
      opacity: 0.45,
      blur: 1.2,
      bloom: 0.25,
      duration: Duration(milliseconds: 230),
      curve: Curves.easeInCubic,
    ),
    // Set down: settles back a little, no lift — this dose was not taken.
    MedDoseAction.push => const _Choreography(
      scale: 0.965,
      rotateX: 0.05,
      opacity: 0.95,
      duration: Duration(milliseconds: 120),
    ),
    // Withdrawn: drifts off the path and dims, still present, no longer active.
    MedDoseAction.recede => const _Choreography(
      scale: 0.80,
      dx: -30,
      rotateZ: -0.06,
      opacity: 0.55,
      duration: Duration(milliseconds: 210),
    ),
    // Put away: a small resting offset from the hero plane, held while the
    // panel shows the dose's new status.
    MedDoseAction.settled => const _Choreography(
      scale: 0.86,
      dy: 12,
      opacity: 0.78,
      duration: Duration(milliseconds: 260),
    ),
  };
}

/// One medication object on the stage.
@immutable
class MedOrbitDoseView {
  const MedOrbitDoseView({
    required this.id,
    required this.slot,
    required this.phase,
    required this.isCapsule,
    required this.badge,
    required this.timeLabel,
    required this.semanticLabel,
    required this.action,
    required this.onTap,
  });

  /// Stable identity, so an object keeps its element (and therefore its
  /// in-flight animation) as the field reorders.
  final String id;

  /// Position on the temporal path relative to the focused dose:
  /// `0` is the hero, `> 0` recedes into the future, `< 0` falls into the past.
  final int slot;

  final MedOrbitPhase phase;

  /// Capsule (liquid / syrup) vs tablet (pill), from the medication's own type.
  final bool isCapsule;

  final MedDoseBadge badge;

  /// Trailing time chip, e.g. `8:00 AM`. Hidden on the focused object, which
  /// shows its time in the panel readout instead.
  final String timeLabel;

  final String semanticLabel;

  /// The beat this object is playing while a check-in commits.
  final MedDoseAction action;

  final VoidCallback onTap;
}

/// Design-space metrics, straight from the prototype.
class _Orbit {
  const _Orbit._();

  static const double perspective = 900;
  static const double designWidth = 390;
  static const double designHeight = 414; // the prototype's stage height

  /// Depth / rise of an upcoming dose, indexed by clamped slot distance.
  static const List<double> futureZ = [0, 250, 470, 660, 820];
  static const List<double> futureY = [0, -112, -190, -252, -304];
  static const List<double> futureOpacity = [1, .9, .74, .58, .44];

  /// Depth / fall of a resolved dose.
  static const List<double> pastZ = [0, 245, 460, 640, 800];
  static const List<double> pastY = [0, 116, 220, 302, 364];
  static const List<double> pastOpacity = [1, .5, .35, .24, .17];

  /// The prototype clamps depth at four steps; beyond that an object is
  /// indistinguishable, so it is not built at all.
  static const int maxSlot = 4;

  static double projection(double z) => perspective / (perspective + z);
}

class MedOrbitField extends StatefulWidget {
  const MedOrbitField({
    super.key,
    required this.doses,
    required this.rippleTick,
    required this.onFocusStep,
    required this.onDayStep,
  });

  final List<MedOrbitDoseView> doses;

  /// Incremented by the screen each time a dose is confirmed taken; the change
  /// — not the value — fires the ground ripple.
  final int rippleTick;

  /// Vertical drag along the temporal path: `-1` toward earlier doses.
  final ValueChanged<int> onFocusStep;

  /// Horizontal drag across days: `-1` previous, `+1` next.
  final ValueChanged<int> onDayStep;

  @override
  State<MedOrbitField> createState() => _MedOrbitFieldState();
}

class _MedOrbitFieldState extends State<MedOrbitField>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ripple = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  Offset? _dragOrigin;
  int _dragStartSlotOffset = 0;
  bool _dragResolvedAsDay = false;

  @override
  void didUpdateWidget(covariant MedOrbitField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The ripple is pure celebration, so reduced motion drops it entirely; the
    // dose still commits and still shows its taken badge.
    if (widget.rippleTick != oldWidget.rippleTick &&
        !AppMotion.reduceMotion(context)) {
      _ripple.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _ripple.dispose();
    super.dispose();
  }

  void _onPanStart(DragStartDetails details) {
    _dragOrigin = details.localPosition;
    _dragStartSlotOffset = 0;
    _dragResolvedAsDay = false;
  }

  void _onPanUpdate(DragUpdateDetails details) {
    final origin = _dragOrigin;
    if (origin == null || _dragResolvedAsDay) return;

    final delta = details.localPosition - origin;
    // A decisive horizontal sweep is a day change, matching the prototype's
    // 56px / 1.4:1 threshold. It resolves once and locks the gesture.
    if (delta.dx.abs() > 56 && delta.dx.abs() > delta.dy.abs() * 1.4) {
      _dragResolvedAsDay = true;
      widget.onDayStep(delta.dx < 0 ? 1 : -1);
      return;
    }

    final step = (delta.dy / 74).round();
    if (step != _dragStartSlotOffset) {
      widget.onFocusStep(step - _dragStartSlotOffset);
      _dragStartSlotOffset = step;
    }
  }

  void _onPanEnd() {
    _dragOrigin = null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = MedOrbitTheme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;

        // One scale factor keeps the whole stage proportional on any screen
        // without hard-coding the prototype's 390 × 414 frame.
        final unit = math.min(
          width / _Orbit.designWidth,
          height / _Orbit.designHeight,
        ).clamp(0.68, 1.25);

        // `perspective-origin: 50% 40%` — the vanishing point.
        final origin = Offset(width / 2, height * 0.40);

        final visible = widget.doses
            .where((d) => d.slot.abs() <= _Orbit.maxSlot)
            .toList();
        // The prototype's `z-index: 60 - |slot| * 6`: nearer objects paint last.
        visible.sort((a, b) => b.slot.abs().compareTo(a.slot.abs()));

        // `fieldTf` — the stage drifts slightly so the path stays composed
        // whichever end of the day is in focus.
        final forward = widget.doses.isEmpty
            ? 0
            : math.min(widget.doses.map((d) => d.slot).reduce(math.max), 3);
        final back = widget.doses.isEmpty
            ? 0
            : math.min(-widget.doses.map((d) => d.slot).reduce(math.min), 3);
        final drift = (forward * 20 - back * 11) * unit;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: _onPanStart,
          onPanUpdate: _onPanUpdate,
          onPanEnd: (_) => _onPanEnd(),
          onPanCancel: _onPanEnd,
          child: ClipRect(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _TemporalFloorPainter(
                      origin: origin.translate(0, drift),
                      unit: unit,
                      color: theme.grid,
                    ),
                  ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedBuilder(
                      animation: _ripple,
                      builder: (context, _) => CustomPaint(
                        painter: _GroundRipplePainter(
                          origin: origin.translate(0, drift),
                          unit: unit,
                          progress: _ripple.value,
                          color: theme.accent,
                        ),
                      ),
                    ),
                  ),
                ),
                if (widget.doses.isEmpty)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: height * 0.44,
                    child: _EmptyStage(theme: theme),
                  ),
                for (final dose in visible)
                  _OrbitObject(
                    key: ValueKey(dose.id),
                    dose: dose,
                    origin: origin.translate(0, drift),
                    unit: unit,
                    theme: theme,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A single medication object, placed and lit for its slot on the path.
class _OrbitObject extends StatelessWidget {
  const _OrbitObject({
    super.key,
    required this.dose,
    required this.origin,
    required this.unit,
    required this.theme,
  });

  final MedOrbitDoseView dose;
  final Offset origin;
  final double unit;
  final MedOrbitTheme theme;

  @override
  Widget build(BuildContext context) {
    final slot = dose.slot;
    final distance = slot.abs().clamp(0, _Orbit.maxSlot);
    final isPast = slot < 0;

    final z = isPast ? _Orbit.pastZ[distance] : _Orbit.futureZ[distance];
    final rise = isPast ? _Orbit.pastY[distance] : _Orbit.futureY[distance];
    var opacity = isPast
        ? _Orbit.pastOpacity[distance]
        : _Orbit.futureOpacity[distance];

    final projection = _Orbit.projection(z);

    // The prototype fades a resolved dose toward the room and drops its
    // saturation; folding both into the tint keeps every object a plain,
    // filter-free widget.
    var desaturate = isPast ? 0.45 : 0.0;
    var darken = isPast ? 0.24 : 0.07 * distance;

    // A skipped / missed dose steps aside off the path.
    final isInactive = dose.phase == MedOrbitPhase.inactive;
    var lateral = 0.0;
    if (isInactive) {
      lateral = -74;
      opacity *= 0.8;
      desaturate = math.max(desaturate, 0.72);
    }

    final tint = MedDoseTint.of(dose.phase);
    final solid = _grade(tint.solid, desaturate: desaturate, darken: darken);

    final size = dose.isCapsule ? const Size(168, 60) : const Size(118, 96);
    final scale = projection * unit;

    // Reduced motion keeps every state change — only the travel is removed, so
    // the dose still reads as taken/skipped, it just doesn't fly there.
    final reduceMotion = AppMotion.reduceMotion(context);
    final act = reduceMotion
        ? _Choreography.none
        : _Choreography.of(dose.action);
    final isResolving = dose.action != MedDoseAction.none;

    final dx =
        origin.dx + (lateral + act.dx) * projection * unit;
    final dy = origin.dy + (rise + act.dy) * projection * unit;

    // Objects two or more steps away sit outside the focal plane.
    final depthBlur = distance >= 3 ? 1.4 : (distance >= 2 ? 0.7 : 0.0);
    final blurSigma = depthBlur + act.blur;

    Widget object = Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        Positioned(
          left: -42,
          top: -42,
          right: -42,
          bottom: -42,
          child: IgnorePointer(
            child: _Halo(
              color: tint.glow,
              alpha:
                  tint.glowAlpha *
                  (slot == 0 ? (isResolving ? 1.4 : 1) : 0.4),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: size.height - 14,
          height: 52,
          child: IgnorePointer(
            child: _ContactShadow(
              color: theme.groundShadow,
              width: dose.isCapsule ? 186 : 136,
              // Lifting the dose off the path tightens and lightens its contact
              // shadow, the way a real object leaving a surface would.
              opacity:
                  (slot == 0
                      ? 0.85
                      : math.max(0.12, 0.5 - distance * 0.18)) *
                  (dose.action == MedDoseAction.lift ? 0.55 : 1.0),
            ),
          ),
        ),
        Positioned.fill(
          child: dose.isCapsule
              ? _Capsule(solid: solid, shadow: theme.groundShadow)
              : _Tablet(solid: solid, shadow: theme.groundShadow),
        ),
        // A single restrained specular bloom instead of particles: the object
        // catches the light as it is picked up, and loses it as it goes.
        if (act.bloom > 0)
          Positioned.fill(
            child: IgnorePointer(
              child: _DoseBloom(
                strength: act.bloom,
                isCapsule: dose.isCapsule,
                duration: act.duration,
                curve: act.curve,
              ),
            ),
          ),
        if (dose.badge != MedDoseBadge.none)
          Positioned(
            right: -6,
            top: dose.isCapsule ? -8 : 0,
            child: IgnorePointer(
              child: _DoseBadge(
                badge: dose.badge,
                theme: theme,
                animate: !reduceMotion,
              ),
            ),
          ),
      ],
    );

    if (isInactive || act.rotateZ != 0) {
      object = Transform.rotate(
        angle: (isInactive ? -9 * math.pi / 180 : 0) + act.rotateZ,
        child: object,
      );
    }

    // The action beat. `TweenAnimationBuilder` interpolates from whatever the
    // previous beat left on screen, so lift → consume → committed is one
    // continuous move with no snap between phases, and it stops ticking the
    // moment it arrives.
    object = TweenAnimationBuilder<double>(
      tween: Tween(end: act.rotateX),
      duration: reduceMotion ? Duration.zero : act.duration,
      curve: act.curve,
      builder: (context, rotateX, child) => Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.0012)
          ..rotateX(rotateX),
        child: child,
      ),
      child: object,
    );

    if (blurSigma > 0) {
      object = ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: object,
      );
    }

    // While an object is travelling it repaints every frame; isolating it stops
    // that from dirtying the rest of the stage.
    object = RepaintBoundary(child: object);

    final settle = reduceMotion ? Duration.zero : act.duration;

    return AnimatedPositioned(
      duration: isResolving
          ? settle
          : (reduceMotion ? Duration.zero : const Duration(milliseconds: 920)),
      curve: isResolving ? act.curve : const Cubic(.22, .9, .24, 1),
      left: dx - size.width / 2,
      top: dy - size.height / 2,
      child: AnimatedOpacity(
        duration: isResolving
            ? settle
            : (reduceMotion ? Duration.zero : const Duration(milliseconds: 660)),
        curve: isResolving ? act.curve : Curves.easeOut,
        opacity: (opacity * act.opacity).clamp(0.0, 1.0),
        child: AnimatedScale(
          duration: isResolving
              ? settle
              : (reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 920)),
          curve: isResolving ? act.curve : const Cubic(.22, .9, .24, 1),
          scale: scale * act.scale,
          child: Semantics(
            button: true,
            label: dose.semanticLabel,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: dose.onTap,
              child: SizedBox(
                width: size.width,
                height: size.height,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(child: object),
                    if (slot != 0)
                      Positioned(
                        left: size.width + 14,
                        top: size.height / 2 - 7,
                        child: IgnorePointer(
                          child: Text(
                            dose.timeLabel,
                            softWrap: false,
                            style: medMono(
                              context,
                              size: 10,
                              em: 0.18,
                              color: tint.label.withValues(
                                alpha: math.max(0.3, 0.78 - distance * 0.16),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// CSS `saturate()` / `brightness()`, folded into the colour itself.
  static Color _grade(
    Color color, {
    required double desaturate,
    required double darken,
  }) {
    final hsl = HSLColor.fromColor(color);
    final flat = hsl
        .withSaturation((hsl.saturation * (1 - desaturate)).clamp(0.0, 1.0))
        .toColor();
    return Color.lerp(flat, Colors.black, darken.clamp(0.0, 1.0))!;
  }
}

// ── Medication objects ───────────────────────────────────────────────────────
//
// Both forms are built from stacked gradients rather than image filters: the
// prototype's blurred specular streaks are reproduced as soft alpha ramps, so a
// stage of nine objects costs no `saveLayer`.

/// A two-tone capsule: solid half, translucent half, a glass body over both.
class _Capsule extends StatelessWidget {
  const _Capsule({required this.solid, required this.shadow});

  final Color solid;
  final Color shadow;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: shadow.withValues(alpha: 0.9),
            blurRadius: 34,
            spreadRadius: -18,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // `stretch` is load-bearing: a childless ColoredBox takes the
            // smallest allowed height, and a Row's cross axis is loose.
            Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: ColoredBox(color: solid)),
                const Expanded(
                  child: ColoredBox(color: Color(0x38E4F4F1)), // .22 shell
                ),
              ],
            ),
            // Top-lit body shading.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x57FFFFFF),
                    Color(0x0DFFFFFF),
                    Color(0x1F000000),
                    Color(0x75000000),
                  ],
                  stops: [0.0, 0.34, 0.62, 1.0],
                ),
              ),
            ),
            // Edge darkening, so the body reads as round.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0x52000000),
                    Color(0x00000000),
                    Color(0x00000000),
                    Color(0x52000000),
                  ],
                  stops: [0.0, 0.14, 0.86, 1.0],
                ),
              ),
            ),
            // The seam between the two halves.
            const Align(
              alignment: Alignment.center,
              child: SizedBox(
                width: 2,
                height: double.infinity,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0x57000000), Color(0x21FFFFFF)],
                    ),
                  ),
                ),
              ),
            ),
            // Specular streak.
            const Positioned(
              left: 18,
              right: 30,
              top: 7,
              height: 10,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                  gradient: LinearGradient(
                    colors: [
                      Color(0x00FFFFFF),
                      Color(0x8FFFFFFF),
                      Color(0x1FFFFFFF),
                      Color(0x00FFFFFF),
                    ],
                    stops: [0.0, 0.4, 0.8, 1.0],
                  ),
                ),
              ),
            ),
            // Bounce light along the underside.
            const Positioned(
              left: 26,
              right: 26,
              bottom: 5,
              height: 6,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.all(Radius.circular(6)),
                  gradient: LinearGradient(
                    colors: [
                      Color(0x00FFFFFF),
                      Color(0x30FFFFFF),
                      Color(0x00FFFFFF),
                    ],
                  ),
                ),
              ),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.all(Radius.circular(30)),
                border: Border.fromBorderSide(
                  BorderSide(color: Color(0x24FFFFFF)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A scored tablet: three stacked ellipses give it thickness, the top one
/// carries the lighting.
class _Tablet extends StatelessWidget {
  const _Tablet({required this.solid, required this.shadow});

  final Color solid;
  final Color shadow;

  static const BorderRadius _disc = BorderRadius.all(
    Radius.elliptical(59, 42),
  );

  @override
  Widget build(BuildContext context) {
    Widget edge(double top, double brightness) => Positioned(
      left: 0,
      right: 0,
      top: top,
      height: 84,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: _disc,
          color: Color.lerp(solid, Colors.black, 1 - brightness),
        ),
      ),
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        edge(11, 0.42),
        edge(5, 0.62),
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: 84,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: _disc,
              color: solid,
              boxShadow: [
                BoxShadow(
                  color: shadow.withValues(alpha: 0.9),
                  blurRadius: 26,
                  spreadRadius: -16,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: _disc,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0x4DFFFFFF),
                          Color(0x0AFFFFFF),
                          Color(0x29000000),
                          Color(0x6B000000),
                        ],
                        stops: [0.0, 0.40, 0.70, 1.0],
                      ),
                    ),
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment(-0.4, -0.76),
                        radius: 0.9,
                        colors: [Color(0x6BFFFFFF), Color(0x00FFFFFF)],
                        stops: [0.0, 0.62],
                      ),
                    ),
                  ),
                  // Score line.
                  const Center(
                    child: SizedBox(
                      width: 80,
                      height: 2,
                      child: DecoratedBox(
                        decoration: BoxDecoration(color: Color(0x42000000)),
                      ),
                    ),
                  ),
                  const Positioned(
                    left: 24,
                    top: 11,
                    width: 34,
                    height: 9,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.all(Radius.circular(10)),
                        gradient: RadialGradient(
                          colors: [Color(0x8FFFFFFF), Color(0x00FFFFFF)],
                        ),
                      ),
                    ),
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: _disc,
                      border: Border.fromBorderSide(
                        BorderSide(color: Color(0x24FFFFFF)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The soft light an object throws onto the stage around it.
class _Halo extends StatelessWidget {
  const _Halo({required this.color, required this.alpha});

  final Color color;
  final double alpha;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 600),
      decoration: BoxDecoration(
        gradient: RadialGradient(
          colors: [
            color.withValues(alpha: alpha.clamp(0.0, 1.0)),
            color.withValues(alpha: 0),
          ],
          stops: const [0.0, 1.0],
        ),
      ),
    );
  }
}

/// The flattened shadow an object casts on the floor beneath it.
class _ContactShadow extends StatelessWidget {
  const _ContactShadow({
    required this.color,
    required this.width,
    required this.opacity,
  });

  final Color color;
  final double width;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    // A 52px disc stretched to the prototype's width and flattened into the
    // floor plane — Flutter's RadialGradient is circular, so the ellipse is
    // made by the transform rather than the box.
    return Center(
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 600),
        opacity: opacity.clamp(0.0, 1.0),
        child: Transform.scale(
          scaleX: width / 52,
          scaleY: 0.28,
          child: SizedBox.square(
            dimension: 52,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    color.withValues(alpha: 0.8),
                    color.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The specular bloom that rakes across a dose as it is picked up and fades as
/// it leaves. Deliberately one soft highlight, not a particle system.
class _DoseBloom extends StatelessWidget {
  const _DoseBloom({
    required this.strength,
    required this.isCapsule,
    required this.duration,
    required this.curve,
  });

  final double strength;
  final bool isCapsule;
  final Duration duration;
  final Curve curve;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: strength),
      duration: duration,
      curve: curve,
      builder: (context, t, _) => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: isCapsule
              ? const BorderRadius.all(Radius.circular(30))
              : const BorderRadius.all(Radius.elliptical(59, 42)),
          gradient: RadialGradient(
            center: const Alignment(-0.35, -0.7),
            radius: 0.95,
            colors: [
              Colors.white.withValues(alpha: 0.42 * t),
              Colors.white.withValues(alpha: 0),
            ],
            stops: const [0.0, 0.75],
          ),
        ),
      ),
    );
  }
}

/// The corner glyph marking a resolved dose.
///
/// It morphs in — a short scale + fade keyed on the badge itself — so the
/// confirmation reads as the dose settling into its final state rather than a
/// label appearing.
class _DoseBadge extends StatelessWidget {
  const _DoseBadge({
    required this.badge,
    required this.theme,
    this.animate = true,
  });

  final MedDoseBadge badge;
  final MedOrbitTheme theme;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final (Color border, Color glyph) = switch (badge) {
      MedDoseBadge.taken => (const Color(0xBF4EA88E), const Color(0xFF6FD9B4)),
      _ => (const Color(0x80B4AC9E), const Color(0xFFB4AC9E)),
    };

    final chip = Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: theme.isDark
            ? const Color(0xE6070E0E)
            : theme.panel.withValues(alpha: 0.94),
        border: Border.all(color: border),
      ),
      child: Center(
        child: switch (badge) {
          MedDoseBadge.taken => Icon(Icons.check_rounded, size: 12, color: glyph),
          MedDoseBadge.missed => Icon(Icons.close_rounded, size: 12, color: glyph),
          _ => Container(width: 9, height: 1.5, color: glyph),
        },
      ),
    );

    if (!animate) return chip;

    return TweenAnimationBuilder<double>(
      key: ValueKey(badge),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutBack,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.scale(scale: 0.6 + 0.4 * t, child: child),
      ),
      child: chip,
    );
  }
}

/// The prototype's ruled "nothing scheduled" plate.
class _EmptyStage extends StatelessWidget {
  const _EmptyStage({required this.theme});

  final MedOrbitTheme theme;

  @override
  Widget build(BuildContext context) {
    Widget rule() => Center(
      child: SizedBox(
        width: 120,
        height: 1,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                theme.grid.withValues(alpha: 0),
                theme.grid.withValues(alpha: 0.28),
                theme.grid.withValues(alpha: 0),
              ],
            ),
          ),
        ),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        rule(),
        const SizedBox(height: 22),
        Text(
          'NO DOSES SCHEDULED',
          textAlign: TextAlign.center,
          style: medMono(context, size: 11, em: 0.28, color: theme.ink6),
        ),
        const SizedBox(height: 22),
        rule(),
      ],
    );
  }
}

// ── Stage painters ───────────────────────────────────────────────────────────

/// The temporal path: runners converging on the vanishing point, crossed by
/// depth rules. Every stop is the projection of the prototype's own
/// `translateZ` values, so the floor recedes at exactly the rate the objects do.
class _TemporalFloorPainter extends CustomPainter {
  const _TemporalFloorPainter({
    required this.origin,
    required this.unit,
    required this.color,
  });

  final Offset origin;
  final double unit;
  final Color color;

  /// `translateZ` and alpha of each depth rule.
  static const List<(double, double)> _rules = [
    (0, .20),
    (210, .15),
    (420, .12),
    (640, .09),
    (880, .07),
    (1150, .05),
  ];

  /// Lateral offset and alpha of each runner.
  static const List<(double, double)> _runners = [
    (0, .16),
    (-132, .10),
    (132, .10),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    // The floor sits `translateY(150)` below the vanishing point.
    const floorY = 150.0;

    for (final (dx, alpha) in _runners) {
      final near = Offset(
        origin.dx + dx * unit,
        origin.dy + floorY * unit,
      );
      final paint = Paint()
        ..strokeWidth = 1
        ..shader = ui.Gradient.linear(
          origin,
          near,
          [color.withValues(alpha: 0), color.withValues(alpha: alpha)],
        );
      canvas.drawLine(origin, near, paint);
    }

    for (final (z, alpha) in _rules) {
      final projection = _Orbit.projection(z);
      final y = origin.dy + floorY * projection * unit;
      final halfWidth = 230 * projection * unit;
      final rect = Rect.fromLTRB(
        origin.dx - halfWidth,
        y,
        origin.dx + halfWidth,
        y + 1,
      );
      final paint = Paint()
        ..shader = ui.Gradient.linear(
          rect.centerLeft,
          rect.centerRight,
          [
            color.withValues(alpha: 0),
            color.withValues(alpha: alpha),
            color.withValues(alpha: 0),
          ],
          [0.0, 0.5, 1.0],
        );
      canvas.drawRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _TemporalFloorPainter old) =>
      old.origin != origin || old.unit != unit || old.color != color;
}

/// The ground ripple that acknowledges a taken dose: a ring pushed outward
/// across the floor plane, flattened to sit in perspective.
class _GroundRipplePainter extends CustomPainter {
  const _GroundRipplePainter({
    required this.origin,
    required this.unit,
    required this.progress,
    required this.color,
  });

  final Offset origin;
  final double unit;
  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) return;
    final eased = Curves.easeOutCubic.transform(progress);
    final scale = 0.35 + (2.5 - 0.35) * eased;
    final radius = 125 * scale * unit;

    canvas.drawOval(
      Rect.fromCenter(
        center: origin,
        width: radius * 2,
        height: radius * 2 * 0.30,
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = color.withValues(alpha: 0.55 * (1 - eased)),
    );
  }

  @override
  bool shouldRepaint(covariant _GroundRipplePainter old) =>
      old.progress != progress || old.origin != origin;
}
