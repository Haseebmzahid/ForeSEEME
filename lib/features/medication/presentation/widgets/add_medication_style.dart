import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:fyp_foreseeme/core/theme/a11y.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';

/// Visual language for the **Add / Edit Medication screen only**, transcribed
/// from the approved prototype (`docs/Design/ForeSeeMe Add Medication (1).html`).
///
/// Why this is local rather than in the app palette: like the Medications Hub
/// and the Profile Hub, this prototype specifies a deep instrument surface — a
/// near-black stage under a teal aurora — but it adds a *liquid glass*
/// material the other two do not have: a 150° white gradient fill (`--lg`), a
/// multi-edge inner rim light (`--lgRim`) and a corner specular (`--lgSpec`).
/// Promoting those to `ForeSeeMePalette` would restyle every other screen.
/// This mirrors `MedicationHubTheme`, `ProfileHubTheme`, `MedOrbitTheme` and
/// `RiskMapTheme`, the prototypes already transcribed this way.
///
/// The values below are the prototype's **own** CSS custom properties, value
/// for value, in both its `DARK` and `LIGHT` sets; the field names track the
/// CSS variable names so the transcription can be checked line by line. Unlike
/// the Medications Hub, nothing needed adjusting for contrast — the prototype
/// already darkens its accent (`#0C8F73`) and warn ink (`#9A6410`) for the lit
/// theme.
///
/// Typography still comes from the design system: sans text uses
/// `context.fsmText` (Space Grotesk — the prototype's own face) and the
/// prototype's mono is the design system's existing IBM Plex Mono telemetry
/// family. No second typography system is introduced.

/// Mono type for the screen's technical labels (section numbers, field
/// captions, times, counts).
///
/// The prototype expresses tracking in `em`; it is converted here to the
/// logical pixels Flutter wants (`size * em`).
TextStyle addMedMono(
  BuildContext context, {
  required double size,
  double em = 0,
  required Color color,
  FontWeight weight = FontWeight.w400,
  double height = 1.2,
}) => context.fsmTelemetry.channel.copyWith(
  fontSize: size,
  letterSpacing: size * em,
  color: color,
  fontWeight: weight,
  height: height,
);

/// Sans type for the screen's prose, at the prototype's exact sizes.
TextStyle addMedSans(
  BuildContext context, {
  required double size,
  required Color color,
  FontWeight weight = FontWeight.w400,
  double em = 0,
  double height = 1.25,
}) => (context.fsmText.titleMedium ?? const TextStyle()).copyWith(
  fontSize: size,
  fontWeight: weight,
  letterSpacing: size * em,
  color: color,
  height: height,
);

/// The prototype's `--lgBlur: blur(30px) saturate(180%) brightness(1.06)`.
///
/// Only the blur is reproduced — Flutter's `BackdropFilter` has no saturation
/// or brightness stage, and the prototype's own fill already carries most of
/// that lift. Routed through [A11y.blurSigma] so the blur is dropped under
/// reduced transparency, where the surfaces beneath turn opaque and must
/// govern contrast on their own.
ui.ImageFilter addMedBlur(BuildContext context, [double sigma = 15]) {
  final resolved = A11y.blurSigma(context, sigma: sigma);
  return ui.ImageFilter.blur(sigmaX: resolved, sigmaY: resolved);
}

/// The prototype's CSS custom properties, per ambient brightness.
@immutable
class AddMedTheme {
  const AddMedTheme({
    required this.bg,
    required this.bg2,
    required this.txt,
    required this.txt2,
    required this.txt3,
    required this.accent,
    required this.onAccent,
    required this.accSoft,
    required this.glow,
    required this.bd,
    required this.bdSoft,
    required this.field,
    required this.fieldBd,
    required this.warn,
    required this.err,
    required this.errSoft,
    required this.sheet,
    required this.shadowColor,
    required this.scrim,
    required this.isDark,
  });

  /// `--bg` — the stage.
  final Color bg;

