import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fyp_foreseeme/core/safety/content_safety_guard.dart';
import 'package:fyp_foreseeme/core/services/launcher_service.dart';
import 'package:fyp_foreseeme/features/insights/data/repositories/static_recommendation_repository.dart';
import 'package:fyp_foreseeme/features/insights/domain/models/health_recommendation.dart';
import 'package:fyp_foreseeme/features/insights/domain/repositories/recommendation_repository.dart';
import 'package:fyp_foreseeme/features/insights/presentation/insights_providers.dart';
import 'package:fyp_foreseeme/features/auth/presentation/auth_providers.dart';
import 'package:fyp_foreseeme/features/resources/presentation/resources_providers.dart';
import 'package:fyp_foreseeme/features/resources/presentation/widgets/emergency_card.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_estimate_model.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/trend_direction.dart';
import 'package:fyp_foreseeme/features/risk/presentation/risk_provider.dart';
import 'package:fyp_foreseeme/features/risk/presentation/screens/risk_details_screen.dart';

/// A repository that returns whatever it is handed — used to feed the guard a
/// deliberately un-sourced advisory (the "what if a future entry forgets its
/// citation" case).
class _FixedRecommendationRepository implements RecommendationRepository {
  const _FixedRecommendationRepository(this.value);
  final HealthRecommendation value;

  @override
  HealthRecommendation lookup(String category, String driver) => value;
}

/// Records dial targets so the emergency affordance's tap can be asserted
/// without a device.
class _RecordingLauncher implements LauncherService {
  final List<String> dialled = [];

  @override
  Future<bool> dialPhone(String number) async {
    dialled.add(number);
    return true;
  }

  @override
  Future<bool> openExternalUrl(String url) async => true;
}

const _citedRec = HealthRecommendation(
  id: 'rec-resp-air',
  category: 'respiratory',
  driver: 'Air quality',
  text: 'Limit outdoor exertion and keep a mask handy.',
  source: 'WHO — Air pollution',
  sourceUrl: 'https://www.who.int/health-topics/air-pollution',
  deepLink: '/resources',
  escalation: 'If breathing worsens, seek care; emergency → Rescue 1122.',
);

RiskEstimateModel _est(String level) => RiskEstimateModel.fromJson({
  'city': 'Lahore',
  'riskLevel': level,
  'disease': 'Smog',
  'confidence': 0.89,
  'temperature': 30.0,
  'humidity': 40.0,
  'aqi': 184.0,
  'generatedAt': '2026-06-30T00:00:00.000Z',
  'modelVersion': 'rf-v1',
});

Widget _riskDetails({
  required RiskEstimateModel estimate,
  LauncherService? launcher,
}) {
  return ProviderScope(
    overrides: [
      currentCityRiskProvider.overrideWith((ref) async => estimate),
      currentCityRiskHistoryProvider.overrideWith((ref) async => const []),
      riskTrendProvider.overrideWith((ref) async => TrendDirection.insufficient),
      currentRecommendationProvider.overrideWith((ref) => _citedRec),
      if (launcher != null)
        launcherServiceProvider.overrideWithValue(launcher),
    ],
    child: const MaterialApp(home: RiskDetailsScreen()),
  );
}

