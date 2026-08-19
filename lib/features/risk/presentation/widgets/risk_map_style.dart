import 'package:flutter/material.dart';

import 'package:fyp_foreseeme/features/risk/domain/models/risk_estimate_model.dart';

/// Visual language for the **Risk Map screen only**, transcribed from the
/// approved prototype (`docs/Design/ForeSeeMe Risk Map.html`).
///
/// Why this is local rather than in the app palette: the prototype specifies an
/// environmental instrument surface — near-black map bed, glass panels, a teal
/// interface accent and a map-specific risk ramp — that deliberately differs
/// from the app's product palette. Promoting these values to
/// `ForeSeeMePalette` would restyle every other screen, so they live here and
/// are consumed only by the Risk Map.
///
/// `RiskVisuals` is untouched and still owns risk identity everywhere else
/// (including this screen's labels and icons); this class only supplies the
/// map bed's own rendering of that same level.
@immutable
class RiskMapTheme {
  const RiskMapTheme({
    required this.mapBg,
    required this.ink,
    required this.ink2,
    required this.panel,
    required this.sheet,
    required this.sheetCell,
    required this.hair,
    required this.btn,
    required this.vignette,
    required this.horizonHaze,
    required this.labelPlate,
    required this.mapStyle,
  });

  /// Map bed / frame background.
  final Color mapBg;

  /// Primary text on the map surface.
  final Color ink;

  /// Muted technical text.
  final Color ink2;

  /// Floating glass panel fill.
  final Color panel;

  /// Bottom sheet fill.
  final Color sheet;

  /// Telemetry cell fill inside the sheet.
  final Color sheetCell;

  /// Hairline rule / panel border.
  final Color hair;

  /// Inset button fill.
  final Color btn;

  /// Edge vignette terminal colour.
  final Color vignette;

  /// Mid-stop of the top horizon haze.
  final Color horizonHaze;

  /// Backing plate behind an on-map label.
  final Color labelPlate;

  /// Google Maps JSON style for this bed.
  final String mapStyle;

  /// The prototype's interface accent (`#4FBFAE`) and its lighter interaction
  /// state (`#7BD8C9`). Constant across both beds.
  static const Color accent = Color(0xFF4FBFAE);
  static const Color accentBright = Color(0xFF7BD8C9);

  static const RiskMapTheme dark = RiskMapTheme(
    mapBg: Color(0xFF0A1012),
    ink: Color(0xFFE7EFF0),
    ink2: Color(0xFF8798A0),
    panel: Color(0xCC0B1214), // rgba(11,18,20,.80)
    sheet: Color(0xE60A1012), // rgba(10,16,18,.90)
    sheetCell: Color(0xF00D1416), // rgba(13,20,22,.94)
    hair: Color(0x1FE7EFF0), // rgba(231,239,240,.12)
    btn: Color(0x14E7EFF0), // rgba(231,239,240,.08)
    vignette: Color(0xB8040809), // rgba(4,8,9,.72)
    horizonHaze: Color(0x9E0E1C20), // rgba(14,28,32,.62)
    labelPlate: Color(0xAD080D0F), // rgba(8,13,15,.68)
    mapStyle: _darkMapStyle,
  );

  static const RiskMapTheme light = RiskMapTheme(
    mapBg: Color(0xFFEDF1F0),
    ink: Color(0xFF0E1618),
    ink2: Color(0xFF5D6E72),
    panel: Color(0xDBFAFCFB), // rgba(250,252,251,.86)
    sheet: Color(0xF0F9FBFA), // rgba(249,251,250,.94)
    sheetCell: Color(0xFAF6F9F8), // rgba(246,249,248,.98)
    hair: Color(0x1F0E1618), // rgba(14,22,24,.12)
    btn: Color(0x0F0E1618), // rgba(14,22,24,.06)
    vignette: Color(0x47788A8C), // rgba(120,138,140,.28)
    horizonHaze: Color(0xA8E2E9E7), // rgba(226,233,231,.66)
    labelPlate: Color(0xC7FCFDFD), // rgba(252,253,253,.78)
    mapStyle: _lightMapStyle,
  );

  static RiskMapTheme of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;

  bool get isDark => mapBg.computeLuminance() < 0.5;
}

/// How a risk level is drawn **on the map bed**: the prototype's own ramp, its
/// layer count, and its per-layer base alpha.
///
/// Layer count is the point: intensity is carried by how many stacked contours
/// a region has, so the field still reads in greyscale and for colour-blind
/// users — colour is never the only channel.
@immutable
class RiskFieldStyle {
  const RiskFieldStyle({
    required this.label,
    required this.color,
    required this.layers,
    required this.alpha,
  });

  final String label;
  final Color color;

  /// Number of stacked contours drawn for this level.
  final int layers;

  /// Base fill alpha of the innermost contour.
  final double alpha;

