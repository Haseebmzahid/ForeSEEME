import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fyp_foreseeme/features/health_profile/presentation/health_profile_providers.dart';
import 'package:fyp_foreseeme/features/risk/data/repositories/fake_risk_repository.dart';
import 'package:fyp_foreseeme/features/risk/data/repositories/firestore_risk_repository.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_attributions.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_estimate_model.dart';
import 'package:fyp_foreseeme/features/risk/domain/repositories/risk_repository.dart';
import 'package:fyp_foreseeme/features/risk/presentation/risk_provider.dart';

/// A repository whose read always throws — stands in for a denied read or an
/// offline read with nothing cached, so the error state can be asserted.
class _ThrowingRiskRepository implements RiskRepository {
  @override
  Future<RiskEstimateModel?> getLatestRiskForCity(String city) async {
    throw Exception('read failed');
  }

  @override
  Future<List<RiskEstimateModel>> getRiskHistory(
    String city, {
    int weeks = 6,
  }) async {
    throw Exception('read failed');
  }

  @override
  Future<List<RiskEstimateModel>> getLatestRiskAllCities(
    List<String> cities,
  ) async {
    throw Exception('read failed');
  }
}

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

  group('currentCityRiskProvider state matrix', () {
    // Registers teardown and listens to [currentCityRiskProvider] so the
    // (chained) async lifecycle is driven to completion; a bare `read(.future)`
    // can otherwise sit in loading and dispose mid-flight in a container test.
    ProviderContainer drive(ProviderContainer container) {
      addTearDown(container.dispose);
      container.listen(
        currentCityRiskProvider,
        (_, _) {},
        fireImmediately: true,
      );
      return container;
    }

    test('data: resolves the estimate for the user\'s city', () async {
      final container = drive(
        ProviderContainer(
          overrides: [
            userCityProvider.overrideWith((ref) => 'Lahore'),
            riskRepositoryProvider.overrideWithValue(FakeRiskRepository()),
          ],
        ),
      );

      final result = await container.read(currentCityRiskProvider.future);

      expect(result, isNotNull);
      expect(result?.city, 'Lahore');
      expect(result?.riskLevel, RiskLevel.high);
    });

    test('empty: city has no estimate yet -> null (no crash)', () async {
      final container = drive(
        ProviderContainer(
          overrides: [
            userCityProvider.overrideWith((ref) => 'Nowhere'),
            riskRepositoryProvider.overrideWithValue(FakeRiskRepository()),
          ],
        ),
      );

      final result = await container.read(currentCityRiskProvider.future);

      expect(result, isNull);
    });

    test(
      'empty: no city on file -> null without hitting the repository',
      () async {
        final container = drive(
          ProviderContainer(
            overrides: [
              userCityProvider.overrideWith((ref) => null),
              riskRepositoryProvider.overrideWithValue(
                _ThrowingRiskRepository(),
              ),
            ],
          ),
        );

        // A null city short-circuits before the (throwing) repository is called.
        final result = await container.read(currentCityRiskProvider.future);

        expect(result, isNull);
      },
    );

    test(
      'error: a failed repository read surfaces as AsyncError, not a crash',
      () async {
        // Asserted on the single-provider read (no chaining): a throwing
        // repository — e.g. a denied read, or offline with nothing cached —
        // drives the provider to AsyncError, which the UI renders as the
        // error/offline state. currentCityRiskProvider simply forwards this.
        // Captured via the AsyncValue listener (not `.future`, which does not
        // settle cleanly on the error path in a container test).
        final container = ProviderContainer(
          overrides: [
            riskRepositoryProvider.overrideWithValue(_ThrowingRiskRepository()),
          ],
        );
        addTearDown(container.dispose);

        // Keep the provider alive (swallowing the surfaced error) and let the
        // failing read propagate, then read the settled AsyncValue.
        container.listen<AsyncValue<RiskEstimateModel?>>(
          latestRiskForCityProvider('Lahore'),
          (_, _) {},
          onError: (_, _) {},
          fireImmediately: true,
        );
        await pumpEventQueue(times: 20);

        final value = container.read(latestRiskForCityProvider('Lahore'));

        expect(value.hasError, isTrue);
        expect(value.error, isA<Exception>());
      },
    );
  });

  group('currentCityExplanationProvider', () {
    RiskEstimateModel withAttributions() => RiskEstimateModel(
      city: 'Lahore',
      riskLevel: RiskLevel.medium,
      disease: 'Dengue',
      confidence: 0.72,
      temperature: 32.6,
      humidity: 76.0,
      aqi: 113.0,
      generatedAt: DateTime.utc(2026, 7, 2),
      modelVersion: 'rf-1.0.0',
      attributions: const RiskAttributions(
        method: 'tree_path_contributions',
        modelVersion: 'rf-1.0.0',
        disease: 'dengue',
        predictedClass: 'Medium',
        baseValue: 0.33,
        topContributors: [
          FeatureContribution(
            feature: 'temperature',
            contribution: 0.44,
            magnitude: 0.44,
            direction: ContributionDirection.increases,
            value: 32.6,
          ),
        ],
        confidenceRationale: ConfidenceRationale(
          confidence: 0.72,
          predictedClass: 'Medium',
          runnerUpClass: 'High',
          runnerUpConfidence: 0.2,
          margin: 0.5,
          agreement: 0.9,
          strength: ConfidenceStrength.moderate,
          lowConfidence: false,
        ),
      ),
    );

    Future<ProviderContainer> containerFor(RiskEstimateModel? estimate) async {
      final container = ProviderContainer(
        overrides: [
          currentCityRiskProvider.overrideWith((ref) async => estimate),
        ],
      );
      addTearDown(container.dispose);
      // Drive the (overridden) async estimate to completion so the derived
      // synchronous provider can read its resolved value.
      await container.read(currentCityRiskProvider.future);
      return container;
    }

    test('templates the stored attributions into a view', () async {
      final container = await containerFor(withAttributions());
      final view = container.read(currentCityExplanationProvider);

      expect(view, isNotNull);
      expect(view!.title, 'Why this estimate?');
      expect(view.drivers.single.label, 'Temperature');
      expect(view.strength, ConfidenceStrength.moderate);
    });

    test('is null when the estimate has no attributions (legacy doc)', () async {
      final legacy = RiskEstimateModel(
        city: 'Lahore',
        riskLevel: RiskLevel.low,
        disease: 'Dengue',
        confidence: 0.6,
        temperature: 20,
        humidity: 50,
        aqi: 80,
        generatedAt: DateTime.utc(2026, 7, 2),
        modelVersion: 'rf-1.0.0',
      );
      final container = await containerFor(legacy);
      expect(container.read(currentCityExplanationProvider), isNull);
    });

    test('is null when there is no estimate', () async {
      final container = await containerFor(null);
      expect(container.read(currentCityExplanationProvider), isNull);
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