  /// The lifted stage tone used when transparency is reduced and glass must
  /// collapse to a solid surface. Not a prototype token — the prototype has no
  /// opaque mode.
  final Color bg2;

  /// `--txt` / `--txt2` / `--txt3` — primary, secondary and faint ink.
  final Color txt;
  final Color txt2;
  final Color txt3;

  /// `--accent` / `--onAccent` / `--accSoft` / `--glow`.
  final Color accent;
  final Color onAccent;
  final Color accSoft;
  final Color glow;

  /// `--bd` / `--bdSoft` — hairline borders and the perspective floor grid.
  final Color bd;
  final Color bdSoft;

  /// `--field` / `--fieldBd` — the input surfaces.
  final Color field;
  final Color fieldBd;

  /// `--warn` — the duplicate-time amber.
  final Color warn;

  /// `--err` / `--errSoft` — validation ink and the failed field's fill.
  final Color err;
  final Color errSoft;

  /// `--sheet` — the bottom sheets' translucent fill.
  final Color sheet;

  /// Base colour of `--shadow`; the geometry differs per theme, see [shadow].
  final Color shadowColor;

  /// The sheet scrim: `rgba(3,7,9,0.6)` dark, `rgba(20,40,38,0.34)` light.
  final Color scrim;

  final bool isDark;

  /// Transcribed from the prototype's `DARK` map.
  static const AddMedTheme dark = AddMedTheme(
    bg: Color(0xFF070B0F),
    bg2: Color(0xFF0F161C),
    txt: Color(0xFFE9F1EF),
    txt2: Color(0x8FE9F1EF), // rgba(233,241,239,0.56)
    txt3: Color(0x57E9F1EF), // rgba(233,241,239,0.34)
    accent: Color(0xFF34E0B4),
    onAccent: Color(0xFF06231D),
    accSoft: Color(0x2434E0B4), // rgba(52,224,180,0.14)
    glow: Color(0x3834E0B4), // rgba(52,224,180,0.22)
    bd: Color(0x29FFFFFF), // rgba(255,255,255,0.16)
    bdSoft: Color(0x1AFFFFFF), // rgba(255,255,255,0.10)
    field: Color(0x0DFFFFFF), // rgba(255,255,255,0.05)
    fieldBd: Color(0x24FFFFFF), // rgba(255,255,255,0.14)
    warn: Color(0xFFE9B872),
    err: Color(0xFFFF9683),
    errSoft: Color(0x1FFF9683), // rgba(255,150,131,0.12)
    sheet: Color(0xC70B1115), // rgba(11,17,21,0.78)
    shadowColor: Color(0xFF000000),
    scrim: Color(0x99030709), // rgba(3,7,9,0.6)
    isDark: true,
  );

  /// Transcribed from the prototype's `LIGHT` map.
  static const AddMedTheme light = AddMedTheme(
    bg: Color(0xFFEDF2F2),
    bg2: Color(0xFFFFFFFF),
    txt: Color(0xFF0A1917),
    txt2: Color(0x9E0A1917), // rgba(10,25,23,0.62)
    txt3: Color(0x660A1917), // rgba(10,25,23,0.40)
    accent: Color(0xFF0C8F73),
    onAccent: Color(0xFFFFFFFF),
    accSoft: Color(0x1F0C8F73), // rgba(12,143,115,0.12)
    glow: Color(0x290C8F73), // rgba(12,143,115,0.16)
    bd: Color(0x240A1917), // rgba(10,25,23,0.14)
    bdSoft: Color(0x170A1917), // rgba(10,25,23,0.09)
    field: Color(0xC7FFFFFF), // rgba(255,255,255,0.78)
    fieldBd: Color(0x240A1917), // rgba(10,25,23,0.14)
    warn: Color(0xFF9A6410),
    err: Color(0xFFB23A22),
    errSoft: Color(0x17B23A22), // rgba(178,58,34,0.09)
    sheet: Color(0xE6F0F5F5), // rgba(240,245,245,0.9)
    shadowColor: Color(0xFF0A2824), // rgba(10,40,36,·)
    scrim: Color(0x57142826), // rgba(20,40,38,0.34)
    isDark: false,
  );

