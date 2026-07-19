// Pure-Dart model for the map's Location Intelligence comparison.
//
// Framework-free, mirroring `risk_attributions.dart`. Compares the user's
// profile city against the nearest OTHER supported city by real distance
// (`city_distance_service.dart`) — never a fabricated neighbourhood. Both
// sides are real, already-computed signals: the latest stored estimate and
// the deterministic 6-week trend for each city.

import 'package:fyp_foreseeme/features/risk/domain/models/risk_estimate_model.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/trend_direction.dart';

/// A real two-city comparison: the user's own area vs. the nearest other
/// supported city, both backed by stored estimates.
class LocationComparison {
  final String yourCity;
  final RiskEstimateModel yourEstimate;
  final TrendDirection yourTrend;

  final String nearbyCity;
  final RiskEstimateModel nearbyEstimate;
  final TrendDirection nearbyTrend;

  const LocationComparison({
    required this.yourCity,
    required this.yourEstimate,
    required this.yourTrend,
    required this.nearbyCity,
    required this.nearbyEstimate,
    required this.nearbyTrend,
  });

  /// Signed AQI difference (nearby − yours). Positive means the nearby city's
  /// air quality index reads higher (worse).
  int get aqiDelta => (nearbyEstimate.aqi - yourEstimate.aqi).round();

  /// True when the two cities currently sit at the same risk level.
  bool get sameLevel => yourEstimate.riskLevel == nearbyEstimate.riskLevel;
}
