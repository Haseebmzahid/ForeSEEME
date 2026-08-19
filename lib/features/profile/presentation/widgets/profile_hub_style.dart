import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:fyp_foreseeme/core/theme/a11y.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';

/// Visual language for the **Profile Hub screen only**, transcribed from the
/// approved prototype (`docs/Design/ForeSeeMe Profile Hub (1).html`).
///
/// Why this is local rather than in the app palette: the prototype specifies a
/// deep instrument surface — a near-black stage under a teal aurora, glass
/// slabs and a neon accent — that deliberately differs from the app's product
/// palette. Promoting these values to `ForeSeeMePalette` would restyle every
/// other screen. This mirrors `RiskMapTheme` and `MedOrbitTheme`, the two
/// prototypes already transcribed this way.
///
/// Both themes below are the prototype's **own** `THEMES` map, value for value.
/// Typography still comes from the design system: sans text uses
/// `context.fsmText` (Space Grotesk — the prototype's own face) and the
/// prototype's mono is the design system's existing IBM Plex Mono telemetry
/// family via [hubMono]. No second typography system is introduced.

/// Mono type for the hub's technical labels (chips, readouts, captions).
///
/// The prototype expresses tracking in `em`; it is converted here to the
/// logical pixels Flutter wants (`size * em`).
TextStyle hubMono(
  BuildContext context, {
  required double size,
  double em = 0,
  required Color color,
  FontWeight weight = FontWeight.w400,
  double height = 1.25,
}) => context.fsmTelemetry.channel.copyWith(
  fontSize: size,
  letterSpacing: size * em,
  color: color,
  fontWeight: weight,
  height: height,
);

/// The prototype's `backdrop-filter: blur(Npx)`.
///
/// Routed through [A11y.blurSigma] so the blur is dropped under reduced
/// transparency, where the surfaces beneath it turn opaque and must govern
/// contrast on their own.
ui.ImageFilter hubBlur(BuildContext context, double sigma) {
  final resolved = A11y.blurSigma(context, sigma: sigma);
  return ui.ImageFilter.blur(sigmaX: resolved, sigmaY: resolved);
}

