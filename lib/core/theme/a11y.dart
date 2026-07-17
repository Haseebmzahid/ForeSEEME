import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Accessibility helpers for the ForeSeeMe design system (Sprint 5, Prompt 15).
///
/// Two concerns, both from audit **M4**:
///
/// 1. **Contrast maths** — WCAG 2.1 relative luminance + contrast ratio, plus an
///    alpha-composite so a *translucent* surface's effective colour (over its
///    background) can be measured. Used by the contrast-audit tests and
///    reusable at runtime.
/// 2. **Reduced-transparency fallback** — when the user asks for higher contrast
///    (`MediaQuery.highContrast`, i.e. iOS "Increase Contrast" / Android
///    high-contrast), translucent glass fills collapse to **solid** surfaces and
///    backdrop blur is dropped, so text never sits on an unpredictable, low-
///    contrast translucent layer. Flutter exposes no dedicated "reduce
///    transparency" flag, so `highContrast` is the honest trigger. See
///    [ForeSeeMeSurface] for the design system's one glass-card recipe built on
///    top of this fallback.
class A11y {
  A11y._();

  // ── WCAG contrast maths (pure) ─────────────────────────────────────────────

  static const double aaText = 4.5; // AA, normal text
  static const double aaLargeText = 3.0; // AA, large / UI components

  /// WCAG relative luminance of an **opaque** colour (0 = black, 1 = white).
  static double relativeLuminance(Color color) {
    double channel(double c) {
      c = c / 255.0;
      return c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4) as double;
    }

    final r = channel((color.r * 255.0).roundToDouble());
    final g = channel((color.g * 255.0).roundToDouble());
    final b = channel((color.b * 255.0).roundToDouble());
    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
  }

  /// WCAG contrast ratio between two colours (≥ 1.0). Both are treated as
  /// opaque; composite a translucent colour with [compositeOver] first.
  static double contrastRatio(Color a, Color b) {
    final la = relativeLuminance(a);
    final lb = relativeLuminance(b);
    final hi = la > lb ? la : lb;
    final lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  /// Alpha-composite [fg] (which may be translucent) over the **opaque** [bg],
  /// returning the effective opaque colour — e.g. the real background a label
  /// sits on inside a translucent glass card.
  static Color compositeOver(Color fg, Color bg) {
    final a = fg.a; // 0..1
    double mix(double f, double b) => f * a + b * (1 - a);
    return Color.fromARGB(
      255,
      (mix(fg.r, bg.r) * 255.0).round(),
      (mix(fg.g, bg.g) * 255.0).round(),
      (mix(fg.b, bg.b) * 255.0).round(),
    );
  }

  // ── Reduced-transparency fallback ──────────────────────────────────────────

  /// Whether to drop translucency in favour of solid, higher-contrast surfaces.
  static bool reduceTransparency(BuildContext context) =>
      MediaQuery.maybeOf(context)?.highContrast ?? false;

  /// Backdrop-blur sigma for a `BackdropFilter` surface: [sigma] normally, **0**
  /// under reduced transparency (no blur, so the solid fill fully governs
  /// contrast).
  static double blurSigma(BuildContext context, {double sigma = 16}) =>
      reduceTransparency(context) ? 0 : sigma;
}
