import 'package:flutter/material.dart';

/// ForeSeeMe premium design-system — **the single source of truth for colour**.
///
/// Every raw `Color(0x…)` literal in the new theme lives here and *only* here.
/// [ForeSeeMeTheme], its `ColorScheme`s, typography, gradients and shadows all
/// resolve their colours from a [ForeSeeMePalette]; none of them declare a raw
/// colour of their own. Tuning the brand = editing this file.
///
/// Two immutable palettes are provided — [ForeSeeMePalette.light] and
/// [ForeSeeMePalette.dark] — chosen to feel at home next to Google Fit, Fitbit,
/// Samsung Health and Apple Health: calm cool-neutral surfaces, a confident
/// health-green primary, teal + violet as supporting accents, and a full,
/// deliberately-consistent light theme (the previous light theme was partial).
///
/// This is the app's one colour system — every surface reads its colours from
/// here, directly or via the theme built from it.
@immutable
class ForeSeeMePalette {
  const ForeSeeMePalette({
    required this.brightness,
    // Brand — primary / secondary / tertiary
    required this.primary,
    required this.onPrimary,
    required this.primaryContainer,
    required this.onPrimaryContainer,
    required this.secondary,
    required this.onSecondary,
    required this.secondaryContainer,
    required this.onSecondaryContainer,
    required this.tertiary,
    required this.onTertiary,
    required this.tertiaryContainer,
    required this.onTertiaryContainer,
    // Status — error / success / warning / info
    required this.error,
    required this.onError,
    required this.errorContainer,
    required this.onErrorContainer,
    required this.success,
    required this.onSuccess,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.warning,
    required this.onWarning,
    required this.warningContainer,
    required this.onWarningContainer,
    required this.info,
    required this.onInfo,
    required this.infoContainer,
    required this.onInfoContainer,
    // Neutrals & surfaces
    required this.background,
    required this.surface,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.surfaceDim,
    required this.surfaceBright,
    required this.surfaceContainerLowest,
    required this.surfaceContainerLow,
    required this.surfaceContainer,
    required this.surfaceContainerHigh,
    required this.surfaceContainerHighest,
    // Text tiers (semantic aliases for legibility across surfaces)
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.textDisabled,
    // Lines
    required this.outline,
    required this.outlineVariant,
    // Inverse (snackbars, tooltips)
    required this.inverseSurface,
    required this.onInverseSurface,
    required this.inversePrimary,
    // Effects
    required this.shadow,
    required this.scrim,
    required this.surfaceTint,
    // Gradient anchors
    required this.gradientBrand,
    required this.gradientPrimary,
    required this.gradientSurface,
  });

  final Brightness brightness;

  final Color primary;
  final Color onPrimary;
  final Color primaryContainer;
  final Color onPrimaryContainer;
  final Color secondary;
  final Color onSecondary;
  final Color secondaryContainer;
  final Color onSecondaryContainer;
  final Color tertiary;
  final Color onTertiary;
  final Color tertiaryContainer;
  final Color onTertiaryContainer;

  final Color error;
  final Color onError;
  final Color errorContainer;
  final Color onErrorContainer;
  final Color success;
  final Color onSuccess;
  final Color successContainer;
  final Color onSuccessContainer;
  final Color warning;
  final Color onWarning;
  final Color warningContainer;
  final Color onWarningContainer;
  final Color info;
  final Color onInfo;
  final Color infoContainer;
  final Color onInfoContainer;

  final Color background;
  final Color surface;
  final Color onSurface;
  final Color onSurfaceVariant;
  final Color surfaceDim;
  final Color surfaceBright;
  final Color surfaceContainerLowest;
  final Color surfaceContainerLow;
  final Color surfaceContainer;
  final Color surfaceContainerHigh;
  final Color surfaceContainerHighest;

  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color textDisabled;

  final Color outline;
  final Color outlineVariant;

  final Color inverseSurface;
  final Color onInverseSurface;
  final Color inversePrimary;

  final Color shadow;
  final Color scrim;
  final Color surfaceTint;

  /// Identity gradient (violet → blue → teal). Used for brand moments/headers.
  final List<Color> gradientBrand;

  /// Primary-action gradient (health-green shades).
  final List<Color> gradientPrimary;

  /// Subtle app-background gradient anchors.
  final List<Color> gradientSurface;

  bool get isDark => brightness == Brightness.dark;

