import 'package:flutter/material.dart';

import 'package:fyp_foreseeme/core/theme/a11y.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_tokens.dart';

/// Shared glass-surface tokens for the Risk module.
///
/// One frosted-card recipe for every Risk surface, resolved from
/// [ForeSeeMeTheme] for the **ambient brightness** so cards read correctly in
/// light and dark, and honouring the **reduced-transparency** accessibility
/// fallback (audit M4): under reduced transparency the fill becomes opaque and
/// the border stronger, so contrast never depends on translucency.
class RiskSurface {
  RiskSurface._();

  /// Translucent card fill (opaque under reduced transparency).
  static Color fill(BuildContext context) {
    final p = context.fsmPalette;
    if (A11y.reduceTransparency(context)) return p.surface;
    return p.surface.withValues(alpha: p.isDark ? 0.55 : 0.82);
  }

  /// Hairline card border (stronger under reduced transparency).
  static Color stroke(BuildContext context) {
    final p = context.fsmPalette;
    if (A11y.reduceTransparency(context)) return p.outline;
    return p.isDark ? p.onSurface.withValues(alpha: 0.06) : p.outlineVariant;
  }

  /// Standard Risk-card decoration: [fill] (or a caller [gradient]) + a hairline
  /// [stroke] (or [borderColor]) + the design-system medium shadow.
  static BoxDecoration card(
    BuildContext context, {
    double radius = ForeSeeMeRadius.lg,
    Gradient? gradient,
    Color? borderColor,
    List<BoxShadow>? shadow,
  }) {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      color: gradient == null ? fill(context) : null,
      gradient: gradient,
      border: Border.all(color: borderColor ?? stroke(context)),
      boxShadow: shadow ?? context.fsmColors.shadows.medium,
    );
  }
}
