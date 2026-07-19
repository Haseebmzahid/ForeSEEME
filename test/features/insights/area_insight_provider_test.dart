import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fyp_foreseeme/features/auth/presentation/auth_providers.dart';
import 'package:fyp_foreseeme/features/insights/presentation/insights_providers.dart';
import 'package:fyp_foreseeme/features/risk/data/repositories/fake_risk_repository.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_attributions.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_estimate_model.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/trend_direction.dart';
import 'package:fyp_foreseeme/features/risk/presentation/risk_provider.dart';

RiskEstimateModel _est({
  bool withAttributions = true,
  DateTime? at,
}) => RiskEstimateModel(
  city: 'Lahore',
  riskLevel: RiskLevel.high,
  disease: 'Dengue',
  confidence: 0.85,
  temperature: 34,
  humidity: 60,
  aqi: 210,
  generatedAt: at ?? DateTime.utc(2026, 7, 18),
  modelVersion: 'rf-1.0.0',
  attributions: withAttributions
      ? const RiskAttributions(
          method: 'tree_path',
          modelVersion: 'rf-1.0.0',
          disease: 'Dengue',
          predictedClass: 'High',
          baseValue: 0.3,
          topContributors: [
            FeatureContribution(
              feature: 'us_aqi',
              contribution: 0.3,
              magnitude: 0.3,
              direction: ContributionDirection.increases,
              value: 210,
            ),
          ],
          confidenceRationale: ConfidenceRationale(
            confidence: 0.85,
            predictedClass: 'High',
            runnerUpClass: 'Medium',
            runnerUpConfidence: 0.1,
            margin: 0.7,
            agreement: 0.9,
            strength: ConfidenceStrength.strong,
            lowConfidence: false,
          ),
        )
      : null,
);

void main() {
  final signedOut = authStateProvider.overrideWith((ref) => Stream.value(null));

  group('areaInsightProvider', () {
    test('composes trend + primary driver + a cited recommendation', () async {
      final container = ProviderContainer(
        overrides: [
          signedOut,
          riskRepositoryProvider.overrideWithValue(
            FakeRiskRepository(seed: {'Lahore': _est()}),
          ),
        ],
      );
      addTearDown(container.dispose);

      final view = await container.read(areaInsightProvider('Lahore').future);

      expect(view, isNotNull);
      expect(view!.estimate.city, 'Lahore');
      expect(view.trend, TrendDirection.insufficient); // single-point history
      expect(view.primaryDriver?.feature, 'us_aqi');
      // Always resolves to at least the cited default — never un-sourced.
      expect(view.recommendation.source, isNotEmpty);
      expect(view.recommendation.sourceUrl, startsWith('https://'));
    });

    test('an estimate with no attributions → null primary driver, not a crash', () async {
      final container = ProviderContainer(
        overrides: [
          signedOut,
          riskRepositoryProvider.overrideWithValue(
            FakeRiskRepository(
              seed: {'Lahore': _est(withAttributions: false)},
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final view = await container.read(areaInsightProvider('Lahore').future);
      expect(view, isNotNull);
      expect(view!.primaryDriver, isNull);
    });

    test('a city with no estimate yet → null view, no fabricated insight', () async {
      final container = ProviderContainer(
        overrides: [
          signedOut,
          riskRepositoryProvider.overrideWithValue(FakeRiskRepository(seed: {})),
        ],
      );
      addTearDown(container.dispose);

      expect(
        await container.read(areaInsightProvider('Karachi').future),
        isNull,
      );
    });
  });
}