  // ── LIGHT ──────────────────────────────────────────────────────────────────
  static const ForeSeeMePalette light = ForeSeeMePalette(
    brightness: Brightness.light,
    // Brand
    primary: Color(0xFF1E8E4A),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFC9F2D6),
    onPrimaryContainer: Color(0xFF08361A),
    secondary: Color(0xFF0E7C7B),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFC7EEEC),
    onSecondaryContainer: Color(0xFF04302F),
    tertiary: Color(0xFF5B4BD6),
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFFE1DCFB),
    onTertiaryContainer: Color(0xFF1F1663),
    // Status
    error: Color(0xFFC5221F),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFFBD9D6),
    onErrorContainer: Color(0xFF540D0C),
    success: Color(0xFF1E8E4A),
    onSuccess: Color(0xFFFFFFFF),
    successContainer: Color(0xFFC9F2D6),
    onSuccessContainer: Color(0xFF08361A),
    warning: Color(0xFF9A5B00),
    onWarning: Color(0xFFFFFFFF),
    warningContainer: Color(0xFFFDE8C4),
    onWarningContainer: Color(0xFF3F2500),
    info: Color(0xFF1D66C9),
    onInfo: Color(0xFFFFFFFF),
    infoContainer: Color(0xFFD5E3FF),
    onInfoContainer: Color(0xFF0A2A5A),
    // Neutrals & surfaces
    background: Color(0xFFF6F8FA),
    surface: Color(0xFFFFFFFF),
    onSurface: Color(0xFF111826),
    onSurfaceVariant: Color(0xFF46505F),
    surfaceDim: Color(0xFFE4E8EE),
    surfaceBright: Color(0xFFFFFFFF),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFF3F5F8),
    surfaceContainer: Color(0xFFEEF1F5),
    surfaceContainerHigh: Color(0xFFE8ECF1),
    surfaceContainerHighest: Color(0xFFE2E7ED),
    // Text
    textPrimary: Color(0xFF111826),
    textSecondary: Color(0xFF46505F),
    textTertiary: Color(0xFF697280),
    textDisabled: Color(0xFF9AA3AF),
    // Lines
    outline: Color(0xFFCED5DD),
    outlineVariant: Color(0xFFE4E8EE),
    // Inverse
    inverseSurface: Color(0xFF1B2430),
    onInverseSurface: Color(0xFFF1F4F8),
    inversePrimary: Color(0xFF7FE0A0),
    // Effects
    shadow: Color(0xFF0B1A2C),
    scrim: Color(0xFF000000),
    surfaceTint: Color(0xFF1E8E4A),
    // Gradients
    gradientBrand: [Color(0xFF6C4BF0), Color(0xFF3F93E2), Color(0xFF12B5A6)],
    gradientPrimary: [Color(0xFF25A757), Color(0xFF14803C)],
    gradientSurface: [Color(0xFFF7FAFB), Color(0xFFEFF4F1), Color(0xFFF1F1FA)],
  );

  // ── DARK ───────────────────────────────────────────────────────────────────
  static const ForeSeeMePalette dark = ForeSeeMePalette(
    brightness: Brightness.dark,
    // Brand
    primary: Color(0xFF4ADE80),
    onPrimary: Color(0xFF04240F),
    primaryContainer: Color(0xFF14532D),
    onPrimaryContainer: Color(0xFFB7F5C9),
    secondary: Color(0xFF2DD4C4),
    onSecondary: Color(0xFF04302C),
    secondaryContainer: Color(0xFF0F4A46),
    onSecondaryContainer: Color(0xFFA7F0E8),
    tertiary: Color(0xFFA78BFA),
    onTertiary: Color(0xFF23166B),
    tertiaryContainer: Color(0xFF3A2E75),
    onTertiaryContainer: Color(0xFFE4DCFF),
    // Status
    error: Color(0xFFFF6B6B),
    onError: Color(0xFF3B0908),
    errorContainer: Color(0xFF5A1B1A),
    onErrorContainer: Color(0xFFFFD9D6),
    success: Color(0xFF4ADE80),
    onSuccess: Color(0xFF04240F),
    successContainer: Color(0xFF14532D),
    onSuccessContainer: Color(0xFFB7F5C9),
    warning: Color(0xFFFBBF24),
    onWarning: Color(0xFF3A2800),
    warningContainer: Color(0xFF4A3410),
    onWarningContainer: Color(0xFFFDE8C4),
    info: Color(0xFF7FB4FF),
    onInfo: Color(0xFF0A2143),
    infoContainer: Color(0xFF103158),
    onInfoContainer: Color(0xFFD5E3FF),
    // Neutrals & surfaces
    background: Color(0xFF0B0F14),
    surface: Color(0xFF12171E),
    onSurface: Color(0xFFE7ECF2),
    onSurfaceVariant: Color(0xFFAEB8C4),
    surfaceDim: Color(0xFF0B0F14),
    surfaceBright: Color(0xFF2A323C),
    surfaceContainerLowest: Color(0xFF080B10),
    surfaceContainerLow: Color(0xFF12171E),
    surfaceContainer: Color(0xFF161C24),
    surfaceContainerHigh: Color(0xFF1E252E),
    surfaceContainerHighest: Color(0xFF262E38),
    // Text
    textPrimary: Color(0xFFE7ECF2),
    textSecondary: Color(0xFFAEB8C4),
    textTertiary: Color(0xFF8A93A0),
    textDisabled: Color(0xFF5C646F),
    // Lines
    outline: Color(0xFF3A424D),
    outlineVariant: Color(0xFF262E38),
    // Inverse
    inverseSurface: Color(0xFFE7ECF2),
    onInverseSurface: Color(0xFF1B2430),
    inversePrimary: Color(0xFF1E8E4A),
    // Effects
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    surfaceTint: Color(0xFF4ADE80),
    // Gradients
    gradientBrand: [Color(0xFF7158FA), Color(0xFF3F93E2), Color(0xFF0ACCC8)],
    gradientPrimary: [Color(0xFF4ADE80), Color(0xFF2FAE5E)],
    gradientSurface: [Color(0xFF0D0D1A), Color(0xFF121A22), Color(0xFF14121C)],
  );

  /// Resolves the palette for a given [brightness].
  static ForeSeeMePalette of(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;
}
