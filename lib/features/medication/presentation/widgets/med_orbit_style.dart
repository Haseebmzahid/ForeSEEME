import 'package:flutter/material.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/features/medication/domain/services/dose_state_engine.dart';

/// Visual language for the **Daily Check-In screen only**, transcribed from the
/// approved prototype (`docs/Design/Medication Orbit (standalone).html`).
///
/// Why this is local rather than in the app palette: the prototype specifies a
/// spatial "orbit" surface — a near-black stage, a receding temporal floor and
/// physically-lit medication objects — that deliberately differs from the app's
/// product palette. Promoting these values to `ForeSeeMePalette` would restyle
/// every other screen, so they live here and are consumed only by Daily
/// Check-In. This mirrors `RiskMapTheme` in the risk feature.
///
/// Typography still comes from the design system: sans text uses
/// `context.fsmText`, and the prototype's mono face is the design system's
/// existing IBM Plex Mono telemetry family via [medMono]. No second typography
/// system is introduced.

/// Mono type for the screen's technical labels (times, state captions, counts).
///
/// The prototype expresses tracking in `em`; it is converted here to the
/// logical pixels Flutter wants (`size * em`).
TextStyle medMono(
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

/// How the orbit draws a dose. Derived from the app's own [DoseStateResult] —
/// this enum is a *rendering* phase, never a source of scheduling truth.
enum MedOrbitPhase {
  /// Confirmed taken.
  taken,

  /// Skipped or missed — the prototype recedes and desaturates both.
  inactive,

  /// The next actionable dose: the visual hero.
  next,

  /// Scheduled but not yet actionable (later today, or a future day).
  pending,
}

/// Time-of-day band, using the prototype's own boundaries. Purely visual —
/// it drives the meridian rail and the stage atmosphere, never scheduling.
enum MedPeriod {
  morning,
  afternoon,
  evening,
  night;

  static MedPeriod ofMinutes(int minutes) {
    if (minutes < 720) return MedPeriod.morning;
    if (minutes < 1020) return MedPeriod.afternoon;
    if (minutes < 1260) return MedPeriod.evening;
    return MedPeriod.night;
  }

  /// Rail anchor of the band's midpoint (`MORNING 09:00`, `AFTERNOON 14:30`, …).
  int get railMidpoint => switch (this) {
    MedPeriod.morning => 540,
    MedPeriod.afternoon => 870,
    MedPeriod.evening => 1140,
    MedPeriod.night => 1350,
  };

  String get label => switch (this) {
    MedPeriod.morning => 'MORNING',
    MedPeriod.afternoon => 'AFTERNOON',
    MedPeriod.evening => 'EVENING',
    MedPeriod.night => 'NIGHT',
  };
}

/// The prototype maps a minute-of-day onto the meridian rail over a 06:00 →
/// 24:00 span. Clamped so a pre-dawn dose still lands on the rail.
double medRailFraction(int minutes) =>
    ((minutes - 360) / (1440 - 360)).clamp(0.0, 1.0);

/// How a medication object is *lit* for a given phase.
///
/// These are the physical colours of the object on the stage, so — like
/// `RiskFieldStyle` — they are constant across light and dark: the pill does
/// not change colour when the room does. Text colours that must stay legible
/// against the surface live on [MedOrbitTheme] instead.
@immutable
class MedDoseTint {
  const MedDoseTint({
    required this.solid,
    required this.glow,
    required this.glowAlpha,
    required this.label,
  });

  /// Body fill of the capsule / tablet.
  final Color solid;

  /// Halo colour behind the object.
  final Color glow;

  /// Halo alpha when the object holds focus.
  final double glowAlpha;

  /// Colour of the object's trailing time label.
  final Color label;

  static const MedDoseTint taken = MedDoseTint(
    solid: Color(0xFF3B7E6D),
    glow: Color(0xFF3E9680), // rgb(62,150,128)
    glowAlpha: 0.22,
    label: Color(0xFF5F8A82),
  );
  static const MedDoseTint inactive = MedDoseTint(
    solid: Color(0xFF6C6A62),
    glow: Color(0xFF827E74), // rgb(130,126,116)
    glowAlpha: 0.14,
    label: Color(0xFF7E7A70),
  );
  static const MedDoseTint next = MedDoseTint(
    solid: Color(0xFF2ECFA9),
    glow: Color(0xFF2ECFA9),
    glowAlpha: 0.40,
    label: Color(0xFF8FE6CF),
  );
  static const MedDoseTint pending = MedDoseTint(
    solid: Color(0xFFD79E52),
    glow: Color(0xFFD79E52),
    glowAlpha: 0.26,
    label: Color(0xFFC9A171),
  );

  static MedDoseTint of(MedOrbitPhase phase) => switch (phase) {
    MedOrbitPhase.taken => taken,
    MedOrbitPhase.inactive => inactive,
    MedOrbitPhase.next => next,
    MedOrbitPhase.pending => pending,
  };
}

/// Surface + ink values for the orbit stage, per ambient brightness.
@immutable
class MedOrbitTheme {
  const MedOrbitTheme({
    required this.bgTop,
    required this.bgMid,
    required this.bgBottom,
    required this.panel,
    required this.ink,
    required this.ink2,
    required this.ink3,
    required this.ink4,
    required this.ink5,
    required this.ink6,
    required this.grid,
    required this.hair,
    required this.accent,
    required this.takeStart,
    required this.takeEnd,
    required this.onTake,
    required this.stateTaken,
    required this.stateInactive,
    required this.statePending,
    required this.groundShadow,
    required this.atmosphereAlpha,
    required this.isDark,
  });

  /// Stage gradient stops, top → 58% → bottom.
  final Color bgTop;
  final Color bgMid;
  final Color bgBottom;

  /// Fill of the bottom focus panel.
  final Color panel;

  /// Primary ink.
  final Color ink;

  /// Secondary ink — detail values.
  final Color ink2;

  /// Readout ink — meridiem, dosage.
  final Color ink3;

  /// Interactive-chrome ink — arrows, skip label.
  final Color ink4;

  /// Muted technical ink — counts, detail keys.
  final Color ink5;

  /// Faintest technical ink — day caption, rail labels.
  final Color ink6;

  /// Base hue of the temporal floor grid.
  final Color grid;

  /// Hairline rule.
  final Color hair;

  /// Interface accent (the prototype's `#2ECFA9`, darkened for light rooms).
  final Color accent;

  /// TAKE NOW gradient, top → bottom, and its content ink.
  final Color takeStart;
  final Color takeEnd;
  final Color onTake;

  /// Panel state caption colours.
  final Color stateTaken;
  final Color stateInactive;
  final Color statePending;

  /// Contact shadow cast by an object onto the floor.
  final Color groundShadow;

  /// Multiplier applied to the atmosphere wash, so it stays a whisper in a
  /// light room.
  final double atmosphereAlpha;

  final bool isDark;

  static const MedOrbitTheme dark = MedOrbitTheme(
    bgTop: Color(0xFF0A1315),
    bgMid: Color(0xFF070C0D),
    bgBottom: Color(0xFF04090A),
    panel: Color(0xFF060B0C),
    ink: Color(0xFFE4EFED),
    ink2: Color(0xFFC7D8D6),
    ink3: Color(0xFF8AA5A6),
    ink4: Color(0xFF7C9698),
    ink5: Color(0xFF6E8A8C),
    ink6: Color(0xFF4E6A6E),
    grid: Color(0xFF96D7CD), // rgb(150,215,205)
    hair: Color(0x0FFFFFFF), // rgba(255,255,255,.06)
    accent: Color(0xFF2ECFA9),
    takeStart: Color(0xFF4FE0BC),
    takeEnd: Color(0xFF22C39E),
    onTake: Color(0xFF03211B),
    stateTaken: Color(0xFF5F9C8A),
    stateInactive: Color(0xFF9C948A),
    statePending: Color(0xFFC9A171),
    groundShadow: Color(0xFF000000),
    atmosphereAlpha: 1.0,
    isDark: true,
  );

  /// Light counterpart. The stage keeps its instrument geometry but is lit as
  /// paper: inks are darkened to hold AA against a pale bed, and the accent
  /// moves off the prototype's neon teal, which cannot carry contrast on white.
  static const MedOrbitTheme light = MedOrbitTheme(
    bgTop: Color(0xFFF2F6F5),
    bgMid: Color(0xFFEBF0EF),
    bgBottom: Color(0xFFE1E8E7),
    panel: Color(0xFFF6FAF9),
    ink: Color(0xFF0E1618),
    ink2: Color(0xFF33474A),
    ink3: Color(0xFF4A5F63),
    ink4: Color(0xFF52676B),
    ink5: Color(0xFF5B7074),
    ink6: Color(0xFF6B8084),
    grid: Color(0xFF3E7E75),
    hair: Color(0x140E1618),
    accent: Color(0xFF0E8A72),
    takeStart: Color(0xFF1CB593),
    takeEnd: Color(0xFF0C7C67),
    onTake: Color(0xFFF2FFFB),
    stateTaken: Color(0xFF2C7A66),
    stateInactive: Color(0xFF6B6459),
    statePending: Color(0xFF8A6220),
    groundShadow: Color(0xFF3B4A4C),
    atmosphereAlpha: 0.55,
    isDark: false,
  );

  static MedOrbitTheme of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;

  /// The prototype's stage gradient.
  LinearGradient get stage => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [bgTop, bgMid, bgBottom],
    stops: const [0.0, 0.58, 1.0],
  );

  /// The floor vignette that sinks the bottom of the stage into the room.
  RadialGradient get vignette => RadialGradient(
    center: const Alignment(0, 1.4),
    radius: 1.3,
    colors: [
      (isDark ? const Color(0xFF000000) : groundShadow).withValues(
        alpha: isDark ? 0.9 : 0.16,
      ),
      (isDark ? const Color(0xFF000000) : groundShadow).withValues(alpha: 0),
    ],
    stops: const [0.0, 0.62],
  );

  /// Time-of-day wash over the stage — the prototype's `atmoMap`.
  RadialGradient atmosphere(MedPeriod period) {
    final (Color tint, double alpha, double y, double radius) = switch (period) {
      MedPeriod.morning => (const Color(0xFF689EB2), 0.22, -0.52, 1.15),
      MedPeriod.afternoon => (const Color(0xFFC4A674), 0.17, -0.32, 1.15),
      MedPeriod.evening => (const Color(0xFFC67852), 0.16, -0.04, 1.08),
      MedPeriod.night => (const Color(0xFF4C68A8), 0.15, 0.20, 1.05),
    };
    return RadialGradient(
      center: Alignment(0, y),
      radius: radius,
      colors: [
        tint.withValues(alpha: alpha * atmosphereAlpha),
        tint.withValues(alpha: 0),
      ],
      stops: const [0.0, 0.6],
    );
  }

  /// Panel state caption colour for a phase.
  Color stateColor(MedOrbitPhase phase) => switch (phase) {
    MedOrbitPhase.taken => stateTaken,
    MedOrbitPhase.inactive => stateInactive,
    MedOrbitPhase.next => accent,
    MedOrbitPhase.pending => statePending,
  };
}

/// The orbit phase for a dose, from the app's own dose-state engine.
///
/// [isNext] is the day's first still-pending dose, which the prototype promotes
/// to the visual hero; every other mapping follows [DoseAvailabilityState]
/// exactly, so the drawing can never disagree with the engine.
MedOrbitPhase medOrbitPhaseOf(
  DoseStateResult state, {
  required bool isNext,
}) => switch (state.state) {
  DoseAvailabilityState.completed => MedOrbitPhase.taken,
  DoseAvailabilityState.skipped ||
  DoseAvailabilityState.missed ||
  DoseAvailabilityState.readOnly => MedOrbitPhase.inactive,
  DoseAvailabilityState.actionable =>
    isNext ? MedOrbitPhase.next : MedOrbitPhase.pending,
  DoseAvailabilityState.upcoming ||
  DoseAvailabilityState.futureDate => MedOrbitPhase.pending,
};
