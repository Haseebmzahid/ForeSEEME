import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// ForeSeeMe Design System **v2** ("Liquid Glass") — the active visual language
/// for Sprint 3 surfaces and the shared components they use.
///
/// Scope (per the Sprint 3 visual-language decision): these tokens style the new
/// risk / resources / alerts surfaces and shared components. The frozen Sprint
/// 1/2 modules (auth, medication, health profile, profile) keep using
/// [AppColors] / [AppTextStyles]; this file does not replace them.
///
/// Source of truth: `docs/ui sprint 3/ForeSeeMe Design System.html`.
class AppColorsV2 {
  AppColorsV2._();

  // ── Shell & glass ──────────────────────────────────────────────────────────
  /// Deep-space app background.
  static const Color shell = Color(0xFF05070F);

  /// Raised shell (cards over the shell).
  static const Color shellRaised = Color(0xFF0C1122);

  /// Translucent glass fill for neutral cards (E1).
  static const Color glassFill = Color(0x0BFFFFFF); // white @ ~.045

  /// Hairline card stroke.
  static const Color stroke = Color(0x1AFFFFFF); // white @ .10

  /// Softer hairline stroke (flat surfaces).
  static const Color strokeSoft = Color(0x0EFFFFFF); // white @ ~.055

  // ── Text tiers ───────────────────────────────────────────────────────────--
  static const Color textPrimary = Color(0xFFEAF0FF);
  static const Color textSecondary = Color(0xFFA4AECB);

  /// Muted label tone used on dark cards in the Sprint 3 screens.
  static const Color textTertiary = Color(0xFF8B96B1);

  /// Faintest hint tone. Raised from `#697391` (≈4.0:1) to meet WCAG AA 4.5:1 on
  /// the glass surface — see `docs/accessibility_audit.md` (Sprint 5, Prompt 15).
  static const Color textFaint = Color(0xFF77819E);

  // ── Brand & accents ─────────────────────────────────────────────────────────
  static const Color brandViolet = Color(0xFF7158FA);
  static const Color brandBlue = Color(0xFF3F93E2);
  static const Color brandTeal = Color(0xFF0ACCC8);

  /// Primary interactive teal.
  static const Color teal = Color(0xFF2FD4C2);
  static const Color violet = Color(0xFF7C6BFF);
  static const Color blue = Color(0xFF5AA9FF);

  // ── Risk & status (always paired with a label + icon — never colour alone) ──
  static const Color riskLow = Color(0xFF35C28A);
  static const Color riskMedium = Color(0xFFF4B740);
  static const Color riskHigh = Color(0xFFF35B6B);
  static const Color riskUncertain = Color(0xFF7C89A6);
}

/// Brand gradient (identity & primary action).
class AppGradientsV2 {
  AppGradientsV2._();

  static const LinearGradient brand = LinearGradient(
    colors: [
      AppColorsV2.brandViolet,
      AppColorsV2.brandBlue,
      AppColorsV2.brandTeal,
    ],
    stops: [0.0, 0.52, 1.0],
    begin: Alignment(-1, -0.3),
    end: Alignment(1, 0.3),
  );
}

/// v2 typography — Sora for display/numerics, Manrope for body/UI.
class AppTextStylesV2 {
  AppTextStylesV2._();

  /// Uppercase tracked micro-label (e.g. "LAHORE · TODAY").
  static TextStyle get microLabel => GoogleFonts.manrope(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.6,
    color: AppColorsV2.textTertiary,
  );

  /// Large risk / numeric headline.
  static TextStyle get headline => GoogleFonts.sora(
    fontSize: 26,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.5,
    color: AppColorsV2.textPrimary,
  );

  /// Card / section title.
  static TextStyle get cardTitle => GoogleFonts.sora(
    fontSize: 18,
    fontWeight: FontWeight.w700,
    color: AppColorsV2.textPrimary,
  );

  /// Standard body text on glass.
  static TextStyle get body => GoogleFonts.manrope(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    height: 1.45,
    color: AppColorsV2.textSecondary,
  );

  /// Small caption / meta line.
  static TextStyle get caption => GoogleFonts.manrope(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: AppColorsV2.textTertiary,
  );
}
