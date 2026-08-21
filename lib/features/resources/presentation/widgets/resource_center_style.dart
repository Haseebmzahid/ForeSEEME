import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:fyp_foreseeme/core/theme/a11y.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/features/resources/domain/models/resource_article.dart';

/// Visual language for the **Resource Center only**, transcribed from the
/// approved prototype (`docs/Design/ForeSeeMe Resource Center.html`).
///
/// Why this is local rather than in the app palette: like the Medications Hub,
/// the Profile Hub and Add Medication, this prototype specifies its own stage —
/// a near-black field under a teal halo — plus something none of the others
/// have: an **energy-reactive accent**. The whole surface (accent, halo, glow)
/// re-tints from teal to amber to coral as the environmental signal changes.
/// Promoting that to `ForeSeeMePalette` would make every other screen react to
/// risk. This mirrors `AddMedTheme`, `MedicationHubTheme`, `ProfileHubTheme`
/// and `MedOrbitTheme`, the prototypes already transcribed this way.
///
/// The values below are the prototype's **own** CSS custom properties, value
/// for value, in both its `:root` (dark) and `[data-theme="light"]` sets and
/// its four `[data-energy]` overrides, so the transcription can be checked line
/// by line against the stylesheet.
///
/// Typography still comes from the design system: display text uses
/// `context.fsmText` (Space Grotesk — the prototype's own display face) and the
/// prototype's mono is the design system's existing IBM Plex Mono telemetry
/// family. No second typography system is introduced.

/// The prototype's `[data-energy]` states.
///
/// In the prototype these are switched by a scenario picker; in production they
/// are derived from the one risk signal the app already computes — see
/// `resourceFieldEnergy` in `resource_center_state.dart`.
enum ResourceEnergy {
  /// The default `:root` teal — conditions within the typical range.
  calm,

  /// `[data-energy="elevated"]` — amber.
  elevated,

  /// `[data-energy="high"]` — coral.
  high,

  /// `[data-energy="neutral"]` — grey; no environmental signal at all.
  neutral,
}

