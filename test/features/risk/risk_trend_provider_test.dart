import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fyp_foreseeme/features/health_profile/presentation/health_profile_providers.dart';
import 'package:fyp_foreseeme/features/risk/data/repositories/fake_risk_repository.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_estimate_model.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/trend_direction.dart';
import 'package:fyp_foreseeme/features/risk/presentation/risk_provider.dart';

RiskEstimateModel at(int week, RiskLevel level) => RiskEstimateModel(
  city: 'Lahore',
  riskLevel: level,
  disease: 'Dengue',
  confidence: 0.8,
  temperature: 30,
  humidity: 50,
  aqi: 100,
  generatedAt: DateTime.utc(2026, 1, 1).add(Duration(days: week * 7)),
  modelVersion: 'rf-1.0.0',
);

void main() {
  const low = RiskLevel.low;
  const med = RiskLevel.medium;
  const high = RiskLevel.high;

  group('FakeRiskRepository.getRiskHistory (additive read)', () {
    test('returns newest-first and caps at weeks; never writes', () async {
      final repo = FakeRiskRepository(
        history: {
          'Lahore': [at(0, low), at(1, med), at(2, med), at(3, high)],
        },
      );

      final history = await repo.getRiskHistory('Lahore', weeks: 3);

      expect(history.length, 3);
      // newest first
      expect(history.first.generatedAt, at(3, high).generatedAt);
      expect(history.last.generatedAt, at(1, med).generatedAt);
      // RiskRepository exposes no write method — this read can't alter the feed.
    });

    test('unknown city yields an empty history', () async {
      final repo = FakeRiskRepository(history: const {});
      expect(await repo.getRiskHistory('Nowhere'), isEmpty);
    });
  });

  group('riskTrendProvider', () {
    ProviderContainer drive(ProviderContainer container) {
      addTearDown(container.dispose);
      container.listen(riskTrendProvider, (_, _) {}, fireImmediately: true);
      return container;
    }

    test('rising history -> TrendDirection.rising', () async {
      final container = drive(
        ProviderContainer(
          overrides: [
            userCityProvider.overrideWith((ref) => 'Lahore'),
            riskRepositoryProvider.overrideWithValue(
              FakeRiskRepository(
                history: {
                  'Lahore': [at(0, low), at(1, low), at(2, med), at(3, high)],
                },
              ),
            ),
          ],
        ),
      );

      expect(
        await container.read(riskTrendProvider.future),
        TrendDirection.rising,
      );
    });

    test('single estimate -> insufficient (not a wrong arrow)', () async {
      final container = drive(
        ProviderContainer(
          overrides: [
            userCityProvider.overrideWith((ref) => 'Lahore'),
            riskRepositoryProvider.overrideWithValue(
              FakeRiskRepository(
                history: {
                  'Lahore': [at(0, high)],
                },
              ),
            ),
          ],
        ),
      );

      expect(
        await container.read(riskTrendProvider.future),
        TrendDirection.insufficient,
      );
    });

    test('no city on file -> insufficient', () async {
      final container = drive(
        ProviderContainer(
          overrides: [
            userCityProvider.overrideWith((ref) => null),
            riskRepositoryProvider.overrideWithValue(FakeRiskRepository()),
          ],
        ),
      );

      expect(
        await container.read(riskTrendProvider.future),
        TrendDirection.insufficient,
      );
    });
  });
}
