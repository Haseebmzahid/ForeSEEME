import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fyp_foreseeme/features/insights/data/repositories/static_recommendation_repository.dart';
import 'package:fyp_foreseeme/features/insights/domain/models/health_recommendation.dart';
import 'package:fyp_foreseeme/features/insights/domain/services/recommendation_mapper.dart';
import 'package:fyp_foreseeme/features/insights/presentation/insights_providers.dart';
import 'package:fyp_foreseeme/features/insights/presentation/recommendations_card.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_estimate_model.dart';
import 'package:fyp_foreseeme/features/risk/presentation/risk_provider.dart';

const _repo = StaticRecommendationRepository();

RiskEstimateModel _risk(String disease) => RiskEstimateModel.fromJson({
  'city': 'Lahore',
  'riskLevel': 'High',
  'disease': disease,
  'confidence': 0.8,
  'temperature': 30.0,
  'humidity': 40.0,
  'aqi': 180.0,
  'generatedAt': '2026-06-30T00:00:00.000Z',
  'modelVersion': 'rf-v1',
});

/// Resolves a recommendation exactly as the provider does (mapper + repo).
HealthRecommendation _resolve(List<String> conditions, String disease) {
  final key = resolveKey(conditions, disease);
  return _repo.lookup(key.category ?? '*', key.driver);
}

