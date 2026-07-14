// Pure-Dart EPA Air Quality Index banding.
//
// Framework-free: imports NO `package:flutter`. Mirrors the other risk domain
// services (`risk_driver_service`, `risk_staleness`) — a deterministic pure
// function over the estimate's own stored `aqi` value. Boundaries follow the
// standard US EPA breakpoints (https://www.airnow.gov/aqi/aqi-basics/).

/// EPA AQI category for a stored [RiskEstimateModel.aqi] value.
enum AqiBand {
  good,
  moderate,
  unhealthyForSensitiveGroups,
  unhealthy,
  veryUnhealthy,
  hazardous,
}

extension AqiBandX on AqiBand {
  /// Short plain-language label, e.g. "Moderate".
  String get label => switch (this) {
    AqiBand.good => 'Good',
    AqiBand.moderate => 'Moderate',
    AqiBand.unhealthyForSensitiveGroups => 'Unhealthy for sensitive groups',
    AqiBand.unhealthy => 'Unhealthy',
    AqiBand.veryUnhealthy => 'Very unhealthy',
    AqiBand.hazardous => 'Hazardous',
  };
}

/// Classifies [aqi] against the standard EPA breakpoints (inclusive lower
/// bound). Negative/unusual values clamp to [AqiBand.good] rather than
/// throwing — the tile degrades gracefully, it never crashes the screen.
AqiBand aqiBandFor(double aqi) {
  if (aqi <= 50) return AqiBand.good;
  if (aqi <= 100) return AqiBand.moderate;
  if (aqi <= 150) return AqiBand.unhealthyForSensitiveGroups;
  if (aqi <= 200) return AqiBand.unhealthy;
  if (aqi <= 300) return AqiBand.veryUnhealthy;
  return AqiBand.hazardous;
}
