import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:fyp_foreseeme/core/theme/a11y.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/core/widgets/app_motion.dart';

/// Visual weight of a [GlassActionButton].
enum GlassActionTone {
  /// The screen's committing action: the glass is tinted with the accent and
  /// carries a little more depth.
  primary,

  /// The quieter alternative. Same glass, no tint, less depth — deliberately
  /// *not* a warning treatment.
  neutral,
}

/// ForeSeeMe's **liquid-glass control**: a translucent pane that sits above the
/// content it acts on, rather than a filled Material button that sits in a form.
///
/// The material is built from five stacked layers, all resolved from design
/// tokens:
///
///  1. a backdrop blur, so whatever is behind genuinely shows through;
///  2. a translucent fill — accent-tinted for [GlassActionTone.primary];
///  3. a top-edge inner highlight, reading as the lit lip of a glass pane;
///  4. a restrained diagonal specular band;
///  5. a hairline border and a soft contact shadow beneath.
///
/// Pressing compresses the pane: it scales down slightly, the fill thickens (a
/// pane pushed against its backing), the shadow tightens, and the highlight
/// dims. That is the whole press language — no ripple, no glow, no bounce.
///
/// **Accessibility.** Under `A11y.reduceTransparency` the blur is dropped and
/// the fill becomes opaque with a stronger border, so contrast never rests on
/// translucency. Under `AppMotion.reduceMotion` the press transition is
/// instant. The tap target is never smaller than 48dp, and [icon] carries the
/// action's meaning alongside colour so the two tones are never distinguished
/// by colour alone.
class GlassActionButton extends StatefulWidget {
  const GlassActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.tone = GlassActionTone.neutral,
    this.accent,
    this.foreground,
    this.height = 54,
    this.isBusy = false,
    this.semanticLabel,
    this.letterSpacing,
    this.fontSize,
  });

  final String label;

  /// Null disables the control (and its press feedback).
  final VoidCallback? onPressed;

  /// Leading glyph. Carries the action's meaning without relying on colour.
  final IconData? icon;

  final GlassActionTone tone;

  /// Tint of the glass and of the [GlassActionTone.primary] ink. Defaults to
  /// the palette primary; surfaces with their own local palette pass theirs.
  final Color? accent;

  /// Ink for a [GlassActionTone.neutral] button and the base for the glass's
  /// highlights. Defaults to the palette's primary text colour.
  final Color? foreground;

  /// Visual height. Clamped to at least the 48dp minimum target, and allowed to
  /// grow when the text scale demands it.
  final double height;

  /// Swaps the label for a spinner and blocks the tap, without changing size.
  final bool isBusy;

  final String? semanticLabel;

  final double? letterSpacing;
  final double? fontSize;

  @override
  State<GlassActionButton> createState() => _GlassActionButtonState();
}

class _GlassActionButtonState extends State<GlassActionButton> {
  static const double _radius = 16;

  bool _pressed = false;

  bool get _enabled => widget.onPressed != null && !widget.isBusy;

  void _setPressed(bool value) {
    if (_pressed == value || !_enabled) return;
    setState(() => _pressed = value);
  }

