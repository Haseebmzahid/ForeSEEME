import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:fyp_foreseeme/core/theme/a11y.dart';
import 'package:fyp_foreseeme/core/widgets/app_motion.dart';

import 'profile_hub_motion.dart';
import 'profile_hub_style.dart';

/// Chrome for the Profile Hub, transcribed from the approved prototype
/// (`docs/Design/ForeSeeMe Profile Hub (1).html`).
///
/// Every widget here is presentation only — it takes values and callbacks and
/// owns no state, no provider and no navigation decision. Scope is the Profile
/// Hub; nothing else in the app imports this file.

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
class HubSlab extends StatefulWidget {
  const HubSlab({
    super.key,
    required this.child,
    this.onTap,
    this.radius = 20,
    this.padding = const EdgeInsets.all(15),
    this.pressedScale = 0.982,
    this.blur = 18,
    this.saturate = false,
    this.quiet = false,
    this.underlay,
    this.semanticLabel,
    this.semanticHint,
    this.expanded,
  });

  final Widget child;

  /// Null renders an inert slab with no press feedback and no button semantics.
  final VoidCallback? onTap;

  final double radius;
  final EdgeInsets padding;

  /// The prototype varies this per card (`.986` for the wide cards, `.982` for
  /// the grid cards, `.988` for the admin slab).
  final double pressedScale;

  final double blur;

  /// The Health Profile card alone carries `saturate(140%)`; Flutter's
  /// [BackdropFilter] has no saturation stage, so the extra vividness is
  /// approximated by lifting the fill slightly. See [_fill].
  final bool saturate;

  /// The About card's quieter `--glass → transparent` fill.
  final bool quiet;

  /// Ornament painted **inside** the slab's clip and **behind** its content —
  /// the prototype's absolutely-positioned first children under
  /// `overflow: hidden` (the Health Profile card's corner bloom, the Help
  /// Center sweep, the admin slab's scanlines and brackets). Passing them here
  /// rather than stacking them outside the slab is what keeps them clipped to
  /// its corner radius, as the prototype clips them.
  final Widget? underlay;

  final String? semanticLabel;
  final String? semanticHint;

  /// Announced on the expandable card so screen readers hear its state.
  final bool? expanded;

  @override
  State<HubSlab> createState() => _HubSlabState();
}

class _HubSlabState extends State<HubSlab> {
  bool _pressed = false;

  bool get _interactive => widget.onTap != null;

  void _set(bool value) {
    if (!_interactive || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ProfileHubTheme.of(context);
    final opaque = A11y.reduceTransparency(context);
    final reduceMotion = AppMotion.reduceMotion(context);
    final pressed = _pressed && _interactive;

    // `transition: transform .25s cubic-bezier(.2,.8,.2,1), box-shadow .25s`.
    const duration = Duration(milliseconds: 250);
    const curve = Cubic(0.2, 0.8, 0.2, 1);

    final slab = AnimatedContainer(
      duration: reduceMotion ? Duration.zero : duration,
      curve: curve,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.radius),
        boxShadow: pressed
            // `box-shadow: inset 0 1px 0 var(--hi), 0 10px 20px rgba(0,0,0,.45)`
            ? [
                BoxShadow(
                  color: theme.shadowColor.withValues(
                    alpha: theme.isDark ? 0.45 : 0.12,
                  ),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ]
            : theme.slabShadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.radius),
        child: BackdropFilter(
          filter: hubBlur(context, widget.blur),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.radius),
              gradient: opaque ? null : _fill(theme),
              color: opaque ? theme.bg2 : null,
              border: Border.all(color: opaque ? theme.txt2 : theme.line),
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
                Padding(padding: widget.padding, child: widget.child),
              ],
            ),
          ),
        ),
      ),
    );

    // `transform: translateY(3px) scale(.98x)`.
    final moved = AnimatedScale(
      scale: (pressed && !reduceMotion) ? widget.pressedScale : 1.0,
      duration: reduceMotion ? Duration.zero : duration,
      curve: curve,
      child: AnimatedSlide(
        offset: (pressed && !reduceMotion)
            ? const Offset(0, 0.012)
            : Offset.zero,
        duration: reduceMotion ? Duration.zero : duration,
        curve: curve,
        child: slab,
      ),
    );

    if (!_interactive) return moved;

    return Semantics(
      button: true,
      label: widget.semanticLabel,
      hint: widget.semanticHint,
      expanded: widget.expanded,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _set(true),
        onTapUp: (_) => _set(false),
        onTapCancel: () => _set(false),
        onTap: widget.onTap,
        child: moved,
      ),
    );
  }

  Gradient _fill(ProfileHubTheme theme) {
    if (widget.quiet) return theme.slabFillQuiet;
    if (!widget.saturate) return theme.slabFill;
    // Stand-in for `saturate(140%)`: the same two stops, each a touch more
    // present, so the one card the prototype saturates still reads as the
    // richest surface on the screen.
    final base = theme.slabFill;
    return LinearGradient(
      begin: base.begin,
      end: base.end,
      colors: [
        Color.lerp(theme.glass2, theme.accent, theme.isDark ? 0.05 : 0.03)!,
        theme.glass,
      ],
    );
  }
}

