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
///
/// A third, **narrow-purpose** family is defined in [ForeSeeMeTelemetry] — IBM
/// Plex Mono, reserved for instrument readouts (measured values, channel labels,
/// timestamps). It is deliberately NOT part of the [TextTheme]: no Material
/// component should inherit it, and no prose should ever be set in it.
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

/// ForeSeeMe design-system — **instrumentation typography** (resolved from a
/// palette), mirroring the `ForeSeeMeGradients.of` / `ForeSeeMeShadows.of`
/// pattern.
///
/// A measured value is not prose. Environmental readouts, channel labels and
/// telemetry footers are set in a monospaced face (IBM Plex Mono) at tracked,
/// small sizes so columns of digits align, units read as units, and the surface
/// reads as an instrument rather than a card of copy.
///
/// Scope is deliberately narrow — reach for these only when the string is a
/// **measurement or its label**. Everything else stays on [ForeSeeMeTypography].
@immutable
class ForeSeeMeTelemetry {
  const ForeSeeMeTelemetry({
    required this.channel,
    required this.strip,
    required this.readout,
    required this.unit,
    required this.value,
    required this.caption,
  });

  /// Tracked micro-label naming a measurement channel, e.g. `AQI`, `HUMIDITY`.
  final TextStyle channel;

  /// Tracked hairline strip text — coordinates, section rules, provenance.
  final TextStyle strip;

  /// A measured value shown at readout scale, e.g. `148`, `31°`.
  final TextStyle readout;

  /// The unit suffix trailing a [readout], e.g. `%`, ` d`.
  final TextStyle unit;

  /// A telemetry-footer value, e.g. `82%`, `6 min ago`.
  final TextStyle value;

  /// Tracked state caption under a headline, e.g. `ACTIVE FIELD`.
  final TextStyle caption;

  factory ForeSeeMeTelemetry.of(ForeSeeMePalette p) {
    // Tracking is expressed in logical pixels (Flutter), converted from the
    // design's em-relative tracking at each size.
    TextStyle mono(
      double size, {
      required double tracking,
      required Color color,
      FontWeight weight = FontWeight.w400,
    }) => GoogleFonts.ibmPlexMono(
      fontSize: size,
      fontWeight: weight,
      letterSpacing: tracking,
      color: color,
      height: 1.2,
    );

    return ForeSeeMeTelemetry(
      channel: mono(9.5, tracking: 1.9, color: p.textTertiary),
      strip: mono(9.5, tracking: 1.5, color: p.textTertiary),
      readout: GoogleFonts.spaceGrotesk(
        fontSize: 19,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.2,
        height: 1.1,
        color: p.textPrimary,
      ),
      unit: mono(11, tracking: 0, color: p.textSecondary),
      value: mono(13, tracking: 0.2, color: p.textPrimary),
      caption: mono(10, tracking: 1.6, color: p.textSecondary),
    );
  }
}
