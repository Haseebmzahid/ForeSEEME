import 'package:flutter_test/flutter_test.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_estimate_model.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/trend_direction.dart';
import 'package:fyp_foreseeme/features/risk/domain/services/risk_trend_service.dart';

/// An estimate at week [week] (older = smaller) with the given [level].
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

/// Builds a history (in chronological order) from a list of levels.
List<RiskEstimateModel> seq(List<RiskLevel> levels) => [
  for (var i = 0; i < levels.length; i++) at(i, levels[i]),
];

void main() {
  const low = RiskLevel.low;
  const med = RiskLevel.medium;
  const high = RiskLevel.high;

  group('computeTrend', () {
    test('insufficient for empty or single-point history', () {
      expect(computeTrend(const []), TrendDirection.insufficient);
      expect(computeTrend(seq([high])), TrendDirection.insufficient);
    });

    test('rising when the latest level climbs above the earlier mean', () {
      expect(computeTrend(seq([low, low, med, high])), TrendDirection.rising);
      expect(computeTrend(seq([low, high])), TrendDirection.rising);
      expect(computeTrend(seq([med, high])), TrendDirection.rising);
    });

    test('falling when the latest level drops below the earlier mean', () {
      expect(computeTrend(seq([high, high, med, low])), TrendDirection.falling);
      expect(computeTrend(seq([high, low])), TrendDirection.falling);
    });

    test('stable when flat', () {
      expect(computeTrend(seq([med, med, med])), TrendDirection.stable);
      expect(computeTrend(seq([low, low])), TrendDirection.stable);
      expect(computeTrend(seq([high, high])), TrendDirection.stable);
    });

    test('stable inside the dead-band (delta == 0.5)', () {
      // scores [0,1,1] -> latest 1, prior mean 0.5, delta 0.5 (not > 0.5).
      expect(computeTrend(seq([low, med, med])), TrendDirection.stable);
    });

    test('is order-independent (input shuffled gives the same result)', () {
      final chronological = seq([low, low, med, high]);
      final shuffled = [
        chronological[2],
        chronological[0],
        chronological[3],
        chronological[1],
      ];
      expect(computeTrend(shuffled), TrendDirection.rising);
    });

    test('ignores confidence — trend is purely the level sequence', () {
      final rising = [
        at(0, low),
        at(1, med),
        at(2, high).copyWith(lowConfidence: true, confidence: 0.2),
      ];
      expect(computeTrend(rising), TrendDirection.rising);
    });
  });
}
