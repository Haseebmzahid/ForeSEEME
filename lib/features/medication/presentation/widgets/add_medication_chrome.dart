import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:fyp_foreseeme/core/theme/a11y.dart';
import 'package:fyp_foreseeme/core/widgets/app_motion.dart';
import 'package:fyp_foreseeme/features/profile/presentation/widgets/profile_hub_motion.dart';

import 'add_medication_style.dart';

/// Chrome for the Add / Edit Medication screen, transcribed from the approved
/// prototype (`docs/Design/ForeSeeMe Add Medication (1).html`).
///
/// Every widget here is presentation only — it takes values and callbacks and
/// owns no state, no provider and no navigation decision. Scope is that one
/// screen; nothing else in the app imports this file.
///
/// Motion reuses `AmbientLoop` / `pingPong` from the Profile Hub and `AppReveal`
/// from `core/widgets/app_motion.dart`, which are the app's existing
/// CSS-keyframe primitives; a second copy would be a second implementation of
/// the same thing.

// ── The liquid-glass slab every surface is built from ────────────────────────

/// The prototype's card material: a blurred, 150°-gradient-filled slab with a
/// hairline border, an inner rim light (`--lgRim`), an optional corner
/// specular (`--lgSpec`) and a drop shadow.
///
/// Press behaviour is the prototype's `style-active`, verbatim: the slab sinks
/// [sinkY] and scales to [pressedScale] over `.22s cubic-bezier(.2,.8,.2,1)`.
/// There is no ripple and no Material glow; an [InkWell] would introduce both,
/// so the press is drawn here instead.
///
/// Under reduced transparency the blur is dropped and the fill goes opaque;
/// under reduced motion the press transition is instant.
class AddMedGlass extends StatefulWidget {
  const AddMedGlass({
    super.key,
    required this.child,
    this.onTap,
    this.radius = 18,
    this.padding = const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
    this.pressedScale = 0.98,
    this.sinkY = 2,
    this.blur = 15,
    this.fill,
    this.solidFill,
    this.borderColor,
    this.dashedBorder = false,
    this.shadow,
    this.specular = false,
    this.rim = true,
    this.underlay,
    this.semanticLabel,
    this.semanticSelected,
  });

  final Widget child;

  /// Null renders an inert slab with no press feedback and no button semantics.
  final VoidCallback? onTap;

  final double radius;
  final EdgeInsets padding;

  /// The prototype varies this per surface (`.98` for the type cards, `.97` for
  /// the frequency cards, `.985` for the wide buttons, `.94` for the chips).
  final double pressedScale;

  /// The prototype's `translateY` under `style-active`.
  final double sinkY;

  final double blur;

  /// Defaults to `--lg`.
  final Gradient? fill;

  /// A flat fill, used where the prototype sets a colour rather than `--lg`
  /// (`--field`, `--errSoft`, the ready CTA's `--accent`).
  final Color? solidFill;

  /// Defaults to `--bd`.
  final Color? borderColor;

  /// The prototype's `border: 1px dashed`.
  final bool dashedBorder;

  /// Defaults to `--shadow`. Pass an empty list for the flat surfaces.
  final List<BoxShadow>? shadow;

  /// The prototype's `::before { background: var(--lgSpec) }` — carried by the
  /// schedule-preview card and the reminder rows.
  final bool specular;

  /// The prototype's `--lgRim`. The flat `--field` surfaces still carry it;
  /// only the fully transparent chips do not.
  final bool rim;

  /// Ornament painted **inside** the slab's clip and **behind** its content —
  /// the prototype's absolutely-positioned children under `overflow: hidden`
  /// (the CTA's progress bar and shimmer). Passing them here rather than
  /// stacking them outside is what keeps them clipped to the corner radius.
  final Widget? underlay;

  final String? semanticLabel;
  final bool? semanticSelected;

  @override
  State<AddMedGlass> createState() => _AddMedGlassState();
}

class _AddMedGlassState extends State<AddMedGlass> {
  bool _pressed = false;

  bool get _interactive => widget.onTap != null;

