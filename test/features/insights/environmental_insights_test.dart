import 'package:flutter_test/flutter_test.dart';
import 'package:fyp_foreseeme/features/insights/domain/services/environmental_insights.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_attributions.dart';

FeatureContribution _c(
  String feature,
  double magnitude, {
  ContributionDirection direction = ContributionDirection.increases,
}) => FeatureContribution(
  feature: feature,
  contribution: direction == ContributionDirection.increases ? magnitude : -magnitude,
  magnitude: magnitude,
  direction: direction,
  value: 0,
);

RiskAttributions _attr(List<FeatureContribution> top) => RiskAttributions(
  method: 'tree_path_contributions',
  modelVersion: 'rf-1.0.0',
  disease: 'dengue',
  predictedClass: 'High',
  baseValue: 0.33,
  topContributors: top,
  confidenceRationale: const ConfidenceRationale(
    confidence: 0.8,
    predictedClass: 'High',
    runnerUpClass: 'Medium',
    runnerUpConfidence: 0.15,
    margin: 0.65,
    agreement: 0.9,
    strength: ConfidenceStrength.strong,
    lowConfidence: false,
  ),
);

void main() {
  test('null attributions → no drivers', () {
    expect(deriveEnvironmentalDrivers(null), isEmpty);
  });

  test('reflects the real attributions and preserves their ranked order', () {
    final drivers = deriveEnvironmentalDrivers(
      _attr([
        _c('temperature', 0.44),
        _c('humidity_lag1', 0.20, direction: ContributionDirection.decreases),
        _c('us_aqi', 0.10),
      ]),
    );

    expect(drivers.map((d) => d.feature).toList(), [
      'temperature',
      'humidity_lag1',
      'us_aqi',
    ]);
    // Human labels come from the shared explanation templater.
    expect(drivers[0].label, 'Temperature');
    expect(drivers[1].label, 'Humidity (previous week)');
    expect(drivers[0].direction, ContributionDirection.increases);
    expect(drivers[1].direction, ContributionDirection.decreases);
    expect(drivers[0].magnitude, 0.44);
  });

  test('excludes non-environmental features (city, cyclical, availability)', () {
    final drivers = deriveEnvironmentalDrivers(
      _attr([
        _c('city_Lahore', 0.9),
        _c('week_sin', 0.8),
        _c('aqi_available', 0.7),
        _c('temperature', 0.5),
        _c('humidity', 0.4),
      ]),
    );
    expect(drivers.map((d) => d.feature).toList(), ['temperature', 'humidity']);
  });

  test('respects the limit (top-N environmental only)', () {
    final drivers = deriveEnvironmentalDrivers(
      _attr([
        _c('temperature', 0.5),
        _c('humidity', 0.4),
        _c('us_aqi', 0.3),
        _c('precipitation', 0.2),
      ]),
      limit: 2,
    );
    expect(drivers, hasLength(2));
    expect(drivers.map((d) => d.feature).toList(), ['temperature', 'humidity']);
  });

  test('isEnvironmentalFeature classification', () {
    expect(isEnvironmentalFeature('temperature'), isTrue);
    expect(isEnvironmentalFeature('humidity_roll3'), isTrue);
    expect(isEnvironmentalFeature('city_Karachi'), isFalse);
    expect(isEnvironmentalFeature('week_cos'), isFalse);
    expect(isEnvironmentalFeature('aqi_available'), isFalse);
  });
}
