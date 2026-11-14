import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fyp_foreseeme/features/disease_explorer/domain/models/disease_risk_estimate.dart';
import 'package:fyp_foreseeme/features/disease_explorer/domain/services/disease_explorer_service.dart';
import 'package:fyp_foreseeme/features/disease_explorer/presentation/disease_explorer_providers.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_estimate_model.dart';
import 'package:fyp_foreseeme/features/risk/data/repositories/firestore_risk_repository.dart';
import 'package:fyp_foreseeme/features/risk/presentation/risk_provider.dart';
import 'fixtures.dart';

void main() {
  test(
    'three independent estimates parse and round trip without changing summary',
    () {
      final original = estimate();
      expect(original.diseaseEstimates.map((e) => e.riskLevel), [
        'Medium',
        'High',
        'Low',
      ]);
      expect(original.disease, 'Smog');
      expect(RiskEstimateModel.fromJson(original.toJson()), original);
      expect(
        original.copyWith(city: 'Karachi').diseaseEstimates,
        original.diseaseEstimates,
      );
      expect(
        () => original.diseaseEstimates.add(original.diseaseEstimates.first),
        throwsUnsupportedError,
      );
      expect(
        () => original.diseaseEstimates.first.probabilities['Low'] = 1,
        throwsUnsupportedError,
      );
    },
  );
  test('legacy and malformed list do not become Low', () {
    expect(estimate(legacy: true).diseaseEstimates, isEmpty);
    expect(
      DiseaseRiskEstimate.parseDocument({
        ...document(),
        'diseaseEstimates': 'bad',
      }),
      isEmpty,
    );
    expect(
      DiseaseExplorerService.estimate(estimate(legacy: true), 'smog'),
      isNull,
    );
  });
  for (final patch in <Map<String, dynamic>>[
    {'riskLevel': 'Invalid'},
    {'confidence': double.nan},
    {'confidence': 1.1},
    {
      'probabilities': {'Low': .1, 'Medium': .1, 'High': .1},
    },
    {
      'probabilities': {'Low': .9, 'Medium': .1, 'High': 0},
    },
    {'status': 'unavailable'},
    {'modelVersion': 'wrong'},
    {'generatedAt': '2020-01-01T00:00:00Z'},
    {'lowConfidence': null},
  ]) {
    test('reject invalid independent entry $patch', () {
      final raw = {...independent('dengue', 'Medium'), ...patch};
      expect(
        DiseaseRiskEstimate.tryParse(
          raw,
          modelVersion: 'rf-1.0.0',
          generatedAt: DateTime.utc(2026, 11, 1),
        ),
        isNull,
      );
    });
  }
  test(
    'duplicate entries fail closed and wrong-disease explanations are excluded',
    () {
      final raw = document();
      final entries = raw['diseaseEstimates'] as List;
      entries.add(independent('dengue', 'Low'));
      expect(DiseaseRiskEstimate.parseDocument(raw).map((e) => e.disease), [
        'smog',
        'influenza',
      ]);
      final single = {
        ...independent('dengue', 'Medium'),
        'attributions': {'disease': 'smog'},
      };
      expect(
        DiseaseRiskEstimate.tryParse(
          single,
          modelVersion: 'rf-1.0.0',
          generatedAt: DateTime.utc(2026, 11, 1),
        )!.attributions,
        isNull,
      );
    },
  );
  test('repository timestamp normalization preserves additive entries', () {
    final raw = document();
    raw['generatedAt'] = Timestamp.fromDate(DateTime.utc(2026, 11, 1));
    expect(
      FirestoreRiskRepository.modelFromSnapshotData(raw).diseaseEstimates,
      hasLength(3),
    );
  });
  test('history excludes dominant-only, other cities, and duplicates', () {
    final docs = [
      estimate(legacy: true),
      estimate(at: DateTime.utc(2026, 11, 2)),
      estimate(city: 'Karachi'),
      estimate(),
      estimate(),
    ];
    final history = DiseaseExplorerService.history(docs, 'Lahore', 'dengue');
    expect(history, hasLength(2));
    expect(history.map((e) => e.riskLevel), ['Medium', 'Medium']);
    expect(history.first.generatedAt, DateTime.utc(2026, 11, 1));
  });
  test('history provider reuses existing city read', () async {
    final calls = <String>[];
    final container = ProviderContainer(
      overrides: [
        riskHistoryProvider.overrideWith((ref, city) async {
          calls.add(city);
          return [estimate(city: city)];
        }),
      ],
    );
    addTearDown(container.dispose);
    await container.read(
      diseaseHistoryProvider((city: 'Karachi', disease: 'dengue')).future,
    );
    await container.read(
      diseaseHistoryProvider((city: 'Karachi', disease: 'smog')).future,
    );
    expect(calls, ['Karachi']);
  });
}