/// Mono type for the field's technical labels (eyebrows, channel captions,
/// counts, provenance footers).
///
/// The prototype expresses tracking in `em`; it is converted here to the
/// logical pixels Flutter wants (`size * em`).
TextStyle rcMono(
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

/// Display type — the prototype's `'Space Grotesk'` headings and card titles.
TextStyle rcDisplay(
  BuildContext context, {
  required double size,
  required Color color,
  FontWeight weight = FontWeight.w500,
  double em = 0,
  double height = 1.25,
}) => (context.fsmText.titleMedium ?? const TextStyle()).copyWith(
  fontSize: size,
  fontWeight: weight,
  letterSpacing: size * em,
  color: color,
  height: height,
);

/// Body type — the prototype's `'IBM Plex Sans'` prose. The design system's
/// body face stands in for it; no new family is bundled.
TextStyle rcBody(
  BuildContext context, {
  required double size,
  required Color color,
  FontWeight weight = FontWeight.w400,
  double height = 1.45,
}) => (context.fsmText.bodyMedium ?? const TextStyle()).copyWith(
  fontSize: size,
  fontWeight: weight,
  color: color,
  height: height,
);

/// The prototype's `backdrop-filter: blur(Npx)`, routed through
/// [A11y.blurSigma] so the blur is dropped under reduced transparency, where
/// the surfaces beneath turn opaque and must govern contrast on their own.
ui.ImageFilter rcBlur(BuildContext context, [double sigma = 18]) {
  final resolved = A11y.blurSigma(context, sigma: sigma);
  return ui.ImageFilter.blur(sigmaX: resolved, sigmaY: resolved);
}

/// The prototype's `--pad`, which steps with the device width:
/// `[data-w="360"]{--pad:16px}`, `390 → 20`, `430 → 22`.
double rcPad(BuildContext context) {
  final w = MediaQuery.sizeOf(context).width;
  if (w < 375) return 16;
  if (w < 412) return 20;
  return 22;
}

/// The prototype's CSS custom properties, per ambient brightness and
/// [ResourceEnergy].
@immutable
class ResourceCenterTheme {
  const ResourceCenterTheme({
    required this.bg,
    required this.bg2,
    required this.fg,
    required this.dim,
    required this.mono,
    required this.glass,
    required this.glass2,
    required this.line,
    required this.line2,
    required this.teal,
    required this.cyan,
    required this.amber,
    required this.coral,
    required this.accent,
    required this.halo,
    required this.haloS,
    required this.sheet,
    required this.card,
    required this.isDark,
  });

  /// `--bg` / `--bg2` — the stage and its lifted tone.
  final Color bg;
  final Color bg2;

  /// `--fg` / `--dim` / `--mono` — primary ink, secondary ink, telemetry ink.
  final Color fg;
  final Color dim;
  final Color mono;

  /// `--glass` / `--glass2` — the two translucent fills.
  final Color glass;
  final Color glass2;

  /// `--line` / `--line2` — hairline and emphasised hairline.
  final Color line;
  final Color line2;

  /// The fixed category inks: `--teal` / `--cyan` / `--amber` / `--coral`.
  final Color teal;
  final Color cyan;
  final Color amber;
  final Color coral;

  /// `--accent` / `--halo` / `--haloS` — the energy-reactive trio.
  final Color accent;
  final Color halo;
  final Color haloS;

  /// `--sheet` — the bottom sheets' translucent fill.
  final Color sheet;

  /// `--card` — the resource cards' fill.
  final Color card;

  final bool isDark;

  // ── `:root` (dark) ─────────────────────────────────────────────────────────

  static const ResourceCenterTheme _darkBase = ResourceCenterTheme(
    bg: Color(0xFF04090B),
    bg2: Color(0xFF08171A),
    fg: Color(0xFFE9F4F2),
    dim: Color(0xFF93A9A7),
    mono: Color(0xFF6E8785),
    glass: Color(0x0BFFFFFF), // rgba(255,255,255,.045)
    glass2: Color(0x16FFFFFF), // rgba(255,255,255,.085)
    line: Color(0x17FFFFFF), // rgba(255,255,255,.09)
    line2: Color(0x2EFFFFFF), // rgba(255,255,255,.18)
    teal: Color(0xFF3FE3BE),
    cyan: Color(0xFF8FE9FF),
    amber: Color(0xFFF2B25C),
    coral: Color(0xFFFF6E63),
    accent: Color(0xFF3FE3BE),
    halo: Color(0x4D3FE3BE), // rgba(63,227,190,.30)
    haloS: Color(0x293FE3BE), // rgba(63,227,190,.16)
    sheet: Color(0xDB091416), // rgba(9,20,22,.86)
    card: Color(0x0DFFFFFF), // rgba(255,255,255,.05)
    isDark: true,
  );

  // ── `[data-theme="light"]` ─────────────────────────────────────────────────

  static const ResourceCenterTheme _lightBase = ResourceCenterTheme(
    bg: Color(0xFFEAF0EF),
    bg2: Color(0xFFFFFFFF),
    fg: Color(0xFF07191A),
    dim: Color(0xFF4C6462),
    mono: Color(0xFF5B7370),
    glass: Color(0xA8FFFFFF), // rgba(255,255,255,.66)
    glass2: Color(0xE6FFFFFF), // rgba(255,255,255,.9)
    line: Color(0x1A07191A), // rgba(7,25,26,.10)
    line2: Color(0x3807191A), // rgba(7,25,26,.22)
    teal: Color(0xFF0C9C80),
    cyan: Color(0xFF1E8FA8),
    amber: Color(0xFFB9761B),
    coral: Color(0xFFD6402F),
    accent: Color(0xFF0C9C80),
    halo: Color(0x380C9C80), // rgba(12,156,128,.22)
    haloS: Color(0x1A0C9C80), // rgba(12,156,128,.10)
    sheet: Color(0xE6FFFFFF), // rgba(255,255,255,.9)
    card: Color(0x9EFFFFFF), // rgba(255,255,255,.62)
    isDark: false,
  );

  /// The theme for the ambient brightness at [energy].
  ///
  /// The energy overrides are applied exactly as the stylesheet cascades them:
  /// `[data-energy]` sets `--accent`, `--halo` **and** `--haloS`, while the
  /// more specific `[data-theme="light"][data-energy]` rules re-declare only
  /// `--accent` and `--halo` — so a lit, elevated field keeps the amber
  /// `--haloS` from the less specific rule. That is the prototype's real
  /// cascade, not a slip.
  static ResourceCenterTheme of(
    BuildContext context, {
    ResourceEnergy energy = ResourceEnergy.calm,
  }) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final base = dark ? _darkBase : _lightBase;
    return switch (energy) {
      ResourceEnergy.calm => base,
      ResourceEnergy.elevated => base._withEnergy(
        accent: dark ? const Color(0xFFF2B25C) : const Color(0xFFB9761B),
        halo: dark
            ? const Color(0x47F2B25C) // rgba(242,178,92,.28)
            : const Color(0x33B9761B), // rgba(185,118,27,.20)
        haloS: const Color(0x24F2B25C), // rgba(242,178,92,.14)
      ),
      ResourceEnergy.high => base._withEnergy(
        accent: dark ? const Color(0xFFFF6E63) : const Color(0xFFD6402F),
        halo: dark
            ? const Color(0x4DFF6E63) // rgba(255,110,99,.30)
            : const Color(0x33D6402F), // rgba(214,64,47,.20)
        haloS: const Color(0x26FF6E63), // rgba(255,110,99,.15)
      ),
      ResourceEnergy.neutral => base._withEnergy(
        accent: dark ? const Color(0xFF9FB6B4) : const Color(0xFF5B7370),
        halo: dark
            ? const Color(0x2E9FB6B4) // rgba(159,182,180,.18)
            : const Color(0x245B7370), // rgba(91,115,112,.14)
        haloS: const Color(0x179FB6B4), // rgba(159,182,180,.09)
      ),
    };
  }

  ResourceCenterTheme _withEnergy({
    required Color accent,
    required Color halo,
    required Color haloS,
  }) => ResourceCenterTheme(
    bg: bg,
    bg2: bg2,
    fg: fg,
    dim: dim,
    mono: mono,
    glass: glass,
    glass2: glass2,
    line: line,
    line2: line2,
    teal: teal,
    cyan: cyan,
    amber: amber,
    coral: coral,
    accent: accent,
    halo: halo,
    haloS: haloS,
    sheet: sheet,
    card: card,
    isDark: isDark,
  );

  // ── Materials ──────────────────────────────────────────────────────────────

  /// A translucent fill, collapsed onto an opaque surface under reduced
  /// transparency (where [rcBlur] drops the backdrop blur too, so the fill
  /// alone has to carry contrast).
  Color solidify(BuildContext context, Color translucent) {
    if (!A11y.reduceTransparency(context)) return translucent;
    return Color.alphaBlend(translucent, isDark ? bg2 : bg2);
  }

  /// `--sphere` — the field object's own body:
  /// `radial-gradient(circle at 34% 26%,
  ///   rgba(255,255,255,.30), rgba(255,255,255,.05) 24%,
  ///   rgba(6,32,31,.86) 60%, rgba(2,11,12,.97))`.
  ///
  /// Written out at eleven stops rather than the CSS's four, because the two
  /// engines interpolate translucent gradients differently: CSS blends in
  /// **premultiplied** alpha, `Color.lerp` does not. Across the 24% → 60%
  /// span — where a 5%-alpha white runs into an 86%-alpha near-black — that
  /// difference is the whole read of the object: straight interpolation keeps
  /// the white's full luminance while the alpha climbs, and the sphere comes
  /// out a flat pale ball instead of a dark orb with one specular. The stops
  /// below are CSS's own premultiplied result, sampled finely enough that
  /// interpolating between them straight lands within a shade of it.
  RadialGradient get sphere => RadialGradient(
    center: const Alignment(-0.32, -0.48), // 34% across, 26% down
    // CSS `farthest-corner` from that point in a 142px box is 140.8px, and a
    // Flutter radial radius is a fraction of the box's shortest side.
    radius: 0.99,
    colors: isDark
        ? const [
            Color(0x4CFFFFFF),
            Color(0x2DFFFFFF),
            Color(0x0DFFFFFF),
            Color(0x2F3E5251),
            Color(0x52203736),
            Color(0x74142C2B),
            Color(0x960D2625),
            Color(0xB9092322),
            Color(0xDB06201F),
            Color(0xE9041515),
            Color(0xF7020B0C),
          ]
        : const [
            Color(0xF2FFFFFF),
            Color(0xECEBF7F4),
            Color(0xE6D6EEE8),
            Color(0xD7CCE7E1),
            Color(0xC8C0DED8),
            Color(0xB9B2D4CE),
            Color(0xAAA2C9C3),
            Color(0x9B8FBBB5),
            Color(0x8C78AAA4),
            Color(0x8C53807C),
            Color(0x8C2E5654),
          ],
    stops: isDark
        ? const [0, 0.12, 0.24, 0.3, 0.36, 0.42, 0.48, 0.54, 0.6, 0.8, 1]
        : const [0, 0.13, 0.26, 0.32, 0.38, 0.44, 0.5, 0.56, 0.62, 0.81, 1],
  );

  /// The screen's ambient wash, layer 3 of 3:
  /// `linear-gradient(180deg, bg2, bg 46%)`.
  LinearGradient get stageFill => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [bg2, bg],
    stops: const [0.0, 0.46],
  );

  /// Layer 1: `radial-gradient(120% 70% at 50% 0%, haloS, transparent 58%)`.
  RadialGradient get stageHalo => RadialGradient(
    center: Alignment.topCenter,
    radius: 1.2,
    colors: [haloS, haloS.withValues(alpha: 0)],
    stops: const [0.0, 0.58],
  );

  /// Layer 2:
  /// `radial-gradient(90% 50% at 100% 100%, rgba(143,233,255,.05), transparent 60%)`.
  RadialGradient get stageCool {
    final tint = cyan.withValues(alpha: isDark ? 0.05 : 0.06);
    return RadialGradient(
      center: Alignment.bottomRight,
      radius: 0.9,
      colors: [tint, tint.withValues(alpha: 0)],
      stops: const [0.0, 0.6],
    );
  }

  /// A CSS radial gradient with no explicit size ends at the **farthest
  /// corner**; in a square box that is `√2⁄2` of the side. A Flutter radial
  /// radius is a fraction of the shortest side, so every unsized `circle`
  /// gradient transcribed here carries this radius rather than the default
  /// `0.5`, which would end the falloff at the box's edge instead and pull
  /// every glow in by 30%.
  static const double _farthestCorner = 0.7071;

  /// The halo behind the field object:
  /// `radial-gradient(circle at 50% 50%, halo, transparent 64%)`.
  RadialGradient get fieldHalo => RadialGradient(
    radius: _farthestCorner,
    colors: [halo, halo.withValues(alpha: 0)],
    stops: const [0.0, 0.64],
  );

  /// A generic radial falloff, reused by glows and contact shadows.
  RadialGradient bloom(Color color, {double stop = 0.66}) => RadialGradient(
    radius: _farthestCorner,
    colors: [color, color.withValues(alpha: 0)],
    stops: [0.0, stop],
  );

  /// The fade over the bottom of the scroller:
  /// `linear-gradient(180deg, transparent, bg 68%)`.
  LinearGradient get bottomScrim => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [bg.withValues(alpha: 0), bg],
    stops: const [0.0, 0.68],
  );

  /// The emergency banner's fill:
  /// `linear-gradient(100deg, rgba(255,110,99,.16), rgba(255,110,99,.04) 62%)`.
  LinearGradient get emergencyFill => LinearGradient(
    begin: const Alignment(-0.98, -0.17), // 100deg
    end: const Alignment(0.98, 0.17),
    colors: [
      coral.withValues(alpha: isDark ? 0.16 : 0.14),
      coral.withValues(alpha: 0.04),
    ],
    stops: const [0.0, 0.62],
  );

  /// The emergency sheet's primary action:
  /// `linear-gradient(100deg, rgba(255,110,99,.26), rgba(255,110,99,.10))`.
  LinearGradient get emergencyActionFill => LinearGradient(
    begin: const Alignment(-0.98, -0.17),
    end: const Alignment(0.98, 0.17),
    colors: [
      coral.withValues(alpha: isDark ? 0.26 : 0.20),
      coral.withValues(alpha: 0.10),
    ],
  );

  /// The shimmer sweep used by the loading skeletons:
  /// `linear-gradient(90deg, glass 0%, glass2 40%, glass 80%)`, scrolled
  /// across a 320px band by the `shimmer` keyframe.
  LinearGradient get skeletonSweep => LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [glass, glass2, glass],
    stops: const [0.0, 0.4, 0.8],
  );

  /// The lift the prototype applies while a resource card is opening:
  /// `0 26px 50px rgba(0,0,0,.45), 0 0 42px var(--halo)`.
  /// Reversed relative to the CSS list — see the sphere's own shadow in
  /// `resource_center_field.dart`: CSS paints shadows front to back, Flutter
  /// back to front.
  List<BoxShadow> get liftShadow => [
    BoxShadow(color: halo, blurRadius: 42),
    BoxShadow(
      color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.16),
      blurRadius: 50,
      offset: const Offset(0, 26),
    ),
  ];

  /// The bottom sheets' shadow: `0 -20px 60px rgba(0,0,0,.5)`.
  List<BoxShadow> get sheetShadow => [
    BoxShadow(
      color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.18),
      blurRadius: 60,
      offset: const Offset(0, -20),
    ),
  ];
}

