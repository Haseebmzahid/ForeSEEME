import 'package:flutter/material.dart';
import 'package:fyp_foreseeme/core/theme/app_design_v2.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_estimate_model.dart';

/// The visual appearance of a risk signal: a colour **paired with a distinct
/// icon shape and a text label**, so risk is never conveyed by colour alone
/// (Design System accessibility requirement — verified for colorblind users).
///
/// Single source of truth for risk styling, reused by the dashboard risk card,
/// the risk legend, and (later) the trend badge and national map. Each level's
/// icon is a distinct glyph (✓ / ! / △ / ?) that survives greyscale.
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
class RiskVisuals {
  RiskVisuals._();

  // `fill`/`border` are derived from the single `AppColorsV2.riskX` token via
  // `.withValues(alpha:)` rather than hand-duplicated hex, so a token change
  // can never drift out of sync with these tints (each field is `static
  // final`, not `const`, only because `.withValues` isn't a const function —
  // the values are still computed exactly once, at load).
  static final RiskAppearance low = RiskAppearance(
    color: AppColorsV2.riskLow,
    fill: AppColorsV2.riskLow.withValues(alpha: 0.12),
    border: AppColorsV2.riskLow.withValues(alpha: 0.40),
    icon: Icons.check_circle_outline_rounded,
    label: 'Low',
    headline: 'Low Risk',
  );

  static final RiskAppearance medium = RiskAppearance(
    color: AppColorsV2.riskMedium,
    fill: AppColorsV2.riskMedium.withValues(alpha: 0.12),
    border: AppColorsV2.riskMedium.withValues(alpha: 0.40),
    icon: Icons.priority_high_rounded,
    label: 'Medium',
    headline: 'Medium Risk',
  );

  static final RiskAppearance high = RiskAppearance(
    color: AppColorsV2.riskHigh,
    fill: AppColorsV2.riskHigh.withValues(alpha: 0.16),
    border: AppColorsV2.riskHigh.withValues(alpha: 0.34),
    icon: Icons.warning_amber_rounded,
    label: 'High',
    headline: 'High Risk',
  );

  /// Low-confidence / unknown — the grey uncertainty treatment.
  static final RiskAppearance uncertain = RiskAppearance(
    color: AppColorsV2.riskUncertain,
    fill: AppColorsV2.riskUncertain.withValues(alpha: 0.10),
    border: AppColorsV2.riskUncertain.withValues(alpha: 0.34),
    icon: Icons.help_outline_rounded,
    label: 'Uncertain',
    headline: 'Uncertain',
  );

  /// Appearance for a [level]; when [lowConfidence] is true the estimate is
  /// unreliable, so the grey [uncertain] treatment is used instead of the
  /// level colour (per the contract's `lowConfidence` flag).
  static RiskAppearance of(RiskLevel level, {bool lowConfidence = false}) {
    if (lowConfidence) return uncertain;
    return forLevel(level);
  }

  /// Appearance for a [level], ignoring confidence.
  static RiskAppearance forLevel(RiskLevel level) => switch (level) {
    RiskLevel.low => low,
    RiskLevel.medium => medium,
    RiskLevel.high => high,
  };

  /// The three risk levels, low→high, for the legend.
  static final List<RiskAppearance> levels = [low, medium, high];
}