  void _set(bool value) {
    if (!_interactive || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = AddMedTheme.of(context);
    final opaque = A11y.reduceTransparency(context);
    final reduceMotion = AppMotion.reduceMotion(context);
    final pressed = _pressed && _interactive;

    // `transition: transform .22s cubic-bezier(.2,.8,.2,1), background .25s`.
    const duration = Duration(milliseconds: 220);
    const curve = Cubic(0.2, 0.8, 0.2, 1);

    final radius = BorderRadius.circular(widget.radius);
    final border = widget.borderColor ?? theme.bd;

    final slab = AnimatedContainer(
      duration: reduceMotion ? Duration.zero : duration,
      curve: curve,
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: widget.shadow ?? theme.shadow,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: addMedBlur(context, widget.blur),
          child: AnimatedContainer(
            duration: reduceMotion ? Duration.zero : duration,
            curve: curve,
            decoration: BoxDecoration(
              borderRadius: radius,
              gradient: widget.solidFill != null
                  ? null
                  : (opaque ? null : (widget.fill ?? theme.lg)),
              color: widget.solidFill ?? (opaque ? theme.bg2 : null),
              border: widget.dashedBorder
                  ? null
                  : Border.all(color: opaque ? theme.txt3 : border),
            ),
            child: Stack(
              children: [
                if (widget.underlay != null)
                  Positioned.fill(child: widget.underlay!),
                if (widget.specular && !opaque)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: radius,
                          gradient: theme.lgSpec,
                        ),
                      ),
                    ),
                  ),
                if (widget.rim && !opaque)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _RimPainter(
                          gradient: theme.rim,
                          radius: widget.radius,
                        ),
                      ),
                    ),
                  ),
                if (widget.dashedBorder)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: AddMedDashedBorderPainter(
                          color: opaque ? theme.txt3 : border,
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
      return widget.semanticLabel == null
          ? transformed
          : Semantics(label: widget.semanticLabel, child: transformed);
    }

    return Semantics(
      button: true,
      selected: widget.semanticSelected,
      label: widget.semanticLabel,
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

/// `--lgRim`: an inner stroke whose brightness falls from the lit top lip to
/// the dimmer sides and bottom.
class _RimPainter extends CustomPainter {
  const _RimPainter({required this.gradient, required this.radius});

  final LinearGradient gradient;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    const width = 1.5;
    final rect = Rect.fromLTWH(
      width / 2,
      width / 2,
      size.width - width,
      size.height - width,
    );
    if (rect.isEmpty) return;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(radius)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..shader = gradient.createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(covariant _RimPainter old) =>
      old.gradient != gradient || old.radius != radius;
}

/// `border: 1px dashed` around a rounded rectangle.
///
/// CSS picks its own dash length; `4 on / 4 off` is what a 1px dashed border
/// measures at these radii, and it divides evenly enough that the corners stay
/// symmetrical.
class AddMedDashedBorderPainter extends CustomPainter {
  const AddMedDashedBorderPainter({required this.color, required this.radius});

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
  bool shouldRepaint(covariant AddMedDashedBorderPainter old) =>
      old.color != color || old.radius != radius;
}

// ── Backdrop ─────────────────────────────────────────────────────────────────

/// The prototype's three ambient layers: the drifting teal aurora, the cool
/// orb on the right, and the perspective floor grid at the foot.
///
/// The aurora tracks the scroll offset (`glow.style.marginTop = y * 0.18`).
class AddMedBackdrop extends StatelessWidget {
  const AddMedBackdrop({super.key, required this.scroll});

  final ScrollController scroll;

  @override
  Widget build(BuildContext context) {
    final theme = AddMedTheme.of(context);
    final size = MediaQuery.sizeOf(context);

    return Positioned.fill(
      child: IgnorePointer(
        child: RepaintBoundary(
          child: Stack(
            children: [
              // `left/right: -20%; top: -18%; height: 560px`, drifting on
              // `fm-glowDrift 14s`.
              AnimatedBuilder(
                animation: scroll,
                builder: (context, _) {
                  final y = scroll.hasClients ? scroll.offset : 0.0;
                  return Positioned(
                    left: -size.width * 0.2,
                    right: -size.width * 0.2,
                    top: -size.height * 0.18 + y * 0.18,
                    height: 560,
                    child: AmbientLoop(
                      period: const Duration(seconds: 14),
                      restT: 0,
                      builder: (context, t, child) => Transform.translate(
                        offset: Offset(
                          pingPongBetween(t, 0, 14),
                          pingPongBetween(t, 0, 10),
                        ),
                        child: Transform.scale(
                          scale: pingPongBetween(t, 1.0, 1.06),
                          child: child,
                        ),
                      ),
                      child: DecoratedBox(
                        decoration: BoxDecoration(gradient: theme.auroraFill),
                      ),
                    ),
                  );
                },
              ),
              // `right: -28%; top: 40%; 420×380`.
              Positioned(
                right: -size.width * 0.28,
                top: size.height * 0.40,
                width: 420,
                height: 380,
                child: DecoratedBox(
                  decoration: BoxDecoration(gradient: theme.orbFill),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: -40,
                height: 280,
                child: CustomPaint(
                  painter: _FloorGridPainter(line: theme.bdSoft),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The prototype's floor: a 46px grid under `transform: perspective(240px)
/// rotateX(74deg)` with `transform-origin: bottom center`, faded out toward the
/// top by a mask.
///
/// Painted directly rather than transformed, because a projected grid is a few
/// lines of geometry and a `Transform` with that much foreshortening resamples
/// hairlines into mush. Transcribed from the Medications Hub's floor, which is
/// the same declaration.
class _FloorGridPainter extends CustomPainter {
  const _FloorGridPainter({required this.line});

  final Color line;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final centerX = w / 2;

    double screenY(double depth) => h * (1 - 1 / (1 + depth * 3.2));

    for (var i = 0; i <= 14; i++) {
      final depth = i / 14;
      final y = screenY(depth);
      if (y >= h) continue;
      final fade = (1 - depth).clamp(0.0, 1.0);
      canvas.drawLine(
        Offset(0, y),
        Offset(w, y),
        Paint()
          ..color = line.withValues(alpha: line.a * fade * 0.5)
          ..strokeWidth = 1,
      );
    }

    for (var i = -9; i <= 9; i++) {
      canvas.drawLine(
        Offset(centerX + i * 46.0, h),
        Offset(centerX + i * 46.0 * 0.06, 0),
        Paint()
          ..strokeWidth = 1
          ..shader = LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              line.withValues(alpha: line.a * 0.5),
              line.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromLTWH(0, 0, w, h)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _FloorGridPainter old) => old.line != line;
}

// ── Header ───────────────────────────────────────────────────────────────────

/// The prototype's 60px header: a glass back button, then the title and its
/// one-line subtitle.
class AddMedHeader extends StatelessWidget {
  const AddMedHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onBack,
  });

  final String title;
  final String subtitle;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = AddMedTheme.of(context);

    return Container(
      // The prototype's fixed 60px, as a floor: at a large text scale the
      // title and its subtitle need the room rather than clipping.
      constraints: const BoxConstraints(minHeight: 60),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(gradient: theme.headerScrim),
      child: Row(
        children: [
          AddMedGlass(
            onTap: onBack,
            radius: 15,
            padding: EdgeInsets.zero,
            pressedScale: 0.92,
            sinkY: 0,
            blur: 15,
            shadow: [
              BoxShadow(
                color: theme.shadowColor.withValues(
                  alpha: theme.isDark ? 0.28 : 0.10,
                ),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
            semanticLabel: 'Back',
            child: SizedBox(
              width: 44,
              height: 44,
              child: Center(
                child: Icon(
                  Icons.arrow_back_ios_new_rounded,
                  size: 15,
                  color: theme.txt,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: addMedSans(
                    context,
                    size: 19,
                    weight: FontWeight.w600,
                    em: -0.02,
                    color: theme.txt,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: addMedSans(
                    context,
                    size: 11.5,
                    color: theme.txt2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Section furniture ────────────────────────────────────────────────────────

/// `1 · MEDICATION` — the prototype's mono section rule, optionally with a
/// readout on the right (`4 · REMINDER TIMES ······ 2 TIMES`).
class AddMedSectionLabel extends StatelessWidget {
  const AddMedSectionLabel({
    super.key,
    required this.label,
    this.suffix,
    this.trailing,
  });

  final String label;

  /// The faint `· OPTIONAL` tail on section 5.
  final String? suffix;

  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = AddMedTheme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text.rich(
            TextSpan(
              text: label,
              children: suffix == null
                  ? null
                  : [
                      TextSpan(
                        text: ' $suffix',
                        style: addMedMono(
                          context,
                          size: 9.5,
                          em: 0.2,
                          color: theme.txt3,
                        ),
                      ),
                    ],
            ),
            style: addMedMono(
              context,
              size: 9.5,
              em: 0.2,
              color: theme.txt2,
            ),
          ),
        ),
        if (trailing != null)
          Text(
            trailing!,
            style: addMedMono(
              context,
              size: 9.5,
              em: 0.12,
              color: theme.txt3,
            ),
          ),
      ],
    );
  }
}

/// The quiet one-line hint under a field.
class AddMedHelp extends StatelessWidget {
  const AddMedHelp(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = AddMedTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 7, 4, 0),
      child: Text(
        text,
        style: addMedSans(context, size: 11.5, color: theme.txt2, height: 1.35),
      ),
    );
  }
}

/// A validation message: a ringed `!` and the sentence, in `--err` (or in
/// `--warn` for the picker's non-blocking clash notice).
class AddMedNotice extends StatelessWidget {
  const AddMedNotice({
    super.key,
    required this.text,
    this.warning = false,
    this.padding = const EdgeInsets.fromLTRB(4, 8, 4, 0),
  });

  final String text;
  final bool warning;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final theme = AddMedTheme.of(context);
    final ink = warning ? theme.warn : theme.err;
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: AddMedBangGlyph(size: 15, color: ink),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              text,
              style: addMedSans(context, size: 12, color: ink, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

/// The ringed `!` used by every notice and by the failure sheet.
class AddMedBangGlyph extends StatelessWidget {
  const AddMedBangGlyph({
    super.key,
    required this.size,
    required this.color,
    this.borderWidth = 1.4,
  });

  final double size;
  final Color color;
  final double borderWidth;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color, width: borderWidth),
      ),
      child: Text(
        '!',
        textAlign: TextAlign.center,
        textScaler: TextScaler.noScaling,
        style: addMedSans(
          context,
          size: size * 0.66,
          weight: FontWeight.w700,
          color: color,
          height: 1.0,
        ),
      ),
    );
  }
}

// ── Object glyphs ────────────────────────────────────────────────────────────

/// The prototype's capsule: a rounded pill split down the middle, teal on the
/// left and pale on the right, tilted `-20°`.
///
/// The tilt is applied by the caller so the preview stage can animate it.
class AddMedCapsuleGlyph extends StatelessWidget {
  const AddMedCapsuleGlyph({
    super.key,
    required this.width,
    required this.height,
    this.lit = false,
  });

  final double width;
  final double height;

  /// The larger preview capsule carries `inset` highlights and a teal bloom;
  /// the small one on the type card carries only the inset pair.
  final bool lit;

  @override
  Widget build(BuildContext context) {
    final theme = AddMedTheme.of(context);
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(height),
        boxShadow: lit
            ? [
                BoxShadow(
                  color: theme.shadowColor.withValues(
                    alpha: theme.isDark ? 0.45 : 0.16,
                  ),
                  blurRadius: 18,
                  offset: const Offset(0, 12),
                ),
                BoxShadow(color: theme.glow, blurRadius: 22),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(height),
        child: Stack(
          children: [
            Row(
              children: const [
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: AddMedTheme.capsuleTeal,
                    ),
                  ),
                ),
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: AddMedTheme.capsulePale,
                    ),
                  ),
                ),
              ],
            ),
            // `inset 0 2px 5px rgba(255,255,255,0.5)` over
            // `inset 0 -6px 10px rgba(0,0,0,0.3)`.
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: 0.34),
                      Colors.white.withValues(alpha: 0),
                      Colors.black.withValues(alpha: 0.26),
                    ],
                    stops: const [0.0, 0.42, 1.0],
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

/// The prototype's syrup bottle: a translucent body with an amber fill in the
/// lower 58% and, at preview size, a soft highlight down its left shoulder.
class AddMedBottleGlyph extends StatelessWidget {
  const AddMedBottleGlyph({
    super.key,
    required this.width,
    required this.height,
    this.lit = false,
  });

  final double width;
  final double height;
  final bool lit;

  @override
  Widget build(BuildContext context) {
    final theme = AddMedTheme.of(context);
    final radius = BorderRadius.vertical(
      top: Radius.circular(width * 0.31),
      bottom: Radius.circular(width * 0.38),
    );

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: lit
            ? [
                BoxShadow(
                  color: theme.shadowColor.withValues(
                    alpha: theme.isDark ? 0.45 : 0.16,
                  ),
                  blurRadius: 18,
                  offset: const Offset(0, 12),
                ),
                BoxShadow(color: theme.glow, blurRadius: 20),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: lit ? 0.18 : 0.14),
            border: Border.all(
              color: Colors.white.withValues(alpha: lit ? 0.35 : 0.30),
            ),
            borderRadius: radius,
          ),
          child: Stack(
            children: [
              Align(
                alignment: Alignment.bottomCenter,
                child: FractionallySizedBox(
                  heightFactor: 0.58,
                  widthFactor: 1,
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: AddMedTheme.syrupFill,
                    ),
                  ),
                ),
              ),
              if (lit)
                Positioned(
                  left: width * 0.23,
                  top: height * 0.13,
                  width: width * 0.19,
                  height: height * 0.39,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(4),
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

// ── Schedule preview card ────────────────────────────────────────────────────

/// The screen's hero: a glass card that restates, live, what will be saved —
/// the medication object on its orbit stage, its name and meta line, a 24-hour
/// rule with the reminder dots on it and the NOW marker, and one chip per
/// reminder.
class AddMedSchedulePreview extends StatelessWidget {
  const AddMedSchedulePreview({
    super.key,
    required this.name,
    required this.meta,
    required this.isPill,
    required this.ready,
    required this.minutes,
    required this.nowMinutes,
    required this.scroll,
  });

  /// Null renders the placeholder `New medication` in faint ink.
  final String? name;

  final String meta;
  final bool isPill;
  final bool ready;

  /// Reminder times as minutes past midnight, in row order.
  final List<int> minutes;

  /// Where the NOW marker sits, as minutes past midnight.
  final int nowMinutes;

  /// Drives the prototype's scroll-linked recession
  /// (`translateY(y * .16) translateZ(-k * 40)` with a fading opacity).
  final ScrollController scroll;

  @override
  Widget build(BuildContext context) {
    final theme = AddMedTheme.of(context);

    return AnimatedBuilder(
      animation: scroll,
      builder: (context, child) {
        final y = scroll.hasClients ? scroll.offset : 0.0;
        if (y <= 0) return child!;
        final k = math.min(1.0, y / 260);
        return Opacity(
          opacity: math.max(0.15, 1 - y / 300),
          child: Transform.translate(
            offset: Offset(0, y * 0.16),
            child: Transform.scale(scale: 1 - k * 0.045, child: child),
          ),
        );
      },
      child: AddMedGlass(
        radius: 22,
        specular: true,
        padding: const EdgeInsets.fromLTRB(16, 15, 16, 17),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'SCHEDULE PREVIEW',
                    style: addMedMono(
                      context,
                      size: 9.5,
                      em: 0.2,
                      color: theme.txt2,
                    ),
                  ),
                ),
                _StatusPill(ready: ready),
              ],
            ),
            const SizedBox(height: 13),
            Row(
              children: [
                _PreviewStage(isPill: isPill),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name ?? 'New medication',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: addMedSans(
                          context,
                          size: 18,
                          weight: FontWeight.w600,
                          em: -0.02,
                          color: name == null ? theme.txt3 : theme.txt,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        meta,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: addMedSans(
                          context,
                          size: 12.5,
                          color: theme.txt2,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _DayRule(minutes: minutes, nowMinutes: nowMinutes),
            const SizedBox(height: 13),
            _PreviewChips(minutes: minutes),
          ],
        ),
      ),
    );
  }
}

/// `NOT SET` / `READY` — a dashed capsule that goes solid and teal once every
/// required detail is present.
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.ready});

  final bool ready;

  @override
  Widget build(BuildContext context) {
    final theme = AddMedTheme.of(context);
    final ink = ready ? theme.accent : theme.txt2;
    final line = ready ? theme.accent.withValues(alpha: 0.4) : theme.bd;

    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: ready ? theme.accent : theme.txt3,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            ready ? 'READY' : 'NOT SET',
            style: addMedMono(context, size: 9, em: 0.12, color: ink),
          ),
        ],
      ),
    );

    return AnimatedScale(
      scale: 1,
      duration: Duration.zero,
      child: ready
          ? DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: line),
              ),
              child: content,
            )
          : CustomPaint(
              painter: AddMedDashedBorderPainter(color: line, radius: 999),
              child: content,
            ),
    );
  }
}

/// The 64×62 orbit stage: two projected rings, a contact shadow and the
/// medication object floating above it.
class _PreviewStage extends StatelessWidget {
  const _PreviewStage({required this.isPill});

  final bool isPill;

  @override
  Widget build(BuildContext context) {
    final theme = AddMedTheme.of(context);

    return SizedBox(
      width: 64,
      height: 62,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // `fm-ringA 13s linear infinite` — a 60px ring under
          // `rotateX(74deg)`, carrying one lit node.
          Positioned(
            left: 2,
            top: 12,
            width: 60,
            height: 60,
            child: AmbientLoop(
              period: const Duration(seconds: 13),
              restT: 0.12,
              builder: (context, t, _) => CustomPaint(
                painter: _OrbitRingPainter(
                  color: theme.accent.withValues(alpha: 0.24),
                  nodeColor: theme.accent,
                  tiltCos: math.cos(74 * math.pi / 180),
                  phase: t,
                  dashed: false,
                ),
              ),
            ),
          ),
          // `fm-ringB 19s linear infinite` — a 42px dashed ring, counter-rotating.
          Positioned(
            left: 11,
            top: 21,
            width: 42,
            height: 42,
            child: AmbientLoop(
              period: const Duration(seconds: 19),
              restT: 0.4,
              builder: (context, t, _) => CustomPaint(
                painter: _OrbitRingPainter(
                  color: theme.bdSoft,
                  nodeColor: null,
                  tiltCos: math.cos(64 * math.pi / 180),
                  phase: 1 - t,
                  dashed: true,
                ),
              ),
            ),
          ),
          // `fm-contact 6s` — the ground shadow breathing under the object.
          Positioned(
            left: 13,
            bottom: 4,
            width: 38,
            height: 7,
            child: AmbientLoop(
              period: const Duration(seconds: 6),
              restT: 0.5,
              builder: (context, t, child) => Opacity(
                opacity: pingPongBetween(t, 0.55, 0.30),
                child: Transform.scale(
                  scaleX: pingPongBetween(t, 1.0, 0.82),
                  child: child,
                ),
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: theme.bloom(
                    Colors.black.withValues(alpha: theme.isDark ? 0.55 : 0.22),
                  ),
                ),
              ),
            ),
          ),
          if (isPill)
            // `fm-float3 6s` — rocks between -20° and -13° while rising 6px.
            Positioned(
              left: 8,
              top: 20,
              child: AmbientLoop(
                period: const Duration(seconds: 6),
                restT: 0,
                builder: (context, t, child) => Transform.translate(
                  offset: Offset(0, pingPongBetween(t, 0, -6)),
                  child: Transform.rotate(
                    angle: pingPongBetween(t, -20, -13) * math.pi / 180,
                    child: child,
                  ),
                ),
                child: const AddMedCapsuleGlyph(
                  width: 48,
                  height: 23,
                  lit: true,
                ),
              ),
            )
          else
            // `fm-bob3 5.6s` — rocks between -3° and +3° while rising 5px.
            Positioned(
              left: 19,
              top: 13,
              child: AmbientLoop(
                period: const Duration(milliseconds: 5600),
                restT: 0.5,
                builder: (context, t, child) => Transform.translate(
                  offset: Offset(0, pingPongBetween(t, 0, -5)),
                  child: Transform.rotate(
                    angle: pingPongBetween(t, -3, 3) * math.pi / 180,
                    child: child,
                  ),
                ),
                child: const AddMedBottleGlyph(
                  width: 26,
                  height: 38,
                  lit: true,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A circle under `rotateX(θ)`, i.e. an ellipse whose height is the circle's
/// diameter times `cos θ`, optionally carrying one lit node travelling round it.
class _OrbitRingPainter extends CustomPainter {
  const _OrbitRingPainter({
    required this.color,
    required this.nodeColor,
    required this.tiltCos,
    required this.phase,
    required this.dashed,
  });

  final Color color;
  final Color? nodeColor;
  final double tiltCos;
  final double phase;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final rx = size.width / 2;
    final ry = size.height / 2 * tiltCos;
    final center = Offset(size.width / 2, size.height / 2);
    final rect = Rect.fromCenter(
      center: center,
      width: rx * 2,
      height: ry * 2,
    );

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = color;

    if (dashed) {
      for (final metric in (Path()..addOval(rect)).computeMetrics()) {
        var d = 0.0;
        while (d < metric.length) {
          final end = math.min(d + 3, metric.length);
          canvas.drawPath(metric.extractPath(d, end), stroke);
          d = end + 3;
        }
      }
    } else {
      canvas.drawOval(rect, stroke);
    }

    final node = nodeColor;
    if (node == null) return;
    final angle = phase * 2 * math.pi;
    final at = Offset(
      center.dx + rx * math.cos(angle),
      center.dy + ry * math.sin(angle),
    );
    // `box-shadow: 0 0 8px var(--accent)`.
    canvas.drawCircle(
      at,
      6,
      Paint()..color = node.withValues(alpha: 0.35),
    );
    canvas.drawCircle(at, 2.5, Paint()..color = node);
  }

  @override
  bool shouldRepaint(covariant _OrbitRingPainter old) =>
      old.phase != phase || old.color != color || old.nodeColor != nodeColor;
}

/// The 24-hour rule: a 3px track carrying the NOW marker and one lit dot per
/// reminder, with the `12 AM · 6 AM · 12 PM · 6 PM · 12 AM` scale beneath.
class _DayRule extends StatelessWidget {
  const _DayRule({required this.minutes, required this.nowMinutes});

  final List<int> minutes;
  final int nowMinutes;

  @override
  Widget build(BuildContext context) {
    final theme = AddMedTheme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The marker's label sits 25px above the track; the dots overhang it by
        // 4.5px. The padded box is what reserves that room inside the card.
        SizedBox(
          height: 3,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: theme.bdSoft,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  Positioned(
                    left: w * (nowMinutes / 1440) - 0.75,
                    top: -9,
                    child: AmbientLoop(
                      period: const Duration(milliseconds: 3400),
                      restT: 0.5,
                      builder: (context, t, child) => Opacity(
                        opacity: pingPongBetween(t, 0.35, 0.9),
                        child: Transform.scale(
                          scaleY: pingPongBetween(t, 1.0, 1.3),
                          child: child,
                        ),
                      ),
                      child: Container(
                        width: 1.5,
                        height: 21,
                        decoration: BoxDecoration(
                          color: theme.txt2,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: w * (nowMinutes / 1440) - 20,
                    top: -25,
                    width: 40,
                    child: Text(
                      'NOW',
                      textAlign: TextAlign.center,
                      style: addMedMono(
                        context,
                        size: 7.5,
                        em: 0.1,
                        color: theme.txt3,
                      ),
                    ),
                  ),
                  for (final m in minutes)
                    Positioned(
                      left: w * (m / 1440) - 6,
                      top: -4.5,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: theme.accent,
                          boxShadow: [
                            BoxShadow(color: theme.glow, blurRadius: 10),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 9),
        // The prototype prints five scale marks. At a large text scale five no
        // longer fit across a phone, so the axis drops to its quarter marks
        // rather than overflowing or shrinking the type.
        LayoutBuilder(
          builder: (context, constraints) {
            final style = addMedMono(
              context,
              size: 8.5,
              em: 0.1,
              color: theme.txt3,
            );
            final probe = TextPainter(
              text: TextSpan(text: '12 AM', style: style),
              textDirection: Directionality.of(context),
              textScaler: MediaQuery.textScalerOf(context),
            )..layout();
            final labels = probe.width * 5 + 16 <= constraints.maxWidth
                ? const ['12 AM', '6 AM', '12 PM', '6 PM', '12 AM']
                : const ['12 AM', '12 PM', '12 AM'];
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final label in labels) Text(label, style: style),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// One mono chip per reminder time, or the dashed `No reminders yet`.
class _PreviewChips extends StatelessWidget {
  const _PreviewChips({required this.minutes});

  final List<int> minutes;

  @override
  Widget build(BuildContext context) {
    final theme = AddMedTheme.of(context);

    if (minutes.isEmpty) {
      return CustomPaint(
        painter: AddMedDashedBorderPainter(color: theme.bd, radius: 10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(
            'No reminders yet',
            style: addMedMono(context, size: 11, color: theme.txt3),
          ),
        ),
      );
    }

    return Wrap(
      spacing: 7,
      runSpacing: 7,
      children: [
        for (final m in minutes)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: theme.accSoft,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: theme.accent.withValues(alpha: 0.32)),
            ),
            child: Text(
              addMedFormatTime(m),
              style: addMedMono(context, size: 11, color: theme.accent),
            ),
          ),
      ],
    );
  }
}

// ── Fields ───────────────────────────────────────────────────────────────────

/// The prototype's input surface: a `--field` slab with a mono caption above
/// the value, turning `--errSoft` / `--err` while a validation message is
/// showing.
class AddMedFieldShell extends StatelessWidget {
  const AddMedFieldShell({
    super.key,
    required this.child,
    required this.hasError,
    this.padding = const EdgeInsets.fromLTRB(15, 12, 15, 13),
  });

  final Widget child;
  final bool hasError;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final theme = AddMedTheme.of(context);
    return AddMedGlass(
      radius: 18,
      padding: padding,
      shadow: const [],
      solidFill: hasError ? theme.errSoft : theme.field,
      borderColor: hasError ? theme.err : theme.fieldBd,
      child: child,
    );
  }
}

/// `NAME *` — the mono caption inside a field, with the accent asterisk the
/// prototype gives required fields.
class AddMedFieldLabel extends StatelessWidget {
  const AddMedFieldLabel(this.text, {super.key, this.required = false});

  final String text;
  final bool required;

  @override
  Widget build(BuildContext context) {
    final theme = AddMedTheme.of(context);
    return Text.rich(
      TextSpan(
        text: text,
        children: required
            ? [
                TextSpan(
                  text: '  *',
                  style: addMedMono(
                    context,
                    size: 9.5,
                    em: 0.14,
                    color: theme.accent,
                  ),
                ),
              ]
            : null,
      ),
      style: addMedMono(context, size: 9.5, em: 0.14, color: theme.txt2),
    );
  }
}

/// The prototype's bare input: no border, no fill, no Material decoration —
/// the surrounding [AddMedFieldShell] is the field.
class AddMedInput extends StatelessWidget {
  const AddMedInput({
    super.key,
    required this.controller,
    required this.hintText,
    required this.fontSize,
    this.focusNode,
    this.mono = false,
    this.keyboardType,
    this.textInputAction = TextInputAction.next,
    this.inputFormatters,
    this.textCapitalization = TextCapitalization.sentences,
    this.onChanged,
    this.onSubmitted,
    this.semanticLabel,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final String hintText;
  final double fontSize;
  final bool mono;
  final TextInputType? keyboardType;
  final TextInputAction textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final TextCapitalization textCapitalization;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = AddMedTheme.of(context);
    final style = mono
        ? addMedMono(
            context,
            size: fontSize,
            color: theme.txt,
            weight: FontWeight.w500,
            height: 1.3,
          )
        : addMedSans(
            context,
            size: fontSize,
            color: theme.txt,
            weight: FontWeight.w500,
            em: -0.01,
            height: 1.3,
          );

    return TextField(
      controller: controller,
      focusNode: focusNode,
      style: style,
      cursorColor: theme.accent,
      cursorWidth: 1.5,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      inputFormatters: inputFormatters,
      textCapitalization: textCapitalization,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        isDense: true,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        contentPadding: const EdgeInsets.only(top: 5),
        hintText: hintText,
        hintStyle: style.copyWith(color: theme.txt3),
      ),
    );
  }
}

// ── Selection controls ───────────────────────────────────────────────────────

/// `Pill` / `Syrup` — a glass card carrying the object glyph, its name, and a
/// filled tick once selected.
class AddMedTypeCard extends StatelessWidget {
  const AddMedTypeCard({
    super.key,
    required this.label,
    required this.selected,
    required this.isPill,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool isPill;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = AddMedTheme.of(context);

    return AddMedGlass(
      onTap: onTap,
      radius: 16,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      pressedScale: 0.98,
      fill: selected ? theme.lgTeal : theme.lg,
      borderColor: selected ? theme.accent.withValues(alpha: 0.5) : theme.bd,
      shadow: selected ? theme.selectedCardShadow : theme.cardShadow,
      semanticLabel: label,
      semanticSelected: selected,
      child: Row(
        children: [
          SizedBox(
            width: 26,
            height: 22,
            child: Center(
              child: isPill
                  ? Transform.rotate(
                      angle: -20 * math.pi / 180,
                      child: const AddMedCapsuleGlyph(width: 26, height: 14),
                    )
                  : const AddMedBottleGlyph(width: 15, height: 21),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: addMedSans(
                context,
                size: 14,
                weight: FontWeight.w600,
                color: theme.txt,
              ),
            ),
          ),
          if (selected)
            Container(
              width: 18,
              height: 18,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.accent,
              ),
              child: Icon(Icons.check_rounded, size: 12, color: theme.onAccent),
            ),
        ],
      ),
    );
  }
}

/// `mg` / `ml` / `pills` — the dose unit selector beside the amount.
class AddMedUnitButton extends StatelessWidget {
  const AddMedUnitButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = AddMedTheme.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          constraints: const BoxConstraints(minWidth: 44, minHeight: 34),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: selected ? theme.accSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: selected ? theme.accent.withValues(alpha: 0.4) : theme.bd,
            ),
          ),
          // `widthFactor`/`heightFactor` keep the box the size of its label —
          // a bare `alignment` would let it swell to whatever width the parent
          // offers, which is what a `Wrap` or a `Column` hands it.
          child: Center(
            widthFactor: 1,
            heightFactor: 1,
            child: Text(
              label,
              style: addMedMono(
                context,
                size: 12,
                color: selected ? theme.accent : theme.txt2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// `Once / Twice / Thrice daily` — a glass card with one dot per reminder and a
/// mono count beneath.
class AddMedFrequencyCard extends StatelessWidget {
  const AddMedFrequencyCard({
    super.key,
    required this.title,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = AddMedTheme.of(context);
    final ink = selected ? theme.accent : theme.txt3;

    return AnimatedSlide(
      offset: selected ? const Offset(0, -0.012) : Offset.zero,
      duration: const Duration(milliseconds: 250),
      curve: const Cubic(0.2, 0.8, 0.2, 1),
      child: AddMedGlass(
        onTap: onTap,
        radius: 18,
        padding: const EdgeInsets.fromLTRB(10, 13, 10, 12),
        pressedScale: 0.97,
        fill: selected ? theme.lgTeal : theme.lg,
        borderColor: selected ? theme.accent.withValues(alpha: 0.55) : theme.bd,
        shadow: selected ? theme.selectedCardShadow : theme.cardShadow,
        semanticLabel: '$title daily',
        semanticSelected: selected,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: addMedSans(
                context,
                size: 15,
                weight: FontWeight.w600,
                em: -0.01,
                color: theme.txt,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              'daily',
              textAlign: TextAlign.center,
              style: addMedSans(context, size: 11.5, color: theme.txt2),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < count; i++) ...[
                  if (i > 0) const SizedBox(width: 4),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: ink),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Text(
              count == 1 ? '1 REMINDER' : '$count REMINDERS',
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: addMedMono(context, size: 8.5, em: 0.1, color: ink),
            ),
          ],
        ),
      ),
    );
  }
}

/// A bordered pill used for the medication-name suggestions and (in the time
/// picker) the time presets. Teal once its value is the one in the field.
class AddMedTagChip extends StatelessWidget {
  const AddMedTagChip({
    super.key,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.minHeight = 34,
  });

  final String label;
  final VoidCallback onTap;
  final bool selected;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    final theme = AddMedTheme.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          constraints: BoxConstraints(minHeight: minHeight),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? theme.accSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: selected ? theme.accent.withValues(alpha: 0.4) : theme.bd,
            ),
          ),
          // See the note on [AddMedUnitButton]: the factors are what keep the
          // chip the width of its label inside a `Wrap`.
          child: Center(
            widthFactor: 1,
            heightFactor: 1,
            child: Text(
              label,
              style: addMedSans(
                context,
                size: 12,
                color: selected ? theme.accent : theme.txt2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Reminder rows ────────────────────────────────────────────────────────────

/// One reminder: its ordinal in an accent tile, the time in mono, the slot and
/// part of day beneath it, a `Change` button and — when more than one reminder
/// exists — a remove control.
///
/// A row whose time collides with another turns amber and says so, which is the
/// prototype's own warning and the reason the row is not simply a list tile.
class AddMedReminderRow extends StatelessWidget {
  const AddMedReminderRow({
    super.key,
    required this.index,
    required this.minutes,
    required this.duplicate,
    required this.onChange,
    this.onRemove,
  });

  final int index;
  final int minutes;
  final bool duplicate;
  final VoidCallback onChange;
  final VoidCallback? onRemove;

  static const _slots = ['First dose', 'Second dose', 'Third dose'];

  @override
  Widget build(BuildContext context) {
    final theme = AddMedTheme.of(context);
    final time = addMedFormatTime(minutes);
    final subtitle = duplicate
        ? 'Same time as another reminder'
        : '${_slots[index]} · ${addMedPartOfDay(minutes)}';

    return AddMedGlass(
      radius: 18,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      specular: true,
      borderColor: duplicate ? theme.warn.withValues(alpha: 0.5) : theme.bd,
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.accSoft,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.accent.withValues(alpha: 0.3)),
            ),
            child: Text(
              '${index + 1}',
              style: addMedMono(context, size: 12, color: theme.accent),
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  time,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: addMedMono(
                    context,
                    size: 18,
                    em: -0.01,
                    weight: FontWeight.w500,
                    color: theme.txt,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: addMedSans(
                    context,
                    size: 11,
                    color: duplicate ? theme.warn : theme.txt2,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _RowButton(
            label: 'Change',
            semanticLabel: 'Change reminder ${index + 1}, currently $time',
            onTap: onChange,
          ),
          if (onRemove != null)
            Semantics(
              button: true,
              label: 'Remove reminder ${index + 1}',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onRemove,
                child: SizedBox(
                  width: 34,
                  height: 44,
                  child: Center(
                    child: Container(
                      width: 12,
                      height: 1.6,
                      decoration: BoxDecoration(
                        color: theme.txt2,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The row's `Change` control: a `--field` capsule at the prototype's 44dp
/// tap height.
class _RowButton extends StatelessWidget {
  const _RowButton({
    required this.label,
    required this.onTap,
    required this.semanticLabel,
  });

  final String label;
  final VoidCallback onTap;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = AddMedTheme.of(context);
    return AddMedGlass(
      onTap: onTap,
      radius: 14,
      blur: 8,
      shadow: const [],
      solidFill: theme.field,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      pressedScale: 0.94,
      sinkY: 0,
      semanticLabel: semanticLabel,
      child: SizedBox(
        height: 42,
        child: Center(
          child: Text(
            label,
            style: addMedSans(
              context,
              size: 12.5,
              weight: FontWeight.w500,
              color: theme.txt,
            ),
          ),
        ),
      ),
    );
  }
}

/// The dashed `+ Add a second/third reminder` button under the rows.
class AddMedAddTimeButton extends StatelessWidget {
  const AddMedAddTimeButton({
    super.key,
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = AddMedTheme.of(context);
    return AddMedGlass(
      onTap: onTap,
      radius: 16,
      blur: 0,
      rim: false,
      shadow: const [],
      solidFill: Colors.transparent,
      dashedBorder: true,
      borderColor: theme.bd,
      pressedScale: 0.985,
      sinkY: 0,
      padding: EdgeInsets.zero,
      semanticLabel: label,
      child: SizedBox(
        height: 50,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_rounded, size: 16, color: theme.txt2),
            const SizedBox(width: 9),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: addMedSans(
                  context,
                  size: 13,
                  weight: FontWeight.w500,
                  color: theme.txt2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The dashed placeholder shown before a frequency is chosen.
class AddMedReminderEmpty extends StatelessWidget {
  const AddMedReminderEmpty({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = AddMedTheme.of(context);
    return AddMedGlass(
      radius: 18,
      blur: 0,
      shadow: const [],
      solidFill: theme.field,
      dashedBorder: true,
      borderColor: theme.bd,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: theme.txt3, width: 1.4),
            ),
            child: Icon(Icons.add_rounded, size: 14, color: theme.txt3),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Pick how often above and ForeSeeMe suggests the reminder '
              'times — you can change every one.',
              style: addMedSans(
                context,
                size: 12.5,
                color: theme.txt2,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Standing notes ───────────────────────────────────────────────────────────

/// The dashed `WHEN YOU SAVE` panel that closes the form.
class AddMedSaveNotes extends StatelessWidget {
  const AddMedSaveNotes({super.key, required this.reminderNote});

  final String reminderNote;

  @override
  Widget build(BuildContext context) {
    final theme = AddMedTheme.of(context);

    Widget line(String text) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.accent,
              ),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: addMedSans(
                context,
                size: 12.5,
                color: theme.txt2,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );

    return AddMedGlass(
      radius: 18,
      blur: 0,
      shadow: const [],
      solidFill: theme.field,
      dashedBorder: true,
      borderColor: theme.bd,
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'WHEN YOU SAVE',
            style: addMedMono(context, size: 9, em: 0.18, color: theme.txt2),
          ),
          const SizedBox(height: 3),
          line('Added to your medication list'),
          line(reminderNote),
          line('Doses appear in your Daily Check-In'),
        ],
      ),
    );
  }
}

/// The edit-only archive control: an amber-outlined row that stops reminders
/// without touching adherence history.
class AddMedArchiveButton extends StatelessWidget {
  const AddMedArchiveButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = AddMedTheme.of(context);
    return AddMedGlass(
      onTap: onTap,
      radius: 18,
      blur: 0,
      rim: false,
      shadow: const [],
      solidFill: Colors.transparent,
      borderColor: theme.warn.withValues(alpha: 0.34),
      pressedScale: 0.985,
      sinkY: 0,
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
      semanticLabel: 'Archive medication',
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: theme.warn.withValues(alpha: 0.4)),
            ),
            child: Icon(Icons.inventory_2_outlined, size: 15, color: theme.warn),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Archive medication',
                  style: addMedSans(
                    context,
                    size: 14,
                    weight: FontWeight.w600,
                    color: theme.txt,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Stops reminders, keeps your adherence history',
                  style: addMedSans(
                    context,
                    size: 11.5,
                    color: theme.txt2,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Footer ───────────────────────────────────────────────────────────────────

/// The readiness readout and its four progress ticks — one per required detail
/// (name, dose, frequency, times).
class AddMedReadyRow extends StatelessWidget {
  const AddMedReadyRow({
    super.key,
    required this.label,
    required this.ready,
    required this.satisfied,
  });

  final String label;
  final bool ready;

  /// One flag per required detail, in the prototype's order.
  final List<bool> satisfied;

  @override
  Widget build(BuildContext context) {
    final theme = AddMedTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 9),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: addMedMono(
                context,
                size: 9.5,
                em: 0.14,
                color: ready ? theme.accent : theme.txt2,
              ),
            ),
          ),
          const SizedBox(width: 8),
          for (var i = 0; i < satisfied.length; i++) ...[
            if (i > 0) const SizedBox(width: 5),
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: 16,
              height: 3,
              decoration: BoxDecoration(
                color: satisfied[i] ? theme.accent : theme.bdSoft,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The primary action: glass and quiet until every required detail is present,
/// then a solid accent slab with a slow shimmer sweeping across it.
///
/// While saving it carries an indeterminate progress bar behind the label and a
/// spinner beside it, exactly as the prototype does.
class AddMedCta extends StatelessWidget {
  const AddMedCta({
    super.key,
    required this.label,
    required this.ready,
    required this.saving,
    required this.progress,
    required this.onTap,
    required this.shake,
  });

  final String label;
  final bool ready;
  final bool saving;

  /// `0..1`, the prototype's `[data-cta-bar]` width.
  final double progress;

  final VoidCallback onTap;

  /// Increments each time submission is refused, which replays the prototype's
  /// `fm-shake` on the button.
  final int shake;

  @override
  Widget build(BuildContext context) {
    final theme = AddMedTheme.of(context);
    final ink = ready ? theme.onAccent : theme.txt2;

    final button = AddMedGlass(
      onTap: saving ? null : onTap,
      radius: 20,
      padding: EdgeInsets.zero,
      pressedScale: 0.99,
      sinkY: 3,
      solidFill: ready ? theme.accent : null,
      borderColor: ready ? Colors.transparent : theme.bd,
      shadow: ready ? theme.ctaReadyShadow : theme.ctaShadow,
      rim: !ready,
      semanticLabel: label,
      underlay: Stack(
        children: [
          if (progress > 0)
            AnimatedFractionallySizedBox(
              duration: const Duration(milliseconds: 500),
              widthFactor: progress,
              heightFactor: 1,
              alignment: Alignment.centerLeft,
              child: ColoredBox(
                color: Colors.white.withValues(alpha: 0.16),
              ),
            ),
          if (ready && !saving)
            Positioned.fill(
              child: AmbientLoop(
                period: const Duration(milliseconds: 3600),
                restT: 0,
                builder: (context, t, child) {
                  // `fm-shimmer`: the band crosses in the first 55% of the
                  // cycle and waits out the rest.
                  final progress = (t / 0.55).clamp(0.0, 1.0);
                  return FractionalTranslation(
                    translation: Offset(-1.4 + progress * 4.6, 0),
                    child: child,
                  );
                },
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: 68,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.white.withValues(alpha: 0),
                            Colors.white.withValues(alpha: 0.42),
                            Colors.white.withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      child: SizedBox(
        height: 56,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (saving) ...[
              SizedBox(
                width: 17,
                height: 17,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(ink),
                ),
              ),
              const SizedBox(width: 10),
            ],
            Flexible(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: addMedSans(
                    context,
                    size: 16,
                    weight: FontWeight.w600,
                    em: -0.01,
                    color: ink,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (shake == 0) return button;
    return TweenAnimationBuilder<double>(
      key: ValueKey<int>(shake),
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 420),
      builder: (context, t, child) {
        if (AppMotion.reduceMotion(context) || t == 1) return child!;
        // `fm-shake`: -4, +4, -2, +2, settling at 0.
        final dx = math.sin(t * math.pi * 4) * 4 * (1 - t);
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: button,
    );
  }
}

// ── Shared formatting ────────────────────────────────────────────────────────

/// `08:00 AM` — the prototype's `fmt(mins)`, zero-padded on the hour.
String addMedFormatTime(int minutes) {
  final h24 = minutes ~/ 60;
  final mm = minutes % 60;
  final period = h24 < 12 ? 'AM' : 'PM';
  var h = h24 % 12;
  if (h == 0) h = 12;
  return '${h.toString().padLeft(2, '0')}:${mm.toString().padLeft(2, '0')} '
      '$period';
}

/// The prototype's `partOfDay(mins)`.
String addMedPartOfDay(int minutes) {
  if (minutes < 300) return 'night';
  if (minutes < 720) return 'morning';
  if (minutes < 1020) return 'afternoon';
  if (minutes < 1290) return 'evening';
  return 'night';
}