  static AddMedTheme of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;

  // ── Materials ──────────────────────────────────────────────────────────────

  /// CSS measures gradient angles clockwise from "to top"; `150deg` therefore
  /// runs from the upper-left down to the lower-right at `tan(30°) = 0.577`
  /// across, which is what this pair of alignments reproduces.
  static const Alignment _gradFrom = Alignment(-0.577, -1.0);
  static const Alignment _gradTo = Alignment(0.577, 1.0);

  /// `--lg` — the glass slab's own fill.
  LinearGradient get lg => LinearGradient(
    begin: _gradFrom,
    end: _gradTo,
    colors: isDark
        ? const [Color(0x24FFFFFF), Color(0x09FFFFFF), Color(0x17FFFFFF)]
        : const [Color(0xF2FFFFFF), Color(0x99FFFFFF), Color(0xDBFFFFFF)],
    stops: const [0.0, 0.46, 1.0],
  );

  /// `--lgTeal` — the *selected* slab's fill.
  LinearGradient get lgTeal => LinearGradient(
    begin: _gradFrom,
    end: _gradTo,
    colors: [
      accent.withValues(alpha: isDark ? 0.30 : 0.20),
      accent.withValues(alpha: isDark ? 0.07 : 0.05),
      accent.withValues(alpha: isDark ? 0.18 : 0.13),
    ],
    stops: const [0.0, 0.48, 1.0],
  );

  /// `--lgSpec` — the corner specular laid over a slab:
  /// `radial-gradient(130% 90% at 18% -14%, …)`.
  RadialGradient get lgSpec => RadialGradient(
    center: const Alignment(-0.64, -1.28), // 18% across, -14% down
    radius: 1.15,
    colors: isDark
        ? const [Color(0x61FFFFFF), Color(0x0FFFFFFF), Color(0x00FFFFFF)]
        : const [Color(0xD9FFFFFF), Color(0x33FFFFFF), Color(0x00FFFFFF)],
    stops: const [0.0, 0.46, 0.66],
  );