// ── Category art ─────────────────────────────────────────────────────────────

/// The prototype's `[data-art]` background treatments. Each resource card,
/// search result and article header carries one; it is what makes a category
/// legible at a glance without resorting to an icon.
enum ResourceArt {
  /// `[data-art="env"]` — a halo wash from the top-left under a cyan veil.
  env,

  /// `[data-art="resp"]` — two soft radials, left and upper-centre.
  resp,

  /// `[data-art="prev"]` — a fine dot lattice.
  prev,

  /// `[data-art="cardio"]` — a diagonal sheen with an amber corner.
  cardio,

  /// `[data-art="emerg"]` — a coral corner wash.
  emerg,
}

/// The art treatment for a stored [ResourceTopic].
///
/// The prototype ships six treatments for six fixture categories. The app
/// stores four topics, so four treatments are used — the prototype's `med`
/// (a grid lattice) has no stored counterpart and is deliberately left unused
/// rather than assigned to an unrelated topic.
ResourceArt resourceArtFor(ResourceTopic topic) => switch (topic) {
  ResourceTopic.airQuality => ResourceArt.env,
  ResourceTopic.lungs => ResourceArt.resp,
  ResourceTopic.asthma => ResourceArt.prev,
  ResourceTopic.heat => ResourceArt.cardio,
  // The prototype's own `emerg` wash, unused until now — a warm corner that
  // pairs with the coral ink below. Nothing existing is re-assigned.
  ResourceTopic.heart => ResourceArt.emerg,
};

