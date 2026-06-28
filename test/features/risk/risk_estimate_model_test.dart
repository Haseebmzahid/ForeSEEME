import 'package:flutter_test/flutter_test.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_estimate_model.dart';

void main() {
  // A representative estimate. `generatedAt` is UTC so equality is offset-stable.
  RiskEstimateModel sample() => RiskEstimateModel(
    city: 'Lahore',
    riskLevel: RiskLevel.high,
    disease: 'Dengue',
    confidence: 0.87,
    temperature: 34.5,
    humidity: 62.0,
    aqi: 180.0,
    generatedAt: DateTime.utc(2026, 6, 28, 0, 0, 0),
    modelVersion: 'rf-v1.2',
    lowConfidence: false,
  );

  group('RiskEstimateModel serialisation', () {
    test('fromJson(toJson(x)) round-trips losslessly', () {
      final original = sample();

      final restored = RiskEstimateModel.fromJson(original.toJson());

      expect(restored, original);
      expect(restored.hashCode, original.hashCode);
    });

    test('round-trips the optional lowConfidence flag when true', () {
      final original = sample().copyWith(lowConfidence: true, confidence: 0.41);

      final restored = RiskEstimateModel.fromJson(original.toJson());

      expect(restored, original);
      expect(restored.lowConfidence, isTrue);
    });

    test('lowConfidence defaults to false when absent from JSON', () {
      final json = sample().toJson()..remove('lowConfidence');

      final restored = RiskEstimateModel.fromJson(json);

      expect(restored.lowConfidence, isFalse);
    });
  });

  group('RiskLevel', () {
    test('serialises to the contract strings', () {
      expect(RiskLevel.low.toJson(), 'Low');
      expect(RiskLevel.medium.toJson(), 'Medium');
      expect(RiskLevel.high.toJson(), 'High');
    });

    test('deserialises the contract strings', () {
      expect(RiskLevelX.fromJson('Low'), RiskLevel.low);
      expect(RiskLevelX.fromJson('Medium'), RiskLevel.medium);
      expect(RiskLevelX.fromJson('High'), RiskLevel.high);
    });

    test('falls back to low for unknown / null values', () {
      expect(RiskLevelX.fromJson('bogus'), RiskLevel.low);
      expect(RiskLevelX.fromJson(null), RiskLevel.low);
    });
  });

  group('RiskEstimateModel.docId', () {
    test('uses the {city}_{YYYY-MM-DD} composite convention', () {
      expect(sample().docId, 'Lahore_2026-06-28');
    });

    test('derives the date from the UTC day of generatedAt', () {
      // 2026-06-28T23:30 in UTC+6 is still 2026-06-28 in UTC.
      final model = sample().copyWith(
        generatedAt: DateTime.utc(2026, 6, 28, 23, 30),
      );
      expect(model.docId, 'Lahore_2026-06-28');
    });
  });

  group('RiskEstimateModel equality', () {
    test('two estimates with identical fields are equal', () {
      expect(sample(), sample());
    });

    test('differing on any field breaks equality', () {
      expect(sample(), isNot(sample().copyWith(confidence: 0.5)));
      expect(sample(), isNot(sample().copyWith(riskLevel: RiskLevel.low)));
      expect(sample(), isNot(sample().copyWith(city: 'Karachi')));
    });
  });
}
