import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fyp_foreseeme/features/health_profile/presentation/health_profile_providers.dart';
import 'package:fyp_foreseeme/features/insights/data/repositories/static_recommendation_repository.dart';
import 'package:fyp_foreseeme/features/insights/domain/models/adherence_insights.dart';
import 'package:fyp_foreseeme/features/insights/domain/models/health_recommendation.dart';
import 'package:fyp_foreseeme/features/insights/presentation/health_insights_screen.dart';
import 'package:fyp_foreseeme/features/insights/presentation/insights_providers.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_estimate_model.dart';
import 'package:fyp_foreseeme/features/risk/presentation/risk_provider.dart';

const _repo = StaticRecommendationRepository();

RiskEstimateModel _risk(String disease, String level) =>
    RiskEstimateModel.fromJson({
      'city': 'Lahore',
      'riskLevel': level,
      'disease': disease,
      'confidence': 0.82,
      'temperature': 34.0,
      'humidity': 40.0,
      'aqi': 210.0,
      'generatedAt': '2026-06-30T00:00:00.000Z',
      'modelVersion': 'rf-v1',
    });

/// The always-present non-diagnostic disclaimer, in both states.
final _disclaimer = find.textContaining('not a medical diagnosis');

const _screen = MaterialApp(home: HealthInsightsScreen());

/// Renders on a tall surface so every lazily-built ListView section (down to the
/// disclaimer) is laid out and findable without scrolling.
void _tallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// A ProviderScope in which every composed provider resolves to its empty/
/// no-data state, wrapping the screen.
ProviderScope _emptyStateScope() => ProviderScope(
  overrides: [
    userCityProvider.overrideWith((ref) async => 'Lahore'),
    currentCityRiskProvider.overrideWith((ref) async => null),
    currentRecommendationProvider.overrideWith((ref) => _repo.lookup('*', '*')),
    adherenceInsightsProvider.overrideWith((ref) => AdherenceInsights.empty()),
  ],
  child: _screen,
);

void main() {
  group('HealthInsightsScreen', () {
    testWidgets(
      'composes risk + recommendation + adherence with a disclaimer',
      (tester) async {
        _tallSurface(tester);
        const rec = HealthRecommendation(
          id: 'rec-resp-air',
          category: 'respiratory',
          driver: 'Air quality',
          text: 'Keep windows closed during peak smog.',
          source: 'WHO — Air pollution',
          sourceUrl: 'https://www.who.int/health-topics/air-pollution',
          deepLink: '/resources',
          escalation:
              'If breathing worsens, seek care; emergency → Rescue 1122.',
        );
        const insights = AdherenceInsights(
          currentStreakDays: 4,
          longestStreakDays: 6,
          takenCount: 15,
          missedCount: 1,
          strongestBucket: TimeOfDayBucket.morning,
          focusBucket: TimeOfDayBucket.evening,
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              userCityProvider.overrideWith((ref) async => 'Lahore'),
              currentCityRiskProvider.overrideWith(
                (ref) async => _risk('Smog', 'High'),
              ),
              currentRecommendationProvider.overrideWith((ref) => rec),
              adherenceInsightsProvider.overrideWith((ref) => insights),
            ],
            child: _screen,
          ),
        );
        await tester.pumpAndSettle();

        // Section headers present.
        expect(find.text('ENVIRONMENTAL RISK'), findsOneWidget);
        expect(find.text('WHAT MAY HELP'), findsOneWidget);
        expect(find.text('YOUR ROUTINE'), findsOneWidget);

        // Each composed surface rendered from its existing provider.
        expect(
          find.textContaining('High Risk'),
          findsOneWidget,
        ); // risk headline
        expect(find.text('Source: WHO — Air pollution'), findsOneWidget); // rec
        expect(
          find.text("You're on a 4-day streak"),
          findsOneWidget,
        ); // adherence

        // Disclaimer always present.
        expect(_disclaimer, findsOneWidget);
      },
    );

    testWidgets(
      'empty/no-data states stay descriptive and keep the disclaimer',
      (tester) async {
        _tallSurface(tester);
        await tester.pumpWidget(_emptyStateScope());
        await tester.pumpAndSettle();

        // Risk empty state, default cited rec, adherence invitation — no crash.
        expect(find.text('No risk data yet'), findsOneWidget);
        expect(find.text('Source: US EPA — AirNow AQI'), findsOneWidget);
        expect(find.textContaining('Log a few doses'), findsOneWidget);

        // Disclaimer still present in the empty state.
        expect(_disclaimer, findsOneWidget);
      },
    );

    testWidgets('disclaimer routes users to a professional and emergency', (
      tester,
    ) async {
      _tallSurface(tester);
      await tester.pumpWidget(_emptyStateScope());
      await tester.pumpAndSettle();

      expect(
        find.textContaining('consult a qualified healthcare professional'),
        findsOneWidget,
      );
      expect(find.textContaining('Rescue 1122'), findsWidgets);
    });
  });
}
