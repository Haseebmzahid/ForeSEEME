import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:fyp_foreseeme/core/theme/a11y.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/medication_hub_state.dart';

/// Visual language for the **Medications screen only**, transcribed from the
/// approved prototype (`docs/Design/ForeSeeMe Medications.html`).
///
/// Why this is local rather than in the app palette: like the Profile Hub, the
/// prototype specifies a deep instrument surface — a near-black stage under a
/// teal aurora, glass slabs, a neon accent and an amber warning ink — that
/// deliberately differs from the app's product palette. Promoting these values
/// to `ForeSeeMePalette` would restyle every other screen. This mirrors
/// `ProfileHubTheme`, `MedOrbitTheme` and `RiskMapTheme`, the prototypes
/// already transcribed this way.
///
/// The dark values below are the prototype's **own** CSS custom properties,
/// value for value; the field names track the CSS variable names so the
/// transcription can be checked against the source line by line. The
/// Medications prototype shares the Profile Hub's palette exactly and adds one
/// token, `--warn`.
///
/// Typography still comes from the design system: sans text uses
/// `context.fsmText` (Space Grotesk — the prototype's own face) and the
/// prototype's mono is the design system's existing IBM Plex Mono telemetry
/// family via [medHubMono]. No second typography system is introduced.

/// Mono type for the screen's technical labels (times, state captions, counts).
///
/// The prototype expresses tracking in `em`; it is converted here to the
/// logical pixels Flutter wants (`size * em`).
TextStyle medHubMono(
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
TextStyle medHubSans(
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

/// The prototype's `backdrop-filter: blur(Npx)`.
///
/// Routed through [A11y.blurSigma] so the blur is dropped under reduced
/// transparency, where the surfaces beneath it turn opaque and must govern
/// contrast on their own.
ui.ImageFilter medHubBlur(BuildContext context, double sigma) {
  final resolved = A11y.blurSigma(context, sigma: sigma);
  return ui.ImageFilter.blur(sigmaX: resolved, sigmaY: resolved);
}

/// How far the user's text-size setting has been turned up, `1.0` at the
/// system default.
///
/// The rail's tiles are the one place on this screen with a *fixed* geometry —
/// the prototype sizes them in pixels — so they are the one place that has to
/// grow deliberately rather than reflow. Everything else on the screen wraps.
double medHubTextScale(BuildContext context) =>
    (MediaQuery.textScalerOf(context).scale(14) / 14).clamp(1.0, 2.2);

/// The prototype's `76px` tile (`92px` when promoted), widened with the text
/// scale so a larger caption still fits inside it.
double medHubTileWidth(BuildContext context, {required bool isNext}) {
  final base = isNext ? 92.0 : 76.0;
  return base * (1 + (medHubTextScale(context) - 1) * 0.6);
}

/// Where the rail's timeline rule crosses the tiles: the vertical centre of a
/// resting tile's glyph disc.
///
/// `8` rail padding + `12` tile padding + the time line + `8` gap + half the
/// `30px` disc — the prototype's own `top: 58px` at the default text size.
double medHubRailRuleTop(BuildContext context) =>
    8 + 12 + 13.2 * medHubTextScale(context) + 8 + 15;

/// The prototype's CSS custom properties, per ambient brightness.
@immutable
class MedicationHubTheme {
  const MedicationHubTheme({
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
    required this.track2,
    required this.warn,
    required this.onAccent,
    required this.isDark,
  });

  /// `--bg` — the stage.
  final Color bg;

  /// The lifted stage tone used when transparency is reduced and glass must
  /// collapse to a solid surface. Not a prototype token — the prototype has no
  /// opaque mode.
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

  /// Base colour of `--shadow`. The shadow geometry differs between themes;
  /// see [slabShadow].
  final Color shadowColor;

  /// `--track2` — the inert dot and ring on a `LATER` dose tile.
  final Color track2;

  /// `--warn` — the missed/skipped amber.
  final Color warn;

  /// Ink drawn *on* the accent (the prototype's `#06231D` check glyph and
  /// arrow chip).
  final Color onAccent;

  final bool isDark;

  /// Transcribed from the prototype's `:root` custom properties.
  static const MedicationHubTheme dark = MedicationHubTheme(
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
    track2: Color(0x4DFFFFFF), // rgba(255,255,255,0.30)
    warn: Color(0xFFE9B872),
    onAccent: Color(0xFF06231D),
    isDark: true,
  );

  /// Light counterpart, matching the Profile Hub's light transcription so the
  /// two screens read as one product in a lit room.
  ///
  /// Two values are not the prototype's, for the same reason they were changed
  /// on the Profile Hub: `#34E0B4` and `#E9B872` cannot carry AA contrast on a
  /// pale slab, so the accent and the warn ink move to darker tones of the same
  /// hues. Everything else is the prototype's own value.
  static const MedicationHubTheme light = MedicationHubTheme(
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
    track2: Color(0x470A201E), // rgba(10,32,30,0.28)
    warn: Color(0xFF8A5A12),
    onAccent: Color(0xFFF2FFFB),
    isDark: false,
  );

  static MedicationHubTheme of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;

  /// Ink for a dose phase: the accent for taken/next, the warn amber for
  /// missed/skipped, secondary ink for later.
  Color inkFor(HubDosePhase phase) => switch (phase) {
    HubDosePhase.taken || HubDosePhase.next => accent,
    HubDosePhase.missed || HubDosePhase.skipped => warn,
    HubDosePhase.later => txt2,
  };

  /// Ink for a medication card's status chip.
  Color inkForStatus(HubMedicationStatus status) => switch (status) {
    HubMedicationStatus.allTaken || HubMedicationStatus.onTrack => accent,
    HubMedicationStatus.behind => warn,
    HubMedicationStatus.noSchedule => txt2,
  };

  /// `--shadow`: `0 22px 44px rgba(0,0,0,0.55)` dark,
  /// `0 18px 36px rgba(16,42,40,0.14)` light.
  List<BoxShadow> get slabShadow => [
    BoxShadow(
      color: shadowColor.withValues(alpha: isDark ? 0.55 : 0.14),
      blurRadius: isDark ? 44 : 36,
      offset: Offset(0, isDark ? 22 : 18),
    ),
  ];

  /// The lighter shadow the rail tiles and the hero chips carry:
  /// `0 14px 26px rgba(0,0,0,0.4)`.
  List<BoxShadow> get tileShadow => [
    BoxShadow(
      color: shadowColor.withValues(alpha: isDark ? 0.40 : 0.10),
      blurRadius: 26,
      offset: const Offset(0, 14),
    ),
  ];

  /// The medication card's fill:
  /// `linear-gradient(158deg, var(--glass2), var(--glass))`.
  ///
  /// CSS measures gradient angles clockwise from "to top"; 158° therefore runs
  /// from the upper-left down to the lower-right, which is what the pair of
  /// alignments below reproduces.
  LinearGradient get slabFill => LinearGradient(
    begin: const Alignment(-0.42, -1.0),
    end: const Alignment(0.42, 1.0),
    colors: [glass2, glass],
  );

  /// The promoted `NEXT UP` tile and the FAB:
  /// `linear-gradient(158deg, rgba(52,224,180,0.16), var(--glass))`.
  LinearGradient accentFill({double from = 0.16}) => LinearGradient(
    begin: const Alignment(-0.42, -1.0),
    end: const Alignment(0.42, 1.0),
    colors: [accent.withValues(alpha: from), glass],
  );

  /// The Check-In slab:
  /// `linear-gradient(158deg, rgba(52,224,180,0.20), rgba(255,255,255,0.05))`.
  LinearGradient get checkInFill => LinearGradient(
    begin: const Alignment(-0.42, -1.0),
    end: const Alignment(0.42, 1.0),
    colors: [
      accent.withValues(alpha: 0.20),
      isDark ? const Color(0x0DFFFFFF) : const Color(0x99FFFFFF),
    ],
  );

  /// The ambient teal aurora behind the hero:
  /// `radial-gradient(46% 40% at 52% 30%, var(--glow), transparent 70%)`.
  ///
  /// CSS gives the ellipse explicit half-extents; on the layer's own box both
  /// work out at ~0.46 of the shorter side, which is what Flutter's `radius`
  /// measures against.
  RadialGradient get auroraFill => RadialGradient(
    center: const Alignment(0.04, -0.4), // 52% across, 30% down
    radius: 0.46,
    colors: [glow, glow.withValues(alpha: 0)],
    stops: const [0.0, 0.7],
  );

  /// The cool orb on the right:
  /// `radial-gradient(50% 50% at 50% 50%, rgba(40,90,140,0.16), transparent 72%)`.
  RadialGradient get orbFill {
    final tint = isDark ? const Color(0xFF285A8C) : const Color(0xFF3E6E9E);
    return RadialGradient(
      colors: [
        tint.withValues(alpha: isDark ? 0.16 : 0.09),
        tint.withValues(alpha: 0),
      ],
      stops: const [0.0, 0.72],
    );
  }

  /// A radial falloff reused by the hero capsule's halo and the contact shadow:
  /// `radial(50% 50% at 50% 50%, colour, transparent 70%)`.
  RadialGradient bloom(Color color) => RadialGradient(
    colors: [color, color.withValues(alpha: 0)],
    stops: const [0.0, 0.7],
  );

  /// The rail's timeline rule:
  /// `linear-gradient(90deg, var(--accent), rgba(52,224,180,0.35) 42%,
  /// var(--line) 44%, var(--line) 100%)` — the elapsed part of the day lit, the
  /// rest inert. [progress] is how far through today's doses the user is.
  LinearGradient railRule(double progress) {
    final p = progress.clamp(0.0, 1.0);
    return LinearGradient(
      colors: [accent, accent.withValues(alpha: 0.35), line, line],
      stops: [0.0, p * 0.95, (p * 0.95 + 0.02).clamp(0.0, 1.0), 1.0],
    );
  }

  /// The bottom bar's scrim:
  /// `linear-gradient(to top, var(--bg) 46%, rgba(7,11,15,0.6) 76%, transparent)`.
  LinearGradient get bottomScrim => LinearGradient(
    begin: Alignment.bottomCenter,
    end: Alignment.topCenter,
    colors: [bg, bg.withValues(alpha: 0.6), bg.withValues(alpha: 0)],
    stops: const [0.46, 0.76, 1.0],
  );
}
