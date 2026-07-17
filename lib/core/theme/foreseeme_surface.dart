import 'package:flutter/material.dart';

import 'package:fyp_foreseeme/core/theme/a11y.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_tokens.dart';

/// Shared **frosted-surface** tokens for the ForeSeeMe design system.
///
/// One glass-card recipe, resolved from [ForeSeeMeTheme] for the **ambient
/// brightness** so cards read correctly in light and dark, and honouring the
/// **reduced-transparency** accessibility fallback (audit M4): under reduced
/// transparency the fill becomes opaque and the border stronger, so contrast
/// never depends on translucency.
///
/// This is the design system's **only** glass-card recipe (UX-09): the Risk
/// module's former `RiskSurface` and the Dashboard's former local helper both
/// carried the same semantics and have been consolidated onto this class.
class ForeSeeMeSurface {
  ForeSeeMeSurface._();

  /// Translucent card fill (opaque under reduced transparency).
  static Color fill(BuildContext context) {
    final p = context.fsmPalette;
    if (A11y.reduceTransparency(context)) return p.surface;
    return p.surface.withValues(alpha: p.isDark ? 0.55 : 0.82);
  }

  /// A more opaque fill for chrome that sits over scrolling content
  /// (app bars, sticky headers) so text stays legible while scrolling.
  static Color chromeFill(BuildContext context) {
    final p = context.fsmPalette;
    if (A11y.reduceTransparency(context)) return p.background;
    return p.background.withValues(alpha: p.isDark ? 0.75 : 0.80);
  }

  /// Hairline card border (stronger under reduced transparency).
  static Color stroke(BuildContext context) {
    final p = context.fsmPalette;
    if (A11y.reduceTransparency(context)) return p.outline;
    return p.isDark ? p.onSurface.withValues(alpha: 0.08) : p.outlineVariant;
  }

  /// Standard card decoration: [fill] (or a caller [gradient]) + a hairline
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
