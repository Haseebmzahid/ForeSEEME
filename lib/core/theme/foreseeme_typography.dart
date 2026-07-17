import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'foreseeme_palette.dart';

/// ForeSeeMe premium design-system — **typography**.
///
/// A single [TextTheme] built from a [ForeSeeMePalette], so type colour always
/// tracks the active theme and never hard-codes a colour. Two families, matching
/// the direction already established elsewhere in the app:
///
///  * **Space Grotesk** — display / headline / titles (confident, geometric).
///  * **Manrope** — body / labels (highly legible at UI sizes).
///
/// The scale follows Material 3 roles (display → label) so the [TextTheme] drops
/// straight into `ThemeData` and every Material component inherits it.
class ForeSeeMeTypography {
  ForeSeeMeTypography._();

  static TextTheme textTheme(ForeSeeMePalette p) {
    TextStyle display(double size, {double height = 1.12, double spacing = -0.5}) =>
        GoogleFonts.spaceGrotesk(
          fontSize: size,
          height: height,
          fontWeight: FontWeight.w700,
          letterSpacing: spacing,
          color: p.textPrimary,
        );

    TextStyle title(double size, FontWeight weight, {double height = 1.3}) =>
        GoogleFonts.spaceGrotesk(
          fontSize: size,
          height: height,
          fontWeight: weight,
          letterSpacing: 0,
          color: p.textPrimary,
        );

    TextStyle body(
      double size, {
      double height = 1.5,
      FontWeight weight = FontWeight.w400,
      Color? color,
    }) => GoogleFonts.manrope(
      fontSize: size,
      height: height,
      fontWeight: weight,
      color: color ?? p.textPrimary,
    );

    TextStyle label(double size, {double spacing = 0.2, Color? color}) =>
        GoogleFonts.manrope(
          fontSize: size,
          fontWeight: FontWeight.w600,
          letterSpacing: spacing,
          color: color ?? p.textPrimary,
        );

    return TextTheme(
      displayLarge: display(34, height: 1.1),
      displayMedium: display(28, height: 1.14),
      displaySmall: display(24, height: 1.18, spacing: -0.25),
      headlineLarge: title(24, FontWeight.w700, height: 1.22),
      headlineMedium: title(22, FontWeight.w700, height: 1.24),
      headlineSmall: title(20, FontWeight.w600, height: 1.28),
      titleLarge: title(18, FontWeight.w700, height: 1.3),
      titleMedium: title(16, FontWeight.w600, height: 1.35),
      titleSmall: label(14, spacing: 0.1),
      bodyLarge: body(16, height: 1.55),
      bodyMedium: body(14, height: 1.5, color: p.textSecondary),
      bodySmall: body(12, height: 1.45, color: p.textTertiary),
      labelLarge: label(14),
      labelMedium: label(12, spacing: 0.4),
      labelSmall: label(11, spacing: 0.6, color: p.textTertiary),
    );
  }
}
