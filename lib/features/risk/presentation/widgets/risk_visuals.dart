import 'package:flutter/material.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_palette.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_estimate_model.dart';

/// The visual appearance of a risk signal: a colour **paired with a distinct
/// icon shape and a text label**, so risk is never conveyed by colour alone
/// (Design System accessibility requirement — verified for colorblind users).
///
/// Single source of truth for risk styling, reused by the dashboard risk card,
/// the risk legend, the trend badge and the national map. Each level's icon is a
/// distinct glyph (✓ / ! / △ / ?) that survives greyscale.
@immutable
class RiskAppearance {
  /// Primary signal colour.
  final Color color;

  /// Translucent fill tint for surfaces.
  final Color fill;

  /// Hairline border tint.
  final Color border;

  /// Distinct icon shape for the level.
  final IconData icon;

  /// Short label, e.g. "High" / "Uncertain".
  final String label;

  /// Headline form, e.g. "High Risk" / "Uncertain".
  final String headline;

  const RiskAppearance({
    required this.color,
    required this.fill,
    required this.border,
    required this.icon,
    required this.label,
    required this.headline,
  });
}

/// Maps [RiskLevel] (and the low-confidence override) to a [RiskAppearance].
///
/// Two families of accessors:
///
///  * **Static** ([low]/[medium]/[high]/[uncertain], [of], [forLevel], [levels])
///    — brightness-independent identity anchors. Their colours are sourced from
///    the ForeSeeMe **dark** palette's semantic tokens (low→success,
///    medium→warning, high→error, uncertain→neutral). Identity is meaningful:
///    the national map derives a marker hue via `identical(a, RiskVisuals.high)`,
///    and out-of-module surfaces read these directly.
///  * **Brightness-aware** ([resolve]/[colorOf]) — for display inside Risk
///    surfaces, where the colour must adapt to the active light/dark theme so it
///    stays legible on the themed card. Icons/labels are shared with the static
///    appearances; only the colour tier changes.
class RiskVisuals {
  RiskVisuals._();

  static RiskAppearance _make(
    Color c,
    IconData icon,
    String label,
    String headline, {
    double fillAlpha = 0.12,
    double borderAlpha = 0.40,
  }) => RiskAppearance(
    color: c,
    fill: c.withValues(alpha: fillAlpha),
    border: c.withValues(alpha: borderAlpha),
    icon: icon,
    label: label,
    headline: headline,
  );

  // Canonical (brightness-independent) risk appearances — sourced from the
  // ForeSeeMe design system's dark semantic tokens (never a hand-picked hex), so
  // identity-based callers (the map's marker hue) keep a stable colour.
  static final RiskAppearance low = _make(
    ForeSeeMePalette.dark.success,
    Icons.check_circle_outline_rounded,
    'Low',
    'Low Risk',
  );

  static final RiskAppearance medium = _make(
    ForeSeeMePalette.dark.warning,
    Icons.priority_high_rounded,
    'Medium',
    'Medium Risk',
  );

  static final RiskAppearance high = _make(
    ForeSeeMePalette.dark.error,
    Icons.warning_amber_rounded,
    'High',
    'High Risk',
    fillAlpha: 0.16,
    borderAlpha: 0.34,
  );

  /// Low-confidence / unknown — the neutral uncertainty treatment.
  static final RiskAppearance uncertain = _make(
    ForeSeeMePalette.dark.onSurfaceVariant,
    Icons.help_outline_rounded,
    'Uncertain',
    'Uncertain',
    fillAlpha: 0.10,
    borderAlpha: 0.34,
  );

  /// Static appearance for a [level]; when [lowConfidence] is true the estimate
  /// is unreliable, so the neutral [uncertain] treatment is used.
  static RiskAppearance of(RiskLevel level, {bool lowConfidence = false}) {
    if (lowConfidence) return uncertain;
    return forLevel(level);
  }

  /// Static appearance for a [level], ignoring confidence.
  static RiskAppearance forLevel(RiskLevel level) => switch (level) {
    RiskLevel.low => low,
    RiskLevel.medium => medium,
    RiskLevel.high => high,
  };

  /// The three risk levels, low→high, for the legend.
  static final List<RiskAppearance> levels = [low, medium, high];

  // ── Brightness-aware display (in-module) ───────────────────────────────────

  /// The display colour for a risk level from the **active theme's** semantic
  /// tokens (low→success, medium→warning, high→error, uncertain→neutral), so it
  /// reads correctly on the themed card in both light and dark.
  static Color colorOf(
    BuildContext context,
    RiskLevel level, {
    bool lowConfidence = false,
  }) {
    if (lowConfidence) return context.fsmPalette.onSurfaceVariant;
    final c = context.fsmColors;
    return switch (level) {
      RiskLevel.low => c.success,
      RiskLevel.medium => c.warning,
      RiskLevel.high => context.fsmPalette.error,
    };
  }

  /// A brightness-aware [RiskAppearance] for display in Risk surfaces: the icon,
  /// label and headline of the static [of], with the colour/fill/border resolved
  /// from the active theme via [colorOf].
  static RiskAppearance resolve(
    BuildContext context,
    RiskLevel level, {
    bool lowConfidence = false,
  }) {
    final base = of(level, lowConfidence: lowConfidence);
    final c = colorOf(context, level, lowConfidence: lowConfidence);
    final isHigh = level == RiskLevel.high && !lowConfidence;
    return RiskAppearance(
      color: c,
      fill: c.withValues(alpha: isHigh ? 0.16 : (lowConfidence ? 0.10 : 0.12)),
      border: c.withValues(alpha: isHigh ? 0.34 : 0.40),
      icon: base.icon,
      label: base.label,
      headline: base.headline,
    );
  }
}