/// Sans type for the hub's prose, at the prototype's exact sizes.
TextStyle hubSans(
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

/// The prototype's CSS custom properties, per ambient brightness.
///
/// Field names track the prototype's variable names so the transcription can be
/// checked against the source line by line.
@immutable
class ProfileHubTheme {
  const ProfileHubTheme({
    required this.bg,
    required this.bg2,
    required this.glass,
    required this.glass2,
    required this.line,
    required this.hi,
    required this.txt,
    required this.txt2,
    required this.accent,
    required this.accentSoft,
    required this.glow,
    required this.shadowColor,
    required this.slab,
    required this.slab2,
    required this.track,
    required this.track2,
    required this.coreStops,
    required this.coreTxt,
    required this.coreTxt2,
    required this.operatorInk,
    required this.isDark,
  });

  /// `--bg` — the stage.
  final Color bg;

  /// `--bg2` — the lifted stage tone.
  final Color bg2;

  /// `--glass` / `--glass2` — the two translucent slab fills.
  final Color glass;
  final Color glass2;

  /// `--line` — hairline borders and the perspective floor grid.
  final Color line;

  /// `--hi` — the lit lip along a slab's top edge (`inset 0 1px 0`).
  final Color hi;

  /// `--txt` / `--txt2` — primary and secondary ink.
  final Color txt;
  final Color txt2;

  /// `--accent` / `--accent-soft` / `--glow`.
  final Color accent;
  final Color accentSoft;
  final Color glow;

  /// Base colour of `--shadow`. The prototype's shadow geometry differs between
  /// themes; see [slabShadow].
  final Color shadowColor;

  /// `--slab`, and the second stop of the admin slab's gradient.
  final Color slab;
  final Color slab2;

  /// `--track` / `--track2` — unfilled progress and inert dots.
  final Color track;
  final Color track2;

  /// `--core` — the three stops of the hero core's radial gradient.
  final List<Color> coreStops;

  /// `--coreTxt` / `--coreTxt2` — ink inside the hero core.
  final Color coreTxt;
  final Color coreTxt2;

  /// The admin slab's `OPERATOR` amber.
  final Color operatorInk;

  final bool isDark;

  /// Transcribed from `THEMES.dark`.
  static const ProfileHubTheme dark = ProfileHubTheme(
    bg: Color(0xFF070B0F),
    bg2: Color(0xFF0B1219),
    glass: Color(0x0BFFFFFF), // rgba(255,255,255,0.045)
    glass2: Color(0x16FFFFFF), // rgba(255,255,255,0.085)
    line: Color(0x1AFFFFFF), // rgba(255,255,255,0.10)
    hi: Color(0x17FFFFFF), // rgba(255,255,255,0.09)
    txt: Color(0xFFE9F1EF),
    txt2: Color(0x8FE9F1EF), // rgba(233,241,239,0.56)
    accent: Color(0xFF34E0B4),
    accentSoft: Color(0x2434E0B4), // rgba(52,224,180,0.14)
    glow: Color(0x3834E0B4), // rgba(52,224,180,0.22)
    shadowColor: Color(0xFF000000),
    slab: Color(0xB8060B0F), // rgba(6,11,15,0.72)
    slab2: Color(0x8C0A1218), // rgba(10,18,24,0.55)
    track: Color(0x1AFFFFFF), // rgba(255,255,255,0.10)
    track2: Color(0x4DFFFFFF), // rgba(255,255,255,0.30)
    coreStops: [
      Color(0x6B78FFE1), // rgba(120,255,225,0.42)
      Color(0x57185658), // rgba(24,86,88,0.34)
      Color(0xDB060E13), // rgba(6,14,19,0.86)
    ],
    coreTxt: Color(0xFFE9F1EF),
    coreTxt2: Color(0x9EE9F1EF), // rgba(233,241,239,0.62)
    operatorInk: Color(0xFFE9B872),
    isDark: true,
  );

  /// Transcribed from `THEMES.light`.
  ///
  /// One value is not the prototype's: the `OPERATOR` amber. `#E9B872` on a
  /// pale slab measures well under AA, and the admin row is an access-state
  /// readout that has to stay readable, so the light theme darkens it to the
  /// same hue at usable contrast. Every other value is the prototype's own.
  static const ProfileHubTheme light = ProfileHubTheme(
    bg: Color(0xFFEBF0EF),
    bg2: Color(0xFFFFFFFF),
    glass: Color(0x8CFFFFFF), // rgba(255,255,255,0.55)
    glass2: Color(0xD9FFFFFF), // rgba(255,255,255,0.85)
    line: Color(0x1F0A201E), // rgba(10,32,30,0.12)
    hi: Color(0xE6FFFFFF), // rgba(255,255,255,0.9)
    txt: Color(0xFF0A1614),
    txt2: Color(0x940A1614), // rgba(10,22,20,0.58)
    accent: Color(0xFF0C9B79),
    accentSoft: Color(0x1F0C9B79), // rgba(12,155,121,0.12)
    glow: Color(0x2E0C9B79), // rgba(12,155,121,0.18)
    shadowColor: Color(0xFF102A28), // rgba(16,42,40,·)
    slab: Color(0xBFFFFFFF), // rgba(255,255,255,0.75)
    slab2: Color(0x8CFFFFFF),
    track: Color(0x240A201E), // rgba(10,32,30,0.14)
    track2: Color(0x470A201E), // rgba(10,32,30,0.28)
    // The prototype's light core is deliberately dark: it frames a photo.
    coreStops: [
      Color(0xF2245C56), // rgba(36,92,86,0.95)
      Color(0xF00E3434), // rgba(14,52,52,0.94)
      Color(0xF5061A1C), // rgba(6,26,28,0.96)
    ],
    coreTxt: Color(0xFFEAF6F2),
    coreTxt2: Color(0xB3EAF6F2), // rgba(234,246,242,0.7)
    operatorInk: Color(0xFF8A5A12),
    isDark: false,
  );

  static ProfileHubTheme of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;

  /// `--shadow`: `0 22px 44px rgba(0,0,0,0.55)` dark,
  /// `0 18px 36px rgba(16,42,40,0.14)` light.
  List<BoxShadow> get slabShadow => [
    BoxShadow(
      color: shadowColor.withValues(alpha: isDark ? 0.55 : 0.14),
      blurRadius: isDark ? 44 : 36,
      offset: Offset(0, isDark ? 22 : 18),
    ),
  ];

  /// The card fill: `linear-gradient(158deg, var(--glass2), var(--glass))`.
  ///
  /// CSS measures gradient angles clockwise from "to top"; 158° therefore runs
  /// from the upper-left down to the lower-right, which is what the pair of
  /// alignments below reproduces.
  LinearGradient get slabFill => LinearGradient(
    begin: const Alignment(-0.42, -1.0),
    end: const Alignment(0.42, 1.0),
    colors: [glass2, glass],
  );

  /// The About card's quieter fill:
  /// `linear-gradient(158deg, var(--glass), rgba(255,255,255,0.02))`.
  LinearGradient get slabFillQuiet => LinearGradient(
    begin: const Alignment(-0.42, -1.0),
    end: const Alignment(0.42, 1.0),
    colors: [
      glass,
      isDark ? const Color(0x05FFFFFF) : const Color(0x0A0A201E),
    ],
  );

  /// The admin slab: `linear-gradient(160deg, var(--slab), rgba(10,18,24,0.55))`.
  LinearGradient get adminFill => LinearGradient(
    begin: const Alignment(-0.36, -1.0),
    end: const Alignment(0.36, 1.0),
    colors: [slab, slab2],
  );

  /// The hero core's `--core` radial gradient
  /// (`circle at 34% 28%`, stops at 0 / 46% / 100%).
  ///
  /// `circle` with the CSS default `farthest-corner` sizing: from (34%, 28%)
  /// the farthest corner of a 132px box is 128.9px away, which is 0.977 of the
  /// box — the fraction Flutter's `radius` is measured in.
  RadialGradient get coreFill => RadialGradient(
    center: const Alignment(-0.32, -0.44), // 34% across, 28% down
    radius: 0.977,
    colors: coreStops,
    stops: const [0.0, 0.46, 1.0],
  );

  /// The ambient teal aurora behind the hero:
  /// `radial-gradient(48% 42% at 50% 30%, var(--glow), transparent 70%)`.
  ///
  /// CSS gives the ellipse explicit half-extents (48% of the box's width, 42%
  /// of its height); on the layer's own 546×620 box both work out at ~261px,
  /// i.e. 0.48 of the shorter side — which is what Flutter's `radius` measures
  /// against. Reading the 48% as a Flutter radius directly would make the glow
  /// half again too wide and wash the whole top of the screen.
  RadialGradient get auroraFill => RadialGradient(
    center: const Alignment(0, -0.4), // 30% down
    radius: 0.48,
    colors: [glow, glow.withValues(alpha: 0)],
    stops: const [0.0, 0.7],
  );

  /// The cool orb in the lower left:
  /// `radial-gradient(50% 50% at 50% 50%, rgba(40,90,140,0.18), transparent 72%)`.
  RadialGradient get orbFill {
    final tint = isDark ? const Color(0xFF285A8C) : const Color(0xFF3E6E9E);
    return RadialGradient(
      colors: [
        tint.withValues(alpha: isDark ? 0.18 : 0.10),
        tint.withValues(alpha: 0),
      ],
      stops: const [0.0, 0.72],
    );
  }

  /// A radial falloff reused by the hero's core halo and the Health Profile
  /// card's corner bloom: `radial(50% 50% at 50% 50%, glow, transparent 70%)`.
  RadialGradient get bloomFill => RadialGradient(
    colors: [glow, glow.withValues(alpha: 0)],
    stops: const [0.0, 0.7],
  );

  /// The Health Profile progress fill:
  /// `linear-gradient(90deg, rgba(52,224,180,0.5), var(--accent))`.
  LinearGradient get progressFill => LinearGradient(
    colors: [accent.withValues(alpha: 0.5), accent],
  );

  /// The shared accent-tinted tile gradient used by the theme knob (160°) and
  /// the Health Profile icon tile (150°).
  LinearGradient accentTile({
    required double from,
    required double to,
    required Alignment begin,
    required Alignment end,
  }) => LinearGradient(
    begin: begin,
    end: end,
    colors: [accent.withValues(alpha: from), accent.withValues(alpha: to)],
  );
}
