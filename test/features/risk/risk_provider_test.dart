import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fyp_foreseeme/features/risk/data/repositories/fake_risk_repository.dart';
import 'package:fyp_foreseeme/features/risk/data/repositories/firestore_risk_repository.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_estimate_model.dart';
import 'package:fyp_foreseeme/features/risk/presentation/risk_provider.dart';

void main() {
  group('latestRiskForCityProvider overridden with FakeRiskRepository', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer(
        overrides: [
          riskRepositoryProvider.overrideWithValue(FakeRiskRepository()),
        ],
      );
      addTearDown(container.dispose);
    });

    test('returns the expected estimate for each seeded risk level', () async {
      final high = await container.read(
        latestRiskForCityProvider('Lahore').future,
      );
      final medium = await container.read(
        latestRiskForCityProvider('Karachi').future,
      );
      final low = await container.read(
        latestRiskForCityProvider('Islamabad').future,
      );

      expect(high?.riskLevel, RiskLevel.high);
      expect(medium?.riskLevel, RiskLevel.medium);
      expect(low?.riskLevel, RiskLevel.low);
      expect(low?.lowConfidence, isTrue);
    });

    test('returns null for a city with no estimate', () async {
      final result = await container.read(
        latestRiskForCityProvider('Nowhere').future,
      );
      expect(result, isNull);
    });

    test('honours a custom seed override', () async {
      final custom = ProviderContainer(
        overrides: [
          riskRepositoryProvider.overrideWithValue(
            FakeRiskRepository(
              seed: {
                'Quetta': RiskEstimateModel(
                  city: 'Quetta',
                  riskLevel: RiskLevel.medium,
                  disease: 'Respiratory Illness',
                  confidence: 0.7,
                  temperature: 29.0,
                  humidity: 40.0,
                  aqi: 100.0,
                  generatedAt: DateTime.utc(2026, 6, 28),
                  modelVersion: 'stub-0.0.0',
                ),
              },
            ),
          ),
        ],
      );
      addTearDown(custom.dispose);

      final result = await custom.read(
        latestRiskForCityProvider('Quetta').future,
      );
      expect(result?.city, 'Quetta');
      expect(result?.riskLevel, RiskLevel.medium);
    });
  });

  group('FirestoreRiskRepository.modelFromSnapshotData', () {
    test('parses a sample document with an ISO-8601 generatedAt', () {
      final data = <String, dynamic>{
        'city': 'Lahore',
        'riskLevel': 'High',
        'disease': 'Dengue',
        'confidence': 0.87,
        'temperature': 34.5,
        'humidity': 62.0,
        'aqi': 180.0,
        'generatedAt': '2026-06-28T00:00:00.000Z',
        'modelVersion': 'rf-v1.2',
        'lowConfidence': false,
      };

      final model = FirestoreRiskRepository.modelFromSnapshotData(data);

      expect(model.city, 'Lahore');
      expect(model.riskLevel, RiskLevel.high);
      expect(model.disease, 'Dengue');
      expect(model.confidence, 0.87);
      expect(model.aqi, 180.0);
      expect(model.generatedAt, DateTime.utc(2026, 6, 28));
      expect(model.modelVersion, 'rf-v1.2');
    });

    test('normalises a Firestore Timestamp generatedAt to UTC', () {
      final data = <String, dynamic>{
        'city': 'Karachi',
        'riskLevel': 'Medium',
        'disease': 'Heat-Related Illness',
        'confidence': 0.6,
        'temperature': 33.0,
        'humidity': 55.0,
        'aqi': 120.0,
        'generatedAt': Timestamp.fromDate(DateTime.utc(2026, 6, 28, 12, 30)),
        'modelVersion': 'stub-0.0.0',
      };

      final model = FirestoreRiskRepository.modelFromSnapshotData(data);

      expect(model.riskLevel, RiskLevel.medium);
      expect(model.generatedAt, DateTime.utc(2026, 6, 28, 12, 30));
      // Optional field absent from the document defaults to false.
      expect(model.lowConfidence, isFalse);
    });
  });
}
