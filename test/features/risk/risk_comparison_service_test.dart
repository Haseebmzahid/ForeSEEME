import 'package:flutter_test/flutter_test.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_estimate_model.dart';
import 'package:fyp_foreseeme/features/risk/domain/services/risk_comparison_service.dart';

RiskEstimateModel _e({
  required String city,
  required RiskLevel level,
  required String disease,
  double confidence = 0.7,
  bool lowConfidence = false,
  DateTime? at,
}) => RiskEstimateModel(
  city: city,
  riskLevel: level,
  disease: disease,
  confidence: confidence,
  temperature: 30,
  humidity: 60,
  aqi: 100,
  generatedAt: at ?? DateTime.utc(2026, 6, 28),
  modelVersion: 'rf-1.0.0',
  lowConfidence: lowConfidence,
);

void main() {
  group('severity helpers', () {
    test('rank orders Low < Medium < High', () {
      expect(severityRank(RiskLevel.low), lessThan(severityRank(RiskLevel.medium)));
      expect(severityRank(RiskLevel.medium), lessThan(severityRank(RiskLevel.high)));
    });

    test('fraction maps to thirds', () {
      expect(severityFraction(RiskLevel.low), closeTo(1 / 3, 1e-9));
      expect(severityFraction(RiskLevel.high), 1.0);
    });
  });

  group('rankCitiesBySeverity', () {
    test('orders most-severe first, ties broken by confidence then name', () {
      final ranked = rankCitiesBySeverity([
        _e(city: 'Islamabad', level: RiskLevel.low, disease: 'Influenza'),
        _e(city: 'Karachi', level: RiskLevel.high, disease: 'Smog', confidence: 0.6),
        _e(city: 'Lahore', level: RiskLevel.high, disease: 'Dengue', confidence: 0.9),
        _e(city: 'Peshawar', level: RiskLevel.medium, disease: 'Smog'),
      ]);

      expect(ranked.map((e) => e.city).toList(), [
        'Lahore', // High, conf 0.9
        'Karachi', // High, conf 0.6
        'Peshawar', // Medium
        'Islamabad', // Low
      ]);
    });

    test('does not mutate the input list', () {
      final input = [
        _e(city: 'A', level: RiskLevel.low, disease: 'X'),
        _e(city: 'B', level: RiskLevel.high, disease: 'Y'),
      ];
      rankCitiesBySeverity(input);
      expect(input.first.city, 'A'); // original order intact
    });
  });

  group('summarizeDiseasesForCity', () {
    test('groups by disease → latest level + weeks observed, empty on none', () {
      expect(summarizeDiseasesForCity(const []), isEmpty);

      final history = [
        // Dengue seen twice; most recent is High on Jun 28.
        _e(city: 'Lahore', level: RiskLevel.medium, disease: 'Dengue',
            at: DateTime.utc(2026, 6, 14)),
        _e(city: 'Lahore', level: RiskLevel.high, disease: 'Dengue',
            at: DateTime.utc(2026, 6, 28)),
        // Smog seen once, Low.
        _e(city: 'Lahore', level: RiskLevel.low, disease: 'Smog',
            at: DateTime.utc(2026, 6, 21)),
      ];

      final summary = summarizeDiseasesForCity(history);

      expect(summary, hasLength(2));
      // Sorted by latest severity: Dengue (High) before Smog (Low).
      expect(summary.first.disease, 'Dengue');
      expect(summary.first.latestLevel, RiskLevel.high);
      expect(summary.first.latestAt, DateTime.utc(2026, 6, 28)); // most recent
      expect(summary.first.weeksObserved, 2);

      expect(summary[1].disease, 'Smog');
      expect(summary[1].latestLevel, RiskLevel.low);
      expect(summary[1].weeksObserved, 1);
    });

    test('carries the latest estimate low-confidence flag', () {
      final summary = summarizeDiseasesForCity([
        _e(city: 'Quetta', level: RiskLevel.low, disease: 'Influenza',
            lowConfidence: true, at: DateTime.utc(2026, 6, 28)),
      ]);
      expect(summary.single.latestLowConfidence, isTrue);
    });
  });
}