// ── Section: theme switcher ──────────────────────────────────────────────────

/// The prototype's two-up theme segmented control, with its sliding knob.
///
/// The knob is a real sliding pane (`transition: transform .42s
/// cubic-bezier(.2,.9,.2,1)`), not a Material [Switch] or [SegmentedButton] —
/// either would replace the prototype's motion and geometry wholesale.
class HubThemeSwitch extends StatelessWidget {
  const HubThemeSwitch({
    super.key,
    required this.isDarkSelected,
    required this.onDark,
    required this.onLight,
  });

  final bool isDarkSelected;
  final VoidCallback onDark;
  final VoidCallback onLight;

  @override
  Widget build(BuildContext context) {
    final theme = ProfileHubTheme.of(context);
    final opaque = A11y.reduceTransparency(context);
    final reduceMotion = AppMotion.reduceMotion(context);

    // The prototype fixes the row at 44px + 5px padding. The control has to
    // survive a larger text scale, so the row grows with the label instead of
    // clipping it.
    final rowHeight = math.max(
      44.0,
      MediaQuery.textScalerOf(context).scale(13) + 27,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: theme.slabShadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: hubBlur(context, 18),
          child: Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: opaque ? theme.bg2 : theme.glass,
              border: Border.all(color: opaque ? theme.txt2 : theme.line),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                // `width: calc(50% - 10px)`, measured on the padded box.
                final inner = constraints.maxWidth - 10;
                final knobWidth = inner / 2 - 5;

                return SizedBox(
                  height: rowHeight,
                  child: Stack(
                    children: [
                      AnimatedPositioned(
                        duration: reduceMotion
                            ? Duration.zero
                            : const Duration(milliseconds: 420),
                        curve: const Cubic(0.2, 0.9, 0.2, 1),
                        left: isDarkSelected ? 0 : knobWidth + 10,
                        top: 0,
                        width: knobWidth,
                        height: rowHeight,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            gradient: theme.accentTile(
                              from: 0.22,
                              to: 0.06,
                              begin: const Alignment(-0.5, -1),
                              end: const Alignment(0.5, 1),
                            ),
                            border: Border.all(
                              color: theme.accent.withValues(alpha: 0.35),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: theme.shadowColor.withValues(
                                  alpha: theme.isDark ? 0.4 : 0.12,
                                ),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                              BoxShadow(color: theme.glow, blurRadius: 22),
                            ],
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: _ThemeOption(
                              label: 'Dark',
                              selected: isDarkSelected,
                              onTap: onDark,
                              height: rowHeight,
                              glyph: _MoonGlyph(
                                color: theme.txt,
                                opacity: isDarkSelected ? 1.0 : 0.45,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _ThemeOption(
                              label: 'Light',
                              selected: !isDarkSelected,
                              onTap: onLight,
                              height: rowHeight,
                              glyph: _SunGlyph(
                                color: theme.txt,
                                accent: theme.accent,
                                lit: !isDarkSelected,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.height,
    required this.glyph,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final double height;
  final Widget glyph;

  @override
  Widget build(BuildContext context) {
    final theme = ProfileHubTheme.of(context);

    return Semantics(
      button: true,
      selected: selected,
      label: '$label theme',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          height: height,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              glyph,
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: hubSans(
                    context,
                    size: 13,
                    em: 0.01,
                    color: theme.txt,
                    weight: FontWeight.w500,
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

/// `background: radial-gradient(circle at 68% 32%, txt 0 52%, transparent 53%)`
/// with `box-shadow: inset -4px 0 0 -1px txt` — a lit disc bitten into a
/// crescent.
class _MoonGlyph extends StatelessWidget {
  const _MoonGlyph({required this.color, required this.opacity});

  final Color color;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = AppMotion.reduceMotion(context);
    return AnimatedOpacity(
      opacity: opacity,
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 400),
      child: SizedBox(
        width: 14,
        height: 14,
        child: CustomPaint(painter: _MoonPainter(color: color)),
      ),
    );
  }
}

class _MoonPainter extends CustomPainter {
  const _MoonPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final full = Path()
      ..addOval(Rect.fromLTWH(0, 0, size.width, size.height));
    // The bite: the gradient's hard stop at 52%/53% around (68%, 32%).
    final bite = Path()
      ..addOval(
        Rect.fromCircle(
          center: Offset(size.width * 1.02, size.height * 0.24),
          radius: size.width * 0.62,
        ),
      );
    canvas.drawPath(
      Path.combine(PathOperation.difference, full, bite),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _MoonPainter old) => old.color != color;
}

/// A filled disc ringed by `box-shadow: 0 0 0 3px …`, which brightens and gains
/// a halo when light mode is active.
class _SunGlyph extends StatelessWidget {
  const _SunGlyph({
    required this.color,
    required this.accent,
    required this.lit,
  });

  final Color color;
  final Color accent;
  final bool lit;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = AppMotion.reduceMotion(context);

    return SizedBox(
      // 12px disc + the 3px ring on each side.
      width: 18,
      height: 18,
      child: Center(
        child: AnimatedContainer(
          duration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 400),
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: lit ? 1.0 : 0.5),
            boxShadow: lit
                ? [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.22),
                      spreadRadius: 3,
                    ),
                    BoxShadow(
                      color: accent.withValues(alpha: 0.5),
                      blurRadius: 14,
                    ),
                  ]
                : [
                    BoxShadow(
                      color: color.withValues(alpha: 0.10),
                      spreadRadius: 3,
                    ),
                  ],
          ),
        ),
      ),
    );
  }
}

// ── Section: progress ────────────────────────────────────────────────────────

/// The Health Profile card's 4px completeness bar.
class HubProgressBar extends StatelessWidget {
  const HubProgressBar({super.key, required this.percent});

  final int percent;

  @override
  Widget build(BuildContext context) {
    final theme = ProfileHubTheme.of(context);
    final reduceMotion = AppMotion.reduceMotion(context);

    return ExcludeSemantics(
      child: SizedBox(
        height: 4,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: ColoredBox(
            color: theme.track,
            child: Align(
              alignment: Alignment.centerLeft,
              child: LayoutBuilder(
                builder: (context, constraints) => AnimatedContainer(
                  duration: reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 600),
                  curve: const Cubic(0.2, 0.8, 0.2, 1),
                  width:
                      constraints.maxWidth *
                      (percent / 100).clamp(0.0, 1.0),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    gradient: theme.progressFill,
                    boxShadow: [
                      BoxShadow(color: theme.glow, blurRadius: 14),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One row of the expanded breakdown: label, 96×3 track, mono figure.
class HubBreakdownRow extends StatelessWidget {
  const HubBreakdownRow({
    super.key,
    required this.label,
    required this.percent,
  });

  final String label;
  final int percent;

  @override
  Widget build(BuildContext context) {
    final theme = ProfileHubTheme.of(context);

    return Semantics(
      label: '$label $percent percent',
      child: ExcludeSemantics(
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: hubSans(context, size: 13, color: theme.txt2),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 96,
              height: 3,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: ColoredBox(
                  color: theme.track,
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: (percent / 100).clamp(0.0, 1.0),
                    child: ColoredBox(color: theme.accent),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 34,
              child: Text(
                '$percent%',
                textAlign: TextAlign.right,
                style: hubMono(context, size: 11, color: theme.txt),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The prototype's 9×9 chevron — two borders on a rotated square, which turns
/// from `45°` to `-135°` when the card expands.
class HubChevron extends StatelessWidget {
  const HubChevron({super.key, required this.expanded});

  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final theme = ProfileHubTheme.of(context);
    final reduceMotion = AppMotion.reduceMotion(context);

    return AnimatedRotation(
      // 45° → -135° is a half turn.
      turns: expanded ? -0.5 : 0.0,
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 350),
      curve: const Cubic(0.2, 0.8, 0.2, 1),
      child: Transform.rotate(
        angle: math.pi / 4,
        child: SizedBox(
          width: 9,
          height: 9,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(color: theme.txt2, width: 1.5),
                bottom: BorderSide(color: theme.txt2, width: 1.5),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Section: card ornaments ──────────────────────────────────────────────────

/// The Health Profile card's corner bloom: `top: -60px; right: -50px`, a 190px
/// radial falloff clipped to the card by `overflow: hidden`.
class HubCornerBloom extends StatelessWidget {
  const HubCornerBloom({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = ProfileHubTheme.of(context);

    return IgnorePointer(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: -60,
            right: -50,
            width: 190,
            height: 190,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: theme.bloomFill,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The Health Profile card's 52px icon tile: an accent-lit rounded square
/// holding a ringed dot.
class HubProfileGlyph extends StatelessWidget {
  const HubProfileGlyph({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = ProfileHubTheme.of(context);

    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: theme.accentTile(
          from: 0.28,
          to: 0.05,
          begin: const Alignment(-0.6, -1),
          end: const Alignment(0.6, 1),
        ),
        border: Border.all(color: theme.accent.withValues(alpha: 0.30)),
        boxShadow: [
          BoxShadow(
            color: theme.shadowColor.withValues(
              alpha: theme.isDark ? 0.4 : 0.12,
            ),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Center(
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: theme.accent, width: 2),
                boxShadow: [BoxShadow(color: theme.glow, blurRadius: 12)],
              ),
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
    );
  }
}

/// The Notifications card's four-bar equalizer.
///
/// `fsm-eq 1.9s ease-in-out infinite` with `.25s` stagger per bar. One ticker
/// drives all four: a CSS animation-delay on an infinite loop is a phase
/// offset, so the bars are read off the same clock at different phases rather
/// than given four controllers.
class HubEqualizer extends StatelessWidget {
  const HubEqualizer({super.key, required this.animate});

  final bool animate;

  static const Duration _period = Duration(milliseconds: 1900);

  @override
  Widget build(BuildContext context) {
    final theme = ProfileHubTheme.of(context);

    final colors = <Color>[
      theme.accent,
      theme.accent.withValues(alpha: 0.8),
      theme.accent.withValues(alpha: 0.55),
      theme.track2,
    ];

    return ExcludeSemantics(
      child: SizedBox(
        height: 26,
        child: AmbientLoop(
          period: _period,
          active: animate,
          // Held mid-cycle so the still frame keeps the staggered silhouette
          // rather than collapsing every bar to the same height.
          restT: 0.5,
          builder: (context, t, child) => Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < 4; i++) ...[
                if (i > 0) const SizedBox(width: 3),
                _EqBar(
                  // `.25s` of a 1.9s loop per bar.
                  scale: pingPongBetween(
                    (t + i * (0.25 / 1.9)) % 1.0,
                    0.3,
                    1.0,
                  ),
                  color: colors[i],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _EqBar extends StatelessWidget {
  const _EqBar({required this.scale, required this.color});

  final double scale;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 3,
    height: 26,
    child: Align(
      alignment: Alignment.bottomCenter,
      // `transform-origin: bottom` + `scaleY`, as an explicit height.
      // A `FractionallySizedBox` collapses here: `Align` hands it loose
      // constraints, so it has no height to take a fraction of.
      child: Container(
        width: 3,
        height: 26 * scale.clamp(0.0, 1.0),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    ),
  );
}

/// The prototype's pill switch. Deliberately **not** a Material [Switch]: the
/// stock control has a different track size, knob size, elevation and motion,
/// and swapping it in would visibly change the card.
class HubSwitch extends StatelessWidget {
  const HubSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.semanticLabel,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = ProfileHubTheme.of(context);
    final reduceMotion = AppMotion.reduceMotion(context);
    final enabled = onChanged != null;

    return Semantics(
      toggled: value,
      enabled: enabled,
      label: semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? () => onChanged!(!value) : null,
        // The pill is 42×24; the target around it is the 48dp minimum.
        child: SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: AnimatedContainer(
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 300),
              width: 42,
              height: 24,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                color: value
                    ? theme.accent.withValues(alpha: 0.30)
                    : theme.track,
                border: Border.all(
                  color: value
                      ? theme.accent.withValues(alpha: 0.45)
                      : theme.line,
                ),
              ),
              child: Stack(
                children: [
                  AnimatedPositioned(
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 300),
                    curve: const Cubic(0.2, 0.9, 0.2, 1),
                    top: 2,
                    left: value ? 20 : 2,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: theme.isDark
                            ? const Color(0xFFEAFDF7)
                            : Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: theme.shadowColor.withValues(
                              alpha: theme.isDark ? 0.45 : 0.22,
                            ),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A tracked mono caption preceded by a 5px bead — the prototype's
/// `ACTIVE` / `SECURED` / `OPERATOR` state line.
///
/// When [animateSwap] is set the label cross-fades on change, matching the
/// prototype's `opacity → 0, swap after 140ms, fade back over .25s`.
class HubStateLine extends StatelessWidget {
  const HubStateLine({
    super.key,
    required this.label,
    required this.color,
    this.beadSize = 5,
    this.em = 0.14,
    this.size = 10,
    this.pulse = false,
    this.animateSwap = false,
    this.animate = true,
  });

  final String label;
  final Color color;
  final double beadSize;
  final double em;
  final double size;

  /// `fsm-breathe 2.8s` on the bead (the admin slab's operator light).
  final bool pulse;

  final bool animateSwap;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = AppMotion.reduceMotion(context);

    Widget bead = Container(
      width: beadSize,
      height: beadSize,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );

    if (pulse) {
      bead = AmbientLoop(
        period: const Duration(milliseconds: 2800),
        active: animate,
        restT: 0.5,
        builder: (context, t, child) =>
            Opacity(opacity: pingPongBetween(t, 0.5, 1.0), child: child),
        child: bead,
      );
    }

    Widget text = Text(
      label,
      key: ValueKey(label),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: hubMono(context, size: size, em: em, color: color),
    );

    if (animateSwap) {
      text = AnimatedSwitcher(
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 250),
        child: text,
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [bead, const SizedBox(width: 6), Flexible(child: text)],
    );
  }
}

/// The Reminders card's four-stop timeline, with its pulsing "now" node.
class HubReminderTimeline extends StatelessWidget {
  const HubReminderTimeline({super.key, required this.animate});

  final bool animate;

  @override
  Widget build(BuildContext context) {
    final theme = ProfileHubTheme.of(context);

    return ExcludeSemantics(
      child: SizedBox(
        height: 26,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned(
              left: 0,
              right: 0,
              height: 1,
              child: ColoredBox(color: theme.line),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _dot(6, theme.track2),
                _dot(6, theme.track2),
                _NowNode(animate: animate),
                _dot(6, theme.track),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _dot(double size, Color color) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(shape: BoxShape.circle, color: color),
  );
}

class _NowNode extends StatelessWidget {
  const _NowNode({required this.animate});

  final bool animate;

  @override
  Widget build(BuildContext context) {
    final theme = ProfileHubTheme.of(context);

    return SizedBox(
      width: 17,
      height: 17,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // `inset: -4px` ring, `fsm-pulse 2.6s`.
          AmbientLoop(
            period: const Duration(milliseconds: 2600),
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
              width: 17,
              height: 17,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: theme.accent),
              ),
            ),
          ),
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: theme.accent,
              boxShadow: [BoxShadow(color: theme.glow, blurRadius: 12)],
            ),
          ),
        ],
      ),
    );
  }
}

/// The Privacy card's hexagonal padlock plate.
class HubPrivacyGlyph extends StatelessWidget {
  const HubPrivacyGlyph({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = ProfileHubTheme.of(context);

    return SizedBox(
      width: 44,
      height: 48,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _HexPainter(
                gradient: theme.accentTile(
                  from: 0.34,
                  to: 0.04,
                  begin: const Alignment(-0.36, -1),
                  end: const Alignment(0.36, 1),
                ),
              ),
            ),
          ),
          // Shackle, then body — the prototype's two spans.
          Transform.translate(
            offset: const Offset(0, -5),
            child: CustomPaint(
              size: const Size(9, 9),
              painter: _ShacklePainter(color: theme.txt),
            ),
          ),
          Transform.translate(
            offset: const Offset(0, 2),
            child: Container(
              width: 11,
              height: 9,
              decoration: BoxDecoration(
                color: theme.txt,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// `clip-path: polygon(50% 0%, 100% 18%, 100% 56%, 50% 100%, 0% 56%, 0% 18%)`.
class _HexPainter extends CustomPainter {
  const _HexPainter({required this.gradient});

  final Gradient gradient;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(w * 0.5, 0)
      ..lineTo(w, h * 0.18)
      ..lineTo(w, h * 0.56)
      ..lineTo(w * 0.5, h)
      ..lineTo(0, h * 0.56)
      ..lineTo(0, h * 0.18)
      ..close();

    canvas.drawPath(
      path,
      Paint()..shader = gradient.createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(covariant _HexPainter old) => old.gradient != gradient;
}

/// The padlock's `border-radius: 999px 999px 0 0; border-bottom: 0` shackle.
class _ShacklePainter extends CustomPainter {
  const _ShacklePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawArc(
      Rect.fromLTWH(1, 1, size.width - 2, size.height * 2 - 2),
      math.pi,
      math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _ShacklePainter old) => old.color != color;
}

/// The Privacy card's three-segment strip.
///
/// Unlike the prototype's numeric readouts this asserts no quantity — it is an
/// abstract rule, and is marked as decoration for assistive technology.
class HubSegments extends StatelessWidget {
  const HubSegments({super.key, required this.lit, this.total = 3});

  final int lit;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = ProfileHubTheme.of(context);

    return ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < total; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Container(
              width: 26,
              height: 3,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                color: i < lit ? theme.accent : theme.track2,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The accent-outlined pill used for `SECURED`.
class HubAccentPill extends StatelessWidget {
  const HubAccentPill({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = ProfileHubTheme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: theme.accentSoft,
        border: Border.all(color: theme.accent.withValues(alpha: 0.3)),
      ),
      child: HubStateLine(
        label: label,
        color: theme.accent,
        em: 0.12,
        animate: false,
      ),
    );
  }
}

/// The Help Center card's travelling hairline:
/// `fsm-sweep 4.5s ease-in-out infinite`, `translateX(-130% → 240%)`.
class HubSweepLine extends StatelessWidget {
  const HubSweepLine({super.key, required this.animate});

  final bool animate;

  @override
  Widget build(BuildContext context) {
    final theme = ProfileHubTheme.of(context);

    return IgnorePointer(
      child: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          // Explicitly full-width: the hairline's own gradient has no
          // intrinsic size, so without this the box collapses to zero and the
          // sweep never paints.
          width: double.infinity,
          height: 1,
          child: AmbientLoop(
            period: const Duration(milliseconds: 4500),
            active: animate,
            builder: (context, t, child) {
              // ease-in-out across a single forward pass.
              final eased = Curves.easeInOut.transform(t);
              return FractionalTranslation(
                translation: Offset(-1.3 + eased * 3.7, 0),
                child: child,
              );
            },
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    theme.accent.withValues(alpha: 0),
                    theme.accent.withValues(alpha: 0.6),
                    theme.accent.withValues(alpha: 0),
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The admin slab's scanline wash and corner brackets.
class HubAdminOrnament extends StatelessWidget {
  const HubAdminOrnament({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = ProfileHubTheme.of(context);

    return IgnorePointer(
      child: CustomPaint(
        painter: _AdminOrnamentPainter(
          scanline: theme.txt.withValues(alpha: theme.isDark ? 0.05 : 0.04),
          bracket: theme.accent.withValues(alpha: 0.5),
        ),
      ),
    );
  }
}

class _AdminOrnamentPainter extends CustomPainter {
  const _AdminOrnamentPainter({
    required this.scanline,
    required this.bracket,
  });

  final Color scanline;
  final Color bracket;

  @override
  void paint(Canvas canvas, Size size) {
    // `repeating-linear-gradient(90deg, rgba(255,255,255,0.05) 0 1px,
    //  transparent 1px 22px)` at `opacity: .5`.
    final line = Paint()..color = scanline.withValues(alpha: scanline.a * 0.5);
    for (var x = 0.0; x < size.width; x += 22) {
      canvas.drawRect(Rect.fromLTWH(x, 0, 1, size.height), line);
    }

    // 8×8 corner brackets, top-left and bottom-right, inset 8px.
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = bracket;

    canvas.drawPath(
      Path()
        ..moveTo(8, 16)
        ..lineTo(8, 8)
        ..lineTo(16, 8),
      stroke,
    );
    canvas.drawPath(
      Path()
        ..moveTo(size.width - 16, size.height - 8)
        ..lineTo(size.width - 8, size.height - 8)
        ..lineTo(size.width - 8, size.height - 16),
      stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _AdminOrnamentPainter old) =>
      old.scanline != scanline || old.bracket != bracket;
}

/// The admin slab's 38px bezel holding a rotated accent lozenge.
class HubAdminGlyph extends StatelessWidget {
  const HubAdminGlyph({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = ProfileHubTheme.of(context);

    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        border: Border.all(color: theme.txt.withValues(alpha: 0.16)),
        color: theme.txt.withValues(alpha: 0.03),
      ),
      child: Center(
        child: Transform.rotate(
          angle: math.pi / 4,
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: theme.accent,
              boxShadow: [BoxShadow(color: theme.glow, blurRadius: 12)],
            ),
          ),
        ),
      ),
    );
  }
}