void main() {
  group('recommendation_mapper.resolveKey (deterministic §5 mapping)', () {
    test('asthma + smog → respiratory / Air quality', () {
      expect(
        resolveKey(['Asthma'], 'Smog'),
        const RecommendationKey(category: 'respiratory', driver: 'Air quality'),
      );
    });

    test('heart disease + heat → cardiovascular / Heat', () {
      expect(
        resolveKey(['Heart Disease'], 'Heat-Related Illness'),
        const RecommendationKey(category: 'cardiovascular', driver: 'Heat'),
      );
    });

    test('diabetes + smog → cardiovascular / Air quality', () {
      expect(
        resolveKey(['Diabetes'], 'Smog'),
        const RecommendationKey(
          category: 'cardiovascular',
          driver: 'Air quality',
        ),
      );
    });

    test('multi-condition uses category priority (respiratory first)', () {
      expect(
        resolveKey(['Heart Disease', 'Asthma'], 'Smog').category,
        'respiratory',
      );
    });

    test('no vulnerability match → null category (still a real driver)', () {
      // Asthma is respiratory; heat only makes cardiovascular vulnerable.
      final key = resolveKey(['Asthma'], 'Heat-Related Illness');
      expect(key.category, isNull);
      expect(key.driver, 'Heat');
    });

    test('none / empty conditions → null category', () {
      expect(resolveKey(['None'], 'Dengue').category, isNull);
      expect(resolveKey([], 'Smog').category, isNull);
    });

    test('unknown disease falls back to the default driver', () {
      expect(resolveKey(['Asthma'], 'Mystery').driver, kDefaultDriver);
    });
  });

  group('StaticRecommendationRepository.lookup (cited, total)', () {
    test('known keys map to the expected cited entries', () {
      expect(_repo.lookup('respiratory', 'Air quality').id, 'rec-resp-air');
      expect(
        _repo.lookup('respiratory', 'Respiratory').id,
        'rec-resp-seasonal',
      );
      expect(
        _repo.lookup('cardiovascular', 'Air quality').id,
        'rec-cardio-air',
      );
      expect(_repo.lookup('cardiovascular', 'Heat').id, 'rec-cardio-heat');
    });

    test('unmatched (category, driver) → cited default', () {
      expect(_repo.lookup('respiratory', 'Heat').id, 'rec-default');
      expect(_repo.lookup('*', '*').id, 'rec-default');
      expect(_repo.lookup('nonsense', 'nonsense').id, 'rec-default');
    });

    test('end-to-end {conditions × disease} → expected cited entry', () {
      expect(_resolve(['Asthma'], 'Smog').id, 'rec-resp-air');
      expect(_resolve(['Diabetes'], 'Smog').id, 'rec-cardio-air');
      expect(
        _resolve(['Heart Disease'], 'Heat-Related Illness').id,
        'rec-cardio-heat',
      );
      expect(_resolve(['Asthma'], 'Influenza').id, 'rec-resp-seasonal');
      // No match → safe generic, sourced default.
      expect(_resolve(['None'], 'Dengue').id, 'rec-default');
      expect(_resolve([], 'Smog').id, 'rec-default');
    });
  });

  group('integrity guarantees (recommendation_rules.md §Integrity)', () {
    test('every entry carries a non-empty source and an https sourceUrl', () {
      for (final rec in StaticRecommendationRepository.all) {
        expect(rec.source, isNotEmpty, reason: '${rec.id} source');
        expect(rec.sourceUrl, startsWith('https://'), reason: '${rec.id} url');
        expect(rec.text, isNotEmpty, reason: '${rec.id} text');
        expect(rec.escalation, isNotEmpty, reason: '${rec.id} escalation');
        expect(rec.deepLink, isNotEmpty, reason: '${rec.id} deepLink');
      }
    });

    test('every escalation routes to professional/emergency help', () {
      for (final rec in StaticRecommendationRepository.all) {
        expect(
          rec.escalation.toLowerCase(),
          anyOf(contains('emergency'), contains('seek'), contains('consult')),
          reason: '${rec.id} must route to help',
        );
      }
    });

    test('lookups only ever return library entries — nothing generated', () {
      // Every resolvable input must yield a text that is verbatim one of the
      // fixed library entries (never composed free-text).
      final libraryTexts = StaticRecommendationRepository.all
          .map((r) => r.text)
          .toSet();
      const diseases = [
        'Smog',
        'Respiratory Illness',
        'Influenza',
        'Heat-Related Illness',
        'Dengue',
        'Mystery',
      ];
      const conditionSets = [
        <String>[],
        ['None'],
        ['Asthma'],
        ['Diabetes'],
        ['Heart Disease'],
        ['Hypertension'],
        ['Asthma', 'Heart Disease'],
      ];
      for (final d in diseases) {
        for (final c in conditionSets) {
          expect(libraryTexts, contains(_resolve(c, d).text));
        }
      }
    });
  });

  group('currentRecommendationProvider', () {
    test('composes current risk + conditions into a cited entry', () async {
      final container = ProviderContainer(
        overrides: [
          currentCityRiskProvider.overrideWith((ref) async => _risk('Smog')),
          userConditionsProvider.overrideWith((ref) async => ['Asthma']),
        ],
      );
      addTearDown(container.dispose);

      final rec = await container.read(currentRecommendationProvider.future);
      expect(rec.id, 'rec-resp-air');
    });

    test('no current estimate → cited default', () async {
      final container = ProviderContainer(
        overrides: [currentCityRiskProvider.overrideWith((ref) async => null)],
      );
      addTearDown(container.dispose);

      final rec = await container.read(currentRecommendationProvider.future);
      expect(rec.id, 'rec-default');
    });

    test('risk present but no matching condition → cited default', () async {
      final container = ProviderContainer(
        overrides: [
          currentCityRiskProvider.overrideWith(
            (ref) async => _risk('Heat-Related Illness'),
          ),
          userConditionsProvider.overrideWith((ref) async => ['Asthma']),
        ],
      );
      addTearDown(container.dispose);

      final rec = await container.read(currentRecommendationProvider.future);
      expect(rec.id, 'rec-default');
    });
  });

  group('RecommendationsCard', () {
    Widget wrap(HealthRecommendation rec) => ProviderScope(
      overrides: [currentRecommendationProvider.overrideWith((ref) => rec)],
      child: const MaterialApp(home: Scaffold(body: RecommendationsCard())),
    );

    testWidgets('renders the advisory text, cited source and escalation', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(_resolve(['Asthma'], 'Smog')));
      await tester.pumpAndSettle();

      expect(find.textContaining('N95/FFP2 mask'), findsOneWidget);
      expect(find.text('Source: WHO — Air pollution'), findsOneWidget);
      expect(find.textContaining('Rescue 1122'), findsOneWidget);
      expect(find.text('Learn more'), findsOneWidget);
    });

    testWidgets('default recommendation still shows a source and help route', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(_resolve(['None'], 'Dengue')));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('not personal medical advice'),
        findsOneWidget,
      );
      expect(find.text('Source: US EPA — AirNow AQI'), findsOneWidget);
      expect(
        find.textContaining('consult a healthcare professional'),
        findsOneWidget,
      );
    });
  });
}