  static const RiskFieldStyle low = RiskFieldStyle(
    label: 'LOW',
    color: Color(0xFF3FB786),
    layers: 2,
    alpha: 0.055,
  );
  static const RiskFieldStyle medium = RiskFieldStyle(
    label: 'MEDIUM',
    color: Color(0xFFE3A63F),
    layers: 4,
    alpha: 0.065,
  );
  static const RiskFieldStyle high = RiskFieldStyle(
    label: 'HIGH',
    color: Color(0xFFE4574B),
    layers: 6,
    alpha: 0.075,
  );

  /// Low-confidence / no model coverage — a dashed, barely-tinted field.
  static const RiskFieldStyle unknown = RiskFieldStyle(
    label: 'UNKNOWN',
    color: Color(0xFF8794A0),
    layers: 1,
    alpha: 0.03,
  );

  /// Legend order, low → unknown.
  static const List<RiskFieldStyle> all = [low, medium, high, unknown];

  /// The field style for an estimate. A low-confidence estimate renders as
  /// [unknown], mirroring `RiskVisuals.of` so the field and the written label
  /// on the same screen can never disagree.
  static RiskFieldStyle of(RiskLevel level, {bool lowConfidence = false}) {
    if (lowConfidence) return unknown;
    return switch (level) {
      RiskLevel.low => low,
      RiskLevel.medium => medium,
      RiskLevel.high => high,
    };
  }

  bool get isUnknown => identical(this, unknown);

  /// Radius multiplier of contour [z], from the prototype's shrink ramp
  /// (`k = 1 - z * (0.13 - (layers > 4 ? 0.02 : 0))`).
  double shrinkFor(int z) => 1 - z * (0.13 - (layers > 4 ? 0.02 : 0));

  /// Fill alpha of contour [z]; a selected region's field reads hotter.
  double fillAlphaFor(int z, {required bool selected}) {
    if (isUnknown) return 0.025;
    return alpha * (1 - z * 0.08) * (selected ? 1.3 : 0.8);
  }

  /// Stroke alpha of contour [z].
  double strokeAlphaFor({required bool selected}) {
    if (isUnknown) return 0.32;
    return selected ? 0.9 : 0.62;
  }
}

// ── Google Maps beds ─────────────────────────────────────────────────────────
//
// Transcribed from the prototype's `THEMES` map. Values that the prototype
// expresses as translucent ink over land are pre-composited to the opaque hex
// the Maps SDK requires. Deliberately NOT `kDarkMapStyle`: that constant is
// shared with the Nearby Hospitals map, and this bed is specific to the Risk
// Map's environmental treatment.

const String _darkMapStyle = '''
[
  {"elementType":"geometry","stylers":[{"color":"#111a1c"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#8798a0"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#0a1012"}]},
  {"elementType":"labels.icon","stylers":[{"visibility":"off"}]},
  {"featureType":"administrative","elementType":"geometry","stylers":[{"color":"#333c3e"}]},
  {"featureType":"administrative.country","elementType":"labels.text.fill","stylers":[{"color":"#b9c7ca"}]},
  {"featureType":"administrative.land_parcel","stylers":[{"visibility":"off"}]},
  {"featureType":"landscape.man_made","elementType":"geometry","stylers":[{"color":"#0d1517"}]},
  {"featureType":"poi","stylers":[{"visibility":"off"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#262f31"}]},
  {"featureType":"road.arterial","elementType":"geometry","stylers":[{"color":"#3c4546"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#515a5c"}]},
  {"featureType":"road","elementType":"labels","stylers":[{"visibility":"off"}]},
  {"featureType":"transit","stylers":[{"visibility":"off"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#122730"}]},
  {"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#5d7278"}]}
]
''';

const String _lightMapStyle = '''
[
  {"elementType":"geometry","stylers":[{"color":"#e2e9e7"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#5d6e72"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#edf1f0"}]},
  {"elementType":"labels.icon","stylers":[{"visibility":"off"}]},
  {"featureType":"administrative","elementType":"geometry","stylers":[{"color":"#c6c7c6"}]},
  {"featureType":"administrative.country","elementType":"labels.text.fill","stylers":[{"color":"#3f5054"}]},
  {"featureType":"administrative.land_parcel","stylers":[{"visibility":"off"}]},
  {"featureType":"landscape.man_made","elementType":"geometry","stylers":[{"color":"#e9eeec"}]},
  {"featureType":"poi","stylers":[{"visibility":"off"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#fcfdfd"}]},
  {"featureType":"road.arterial","elementType":"geometry","stylers":[{"color":"#ffffff"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#ffffff"}]},
  {"featureType":"road","elementType":"labels","stylers":[{"visibility":"off"}]},
  {"featureType":"transit","stylers":[{"visibility":"off"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#cfe0e4"}]},
  {"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#7d969c"}]}
]
''';
