import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fyp_foreseeme/features/health_profile/presentation/health_profile_providers.dart';
import 'package:fyp_foreseeme/features/risk/data/repositories/fake_risk_repository.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_estimate_model.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/trend_direction.dart';
import 'package:fyp_foreseeme/features/risk/presentation/risk_provider.dart';

RiskEstimateModel _est(
  String city,
  RiskLevel level, {
  double aqi = 100,
  DateTime? at,
}) => RiskEstimateModel(
  city: city,
  riskLevel: level,
  disease: 'Dengue',
  confidence: 0.8,
  temperature: 30,
  humidity: 50,
  aqi: aqi,
  generatedAt: at ?? DateTime.utc(2026, 7, 18),
  modelVersion: 'rf-1.0.0',
);

void main() {
  group('locationComparisonProvider', () {
    test('compares your profile city against its nearest other city', () async {
      final container = ProviderContainer(
        overrides: [
          userCityProvider.overrideWith((ref) async => 'Islamabad'),
          riskRepositoryProvider.overrideWithValue(
            FakeRiskRepository(
              seed: {
                'Islamabad': _est('Islamabad', RiskLevel.low, aqi: 60),
                'Rawalpindi': _est('Rawalpindi', RiskLevel.medium, aqi: 90),
              },
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final comparison = await container.read(
        locationComparisonProvider.future,
      );

      expect(comparison, isNotNull);
      expect(comparison!.yourCity, 'Islamabad');
      expect(comparison.nearbyCity, 'Rawalpindi');
      expect(comparison.aqiDelta, 30);
      expect(comparison.sameLevel, isFalse);
      // Single-point history → insufficient trend for both, never a fabricated arrow.
      expect(comparison.yourTrend, TrendDirection.insufficient);
      expect(comparison.nearbyTrend, TrendDirection.insufficient);
    });

    test('no profile city → null, never a partial comparison', () async {
      final container = ProviderContainer(
        overrides: [userCityProvider.overrideWith((ref) async => null)],
      );
      addTearDown(container.dispose);

      expect(await container.read(locationComparisonProvider.future), isNull);
    });

    test('nearby city has no estimate yet → null', () async {
      final container = ProviderContainer(
        overrides: [
          userCityProvider.overrideWith((ref) async => 'Islamabad'),
          riskRepositoryProvider.overrideWithValue(
            FakeRiskRepository(
              seed: {'Islamabad': _est('Islamabad', RiskLevel.low)},
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(await container.read(locationComparisonProvider.future), isNull);
    });
  });
}