  /// `--lgRim`, flattened to the one inner stroke that carries it: the lit lip
  /// along the top edge fading to the dimmer side and bottom edges.
  ///
  /// The CSS declares four directional `inset` shadows plus a 34px inner glow.
  /// A single inner stroke under a vertical gradient reproduces what the eye
  /// reads from that stack; the inner glow sits below the threshold of
  /// visibility at these sizes and is dropped.
  LinearGradient get rim => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: isDark
        ? const [Color(0x8CFFFFFF), Color(0x2EFFFFFF), Color(0x29FFFFFF)]
        : const [Color(0xF2FFFFFF), Color(0x8CFFFFFF), Color(0xB3FFFFFF)],
    stops: const [0.0, 0.5, 1.0],
  );

  /// `--shadow`: `0 22px 44px rgba(0,0,0,0.55)` dark,
  /// `0 18px 34px rgba(10,40,36,0.12)` light.
  List<BoxShadow> get shadow => [
    BoxShadow(
      color: shadowColor.withValues(alpha: isDark ? 0.55 : 0.12),
      blurRadius: isDark ? 44 : 34,
      offset: Offset(0, isDark ? 22 : 18),
    ),
  ];

  /// The lighter shadow the type / frequency cards carry:
  /// `0 14px 24px rgba(0,0,0,0.3)`.
  List<BoxShadow> get cardShadow => [
    BoxShadow(
      color: shadowColor.withValues(alpha: isDark ? 0.30 : 0.09),
      blurRadius: 24,
      offset: const Offset(0, 14),
    ),
  ];

  /// A *selected* type / frequency card:
  /// `0 20px 32px rgba(0,0,0,0.36), 0 0 24px var(--glow)`.
  List<BoxShadow> get selectedCardShadow => [
    BoxShadow(
      color: shadowColor.withValues(alpha: isDark ? 0.36 : 0.11),
      blurRadius: 32,
      offset: const Offset(0, 20),
    ),
    BoxShadow(color: glow, blurRadius: 24),
  ];

  /// The ready CTA: `0 20px 38px rgba(0,0,0,0.4), 0 0 32px var(--glow)`.
  List<BoxShadow> get ctaReadyShadow => [
    BoxShadow(
      color: shadowColor.withValues(alpha: isDark ? 0.40 : 0.13),
      blurRadius: 38,
      offset: const Offset(0, 20),
    ),
    BoxShadow(color: glow, blurRadius: 32),
  ];

  /// The resting CTA: `0 18px 34px rgba(0,0,0,0.4)`.
  List<BoxShadow> get ctaShadow => [
    BoxShadow(
      color: shadowColor.withValues(alpha: isDark ? 0.40 : 0.12),
      blurRadius: 34,
      offset: const Offset(0, 18),
    ),
  ];

  /// `0 16px 30px rgba(0,0,0,0.35), 0 0 26px var(--glow)` — the accent buttons
  /// inside the sheets.
  List<BoxShadow> get accentButtonShadow => [
    BoxShadow(
      color: shadowColor.withValues(alpha: isDark ? 0.35 : 0.12),
      blurRadius: 30,
      offset: const Offset(0, 16),
    ),
    BoxShadow(color: glow, blurRadius: 26),
  ];

  /// The ambient teal aurora behind the header:
  /// `radial-gradient(46% 40% at 52% 32%, var(--glow), transparent 70%)`.
  RadialGradient get auroraFill => RadialGradient(
    center: const Alignment(0.04, -0.36), // 52% across, 32% down
    radius: 0.46,
    colors: [glow, glow.withValues(alpha: 0)],
    stops: const [0.0, 0.7],
  );

  /// The cool orb on the right:
  /// `radial-gradient(50% 50% at 50% 50%, rgba(40,90,140,0.14), transparent 72%)`.
  RadialGradient get orbFill {
    final tint = isDark ? const Color(0xFF285A8C) : const Color(0xFF3E6E9E);
    return RadialGradient(
      colors: [
        tint.withValues(alpha: isDark ? 0.14 : 0.08),
        tint.withValues(alpha: 0),
      ],
      stops: const [0.0, 0.72],
    );
  }

  /// A radial falloff, reused by the preview stage's contact shadow.
  RadialGradient bloom(Color color) => RadialGradient(
    colors: [color, color.withValues(alpha: 0)],
    stops: const [0.0, 0.7],
  );

  /// The header's own backing:
  /// `linear-gradient(to bottom, var(--bg) 62%, transparent)`.
  LinearGradient get headerScrim => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [bg, bg.withValues(alpha: 0)],
    stops: const [0.62, 1.0],
  );

  /// The footer's scrim: `linear-gradient(to top, var(--bg) 44%, transparent)`.
  LinearGradient get footerScrim => LinearGradient(
    begin: Alignment.bottomCenter,
    end: Alignment.topCenter,
    colors: [bg, bg.withValues(alpha: 0)],
    stops: const [0.44, 1.0],
  );

  /// The capsule glyph's two halves:
  /// `linear-gradient(160deg, #7BFFDF, #1E9C86)` and its pale counterpart.
  static const LinearGradient capsuleTeal = LinearGradient(
    begin: Alignment(-0.36, -1.0), // 160deg
    end: Alignment(0.36, 1.0),
    colors: [Color(0xFF7BFFDF), Color(0xFF1E9C86)],
  );

  static const LinearGradient capsulePale = LinearGradient(
    begin: Alignment(-0.36, -1.0),
    end: Alignment(0.36, 1.0),
    colors: [Color(0xEBFFFFFF), Color(0xB8B4CDC8)],
  );

  /// The syrup bottle's fill:
  /// `linear-gradient(180deg, rgba(233,184,114,0.85), rgba(200,140,60,0.75))`.
  static const LinearGradient syrupFill = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xD9E9B872), Color(0xBFC88C3C)],
  );
}