void main() {
  group('ContentSafetyGuard', () {
    test('isCited requires a non-empty source and an https url', () {
      expect(
        ContentSafetyGuard.isCited(source: 'WHO', sourceUrl: 'https://who.int'),
        isTrue,
      );
      expect(
        ContentSafetyGuard.isCited(source: '', sourceUrl: 'https://who.int'),
        isFalse,
      );
      expect(
        ContentSafetyGuard.isCited(source: 'WHO', sourceUrl: ''),
        isFalse,
      );
      expect(
        ContentSafetyGuard.isCited(source: 'WHO', sourceUrl: 'ftp://who.int'),
        isFalse,
      );
    });

    test('requireCited throws ContentSafetyViolation on an un-sourced advisory', () {
      expect(
        () => ContentSafetyGuard.requireCited(
          label: 'x',
          source: '',
          sourceUrl: '',
        ),
        throwsA(isA<ContentSafetyViolation>()),
      );
      // A cited advisory passes silently.
      ContentSafetyGuard.requireCited(
        label: 'x',
        source: 'WHO',
        sourceUrl: 'https://who.int',
      );
    });
  });

  group('recommendation library is cited-only (Rule 11)', () {
    test('every library entry carries a valid citation', () {
      for (final rec in StaticRecommendationRepository.all) {
        expect(
          ContentSafetyGuard.isCited(
            source: rec.source,
            sourceUrl: rec.sourceUrl,
          ),
          isTrue,
          reason: '${rec.id} must be cited',
        );
      }
    });

    test('lookup only ever returns fixed library entries — never generated', () {
      const repo = StaticRecommendationRepository();
      final library = StaticRecommendationRepository.all;

      // A wide matrix, including junk and empty keys, must always resolve to an
      // object already in the fixed library (proving nothing is synthesised).
      const categories = [
        'respiratory',
        'cardiovascular',
        '*',
        '',
        'unknown',
        'RESPIRATORY',
      ];
      const drivers = [
        'Air quality',
        'Heat',
        'Respiratory',
        '*',
        '',
        'Nonsense',
      ];

      for (final c in categories) {
        for (final d in drivers) {
          final rec = repo.lookup(c, d);
          expect(
            library.any((e) => identical(e, rec)),
            isTrue,
            reason: 'lookup("$c","$d") returned a non-library object',
          );
          expect(
            ContentSafetyGuard.isCited(
              source: rec.source,
              sourceUrl: rec.sourceUrl,
            ),
            isTrue,
          );
        }
      }
    });
  });

  group('currentRecommendationProvider runtime guard', () {
    /// Resolves [currentRecommendationProvider] to a settled AsyncValue with the
    /// given repository, signed out (risk → null → `lookup('*','*')`).
    Future<AsyncValue<HealthRecommendation>> resolve(
      HealthRecommendation supplied,
    ) async {
      final container = ProviderContainer(
        overrides: [
          authStateProvider.overrideWith((ref) => Stream.value(null)),
          recommendationRepositoryProvider.overrideWithValue(
            _FixedRecommendationRepository(supplied),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.listen(currentRecommendationProvider, (_, _) {},
          fireImmediately: true);
      await pumpEventQueue(); // drain the async chain to a settled value
      return container.read(currentRecommendationProvider);
    }

    test('surfaces a ContentSafetyViolation for an un-sourced advisory', () async {
      const unsourced = HealthRecommendation(
        id: 'rec-bad',
        category: '*',
        driver: '*',
        text: 'Some advice with no citation.',
        source: '',
        sourceUrl: '',
        deepLink: '/resources',
        escalation: 'emergency → Rescue 1122.',
      );

      final result = await resolve(unsourced);

      expect(result.hasError, isTrue);
      expect(result.error, isA<ContentSafetyViolation>());
    });

    test('passes through a properly cited advisory', () async {
      final result = await resolve(_citedRec);

      expect(result.hasError, isFalse);
      expect(result.value?.id, 'rec-resp-air');
    });
  });

  group('emergency affordance on high risk', () {
    testWidgets('renders and dials Rescue 1122 on a High estimate', (
      tester,
    ) async {
      final launcher = _RecordingLauncher();
      await tester.pumpWidget(
        _riskDetails(estimate: _est('High'), launcher: launcher),
      );
      await tester.pumpAndSettle();

      expect(find.byType(EmergencyCard), findsOneWidget);

      await tester.tap(find.byType(EmergencyCard));
      await tester.pumpAndSettle();
      expect(launcher.dialled, ['1122']);
    });

    testWidgets('is absent on a Low estimate', (tester) async {
      await tester.pumpWidget(_riskDetails(estimate: _est('Low')));
      await tester.pumpAndSettle();

      expect(find.byType(EmergencyCard), findsNothing);
    });
  });
}