  void _handleTapDown() {
    if (!_enabled) return;
    // The lightest cue the platform offers — this is a healthcare confirmation,
    // not a game control. Matches the app's existing direct HapticFeedback use.
    HapticFeedback.selectionClick();
    _setPressed(true);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final reduceMotion = AppMotion.reduceMotion(context);
    final opaque = A11y.reduceTransparency(context);

    final accent = widget.accent ?? palette.primary;
    final foreground = widget.foreground ?? palette.textPrimary;
    final isPrimary = widget.tone == GlassActionTone.primary;

    final fill = _fill(
      accent: accent,
      foreground: foreground,
      isPrimary: isPrimary,
      pressed: _pressed && _enabled,
      opaque: opaque,
      isDark: palette.isDark,
    );
    // A translucent pane changes the effective background under its own label,
    // so the ink is checked against that composite rather than assumed legible.
    final baseInk = _readableInk(
      isPrimary ? accent : foreground,
      fill,
      palette.surface,
    );
    final ink = _enabled ? baseInk : baseInk.withValues(alpha: 0.38);

    // The pane must stay tappable and legible as the user's text grows, so the
    // 48dp floor is a floor, not a fixed height.
    final scaler = MediaQuery.textScalerOf(context);
    final fontSize = widget.fontSize ?? 13.0;
    final height = math.max(
      math.max(widget.height, 48.0),
      scaler.scale(fontSize) + 30,
    );

    final pressed = _pressed && _enabled;

    return Semantics(
      button: true,
      enabled: _enabled,
      label: widget.semanticLabel ?? widget.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _handleTapDown(),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        onTap: _enabled ? widget.onPressed : null,
        child: AnimatedScale(
          scale: (pressed && !reduceMotion) ? 0.975 : 1.0,
          duration: reduceMotion ? Duration.zero : AppMotion.fast,
          curve: AppMotion.curve,
          child: AnimatedContainer(
            duration: reduceMotion ? Duration.zero : AppMotion.fast,
            curve: AppMotion.curve,
            height: height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(_radius),
              // A soft contact shadow that tightens under the press, as a real
              // pane pushed toward its backing would.
              boxShadow: _enabled
                  ? [
                      BoxShadow(
                        color: (isPrimary ? accent : palette.shadow).withValues(
                          alpha: pressed
                              ? 0.10
                              : (isPrimary ? 0.20 : 0.14),
                        ),
                        blurRadius: pressed ? 12 : 22,
                        spreadRadius: -8,
                        offset: Offset(0, pressed ? 4 : 10),
                      ),
                    ]
                  : null,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(_radius),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(
                  sigmaX: A11y.blurSigma(context, sigma: 18),
                  sigmaY: A11y.blurSigma(context, sigma: 18),
                ),
                child: AnimatedContainer(
                  duration: reduceMotion ? Duration.zero : AppMotion.fast,
                  curve: AppMotion.curve,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(_radius),
                    color: fill,
                    border: Border.all(
                      // A dark hairline on a pale pane needs less alpha to read
                      // than a light one on a dark pane, so the edge stays
                      // visible in both rooms without shouting in either.
                      color: (isPrimary ? accent : foreground).withValues(
                        alpha: opaque
                            ? 0.55
                            : palette.isDark
                            ? (isPrimary ? 0.34 : 0.16)
                            : (isPrimary ? 0.44 : 0.28),
                      ),
                    ),
                  ),
                  child: Stack(
                    children: [
                      if (!opaque) ...[
                        // The lit lip along the pane's top edge.
                        Positioned.fill(
                          child: IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(_radius),
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.white.withValues(
                                      alpha: pressed ? 0.10 : 0.18,
                                    ),
                                    Colors.white.withValues(alpha: 0),
                                  ],
                                  stops: const [0.0, 0.48],
                                ),
                              ),
                            ),
                          ),
                        ),
                        // A single restrained specular band, raked across the
                        // upper-left the way a fixed key light would catch it.
                        Positioned.fill(
                          child: IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(_radius),
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Colors.white.withValues(alpha: 0),
                                    Colors.white.withValues(
                                      alpha: pressed ? 0.05 : 0.10,
                                    ),
                                    Colors.white.withValues(alpha: 0),
                                  ],
                                  stops: const [0.06, 0.20, 0.42],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                      Center(
                        child: widget.isBusy
                            ? SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  strokeCap: StrokeCap.round,
                                  valueColor: AlwaysStoppedAnimation<Color>(ink),
                                ),
                              )
                            : Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (widget.icon != null) ...[
                                      Icon(
                                        widget.icon,
                                        size: 16,
                                        color: ink,
                                      ),
                                      const SizedBox(width: 8),
                                    ],
                                    Flexible(
                                      child: Text(
                                        widget.label,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: context.fsmText.labelLarge
                                            ?.copyWith(
                                              fontSize: fontSize,
                                              fontWeight: isPrimary
                                                  ? FontWeight.w700
                                                  : FontWeight.w500,
                                              letterSpacing:
                                                  widget.letterSpacing ??
                                                  fontSize * 0.12,
                                              color: ink,
                                            ),
                                      ),
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
        ),
      ),
    );
  }

  /// Nudges [ink] toward the nearest extreme until it clears WCAG AA against
  /// the pane it will sit on.
  ///
  /// The pane is translucent, so its effective background is [pane] composited
  /// over whatever is behind it — approximated here by [behind], the palette's
  /// own surface. A tinted glass pane is exactly the case where an accent that
  /// reads fine on the app background quietly falls under 4.5:1, so the
  /// component checks rather than trusts.
  static Color _readableInk(Color ink, Color pane, Color behind) {
    final background = A11y.compositeOver(pane, behind);
    final toward = A11y.relativeLuminance(background) > 0.4
        ? Colors.black
        : Colors.white;

    var candidate = ink;
    for (var step = 0; step < 8; step++) {
      if (A11y.contrastRatio(candidate, background) >= A11y.aaText) break;
      candidate = Color.lerp(candidate, toward, 0.14)!;
    }
    return candidate;
  }

  /// The pane's own tint. Thickens under the press; goes fully opaque when the
  /// user has asked for reduced transparency.
  Color _fill({
    required Color accent,
    required Color foreground,
    required bool isPrimary,
    required bool pressed,
    required bool opaque,
    required bool isDark,
  }) {
    if (!_enabled) {
      return foreground.withValues(alpha: opaque ? 0.10 : 0.04);
    }
    if (isPrimary) {
      if (opaque) return accent.withValues(alpha: isDark ? 0.55 : 0.22);
      return accent.withValues(
        alpha: (isDark ? 0.22 : 0.16) + (pressed ? 0.07 : 0.0),
      );
    }
    if (opaque) return foreground.withValues(alpha: isDark ? 0.18 : 0.10);
    return foreground.withValues(
      alpha: (isDark ? 0.07 : 0.05) + (pressed ? 0.05 : 0.0),
    );
  }
}