/// The prototype's per-category ink, used for a card's eyebrow and its dot:
/// environment → accent, respiratory → cyan, cardiovascular → amber,
/// the quieter categories → dim.
Color resourceCatColor(ResourceCenterTheme theme, ResourceTopic topic) =>
    switch (topic) {
      ResourceTopic.airQuality => theme.accent,
      ResourceTopic.lungs => theme.cyan,
      ResourceTopic.asthma => theme.dim,
      ResourceTopic.heat => theme.amber,
      ResourceTopic.heart => theme.coral,
    };

/// The tracked, upper-case category label the prototype prints on every card.
String resourceCatLabel(ResourceTopic topic) => switch (topic) {
  ResourceTopic.airQuality => 'AIR QUALITY',
  ResourceTopic.lungs => 'LUNGS',
  ResourceTopic.asthma => 'ASTHMA',
  ResourceTopic.heat => 'HEAT',
  ResourceTopic.heart => 'HEART',
};

/// One `[data-art]` layer, sized to its parent. Purely decorative.
class ResourceArtLayer extends StatelessWidget {
  const ResourceArtLayer({super.key, required this.art, required this.theme});

  final ResourceArt art;
  final ResourceCenterTheme theme;

  @override
  Widget build(BuildContext context) {
    final cyanVeil = theme.cyan.withValues(alpha: 0.10);

    return IgnorePointer(
      child: switch (art) {
        // radial(120% 90% at 15% 0%, haloS, transparent 62%) over
        // linear(180deg, rgba(143,233,255,.10), transparent 70%)
        ResourceArt.env => Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [cyanVeil, cyanVeil.withValues(alpha: 0)],
                  stops: const [0.0, 0.7],
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-0.7, -1.0),
                  radius: 1.2,
                  colors: [theme.haloS, theme.haloS.withValues(alpha: 0)],
                  stops: const [0.0, 0.62],
                ),
              ),
            ),
          ],
        ),
        // radial(70% 130% at 4% 60%, haloS, transparent 68%) +
        // radial(50% 90% at 55% 20%, rgba(143,233,255,.10), transparent 70%)
        ResourceArt.resp => Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.1, -0.6),
                  radius: 0.9,
                  colors: [cyanVeil, cyanVeil.withValues(alpha: 0)],
                  stops: const [0.0, 0.7],
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-0.92, 0.2),
                  radius: 1.3,
                  colors: [theme.haloS, theme.haloS.withValues(alpha: 0)],
                  stops: const [0.0, 0.68],
                ),
              ),
            ),
          ],
        ),
        // radial dot lattice, 16px pitch, 1.2px dots, opacity .55
        ResourceArt.prev => Opacity(
          opacity: 0.55,
          child: CustomPaint(
            painter: _DotLatticePainter(
              color: theme.isDark
                  ? const Color(0x4D7DA09E) // rgba(125,160,158,.30)
                  : const Color(0x4D5B7370),
            ),
          ),
        ),
        // linear(105deg, transparent 42%, haloS 50%, transparent 58%) +
        // radial(90% 120% at 90% 100%, rgba(242,178,92,.10), transparent 60%)
        ResourceArt.cardio => Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.8, 1.0),
                  radius: 1.1,
                  colors: [
                    theme.amber.withValues(alpha: 0.10),
                    theme.amber.withValues(alpha: 0),
                  ],
                  stops: const [0.0, 0.6],
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: const Alignment(-0.97, -0.26), // 105deg
                  end: const Alignment(0.97, 0.26),
                  colors: [
                    theme.haloS.withValues(alpha: 0),
                    theme.haloS,
                    theme.haloS.withValues(alpha: 0),
                  ],
                  stops: const [0.42, 0.5, 0.58],
                ),
              ),
            ),
          ],
        ),
        // radial(110% 90% at 0% 0%, rgba(255,110,99,.16), transparent 60%)
        ResourceArt.emerg => DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(-1.0, -1.0),
              radius: 1.3,
              colors: [
                theme.coral.withValues(alpha: 0.16),
                theme.coral.withValues(alpha: 0),
              ],
              stops: const [0.0, 0.6],
            ),
          ),
        ),
      },
    );
  }
}

/// `background-image: radial-gradient(circle, C 1.2px, transparent 1.2px);
/// background-size: 16px 16px`.
class _DotLatticePainter extends CustomPainter {
  const _DotLatticePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    const pitch = 16.0;
    for (var y = pitch / 2; y < size.height; y += pitch) {
      for (var x = pitch / 2; x < size.width; x += pitch) {
        canvas.drawCircle(Offset(x, y), 1.2, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DotLatticePainter old) => old.color != color;
}
