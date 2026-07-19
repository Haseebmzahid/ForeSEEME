import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/features/health_profile/presentation/health_profile_providers.dart';
import 'package:fyp_foreseeme/features/insights/domain/models/health_recommendation.dart';
import 'package:fyp_foreseeme/features/insights/domain/services/environmental_insights.dart';
import 'package:fyp_foreseeme/features/insights/presentation/insights_providers.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_attributions.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_estimate_model.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/trend_direction.dart';
import 'package:fyp_foreseeme/features/risk/presentation/screens/risk_map_screen.dart';

RiskEstimateModel _est() => RiskEstimateModel(
  city: 'Lahore',
  riskLevel: RiskLevel.high,
  disease: 'Dengue',
  confidence: 0.8,
  temperature: 34,
  humidity: 60,
  aqi: 210,
  generatedAt: DateTime.utc(2026, 7, 18),
  modelVersion: 'rf-1.0.0',
);

const _rec = HealthRecommendation(
  id: 'rec-resp-air',
  category: 'respiratory',
  driver: 'Air quality',
  text: 'Keep windows closed during peak smog.',
  source: 'WHO — Air pollution',
  sourceUrl: 'https://www.who.int/health-topics/air-pollution',
  deepLink: '/resources',
  escalation: 'If breathing worsens, seek care; emergency → Rescue 1122.',
);

void main() {
  // `flutter_riverpod` 3.3.1 doesn't export the `Override` type name, so
  // `overrides` stays untyped here — `ProviderScope` performs its own runtime
  // check (mirrors the local-function pattern in pipeline_e2e_test.dart).
  Widget wrap(Widget child, {required dynamic overrides}) => ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: ForeSeeMeTheme.light,
      home: Scaffold(body: child),
    ),
  );

  testWidgets(
    'shows the primary contributor, trend, and cited recommendation for the tapped city',
    (tester) async {
      final view = AreaInsightView(
        estimate: _est(),
        trend: TrendDirection.rising,
        primaryDriver: const EnvironmentalDriver(
          feature: 'us_aqi',
          label: 'Air quality (AQI)',
          direction: ContributionDirection.increases,
          magnitude: 0.3,
        ),
        recommendation: _rec,
      );

      await tester.pumpWidget(
        wrap(
          CityDetailSheet(estimate: _est()),
          overrides: [
            userCityProvider.overrideWith((ref) async => null),
            areaInsightProvider(
              'Lahore',
            ).overrideWith((ref) async => view),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('PRIMARY CONTRIBUTOR'), findsOneWidget);
      expect(find.text('Air quality (AQI)'), findsOneWidget);
      expect(find.text('Rising'), findsOneWidget);
      expect(
        find.text('Keep windows closed during peak smog.'),
        findsOneWidget,
      );
      expect(find.text('Source: WHO — Air pollution'), findsOneWidget);
      expect(find.text('Learn more'), findsOneWidget);
    },
  );

  testWidgets('no attributions → "Not available" instead of a fabricated driver', (
    tester,
  ) async {
    final view = AreaInsightView(
      estimate: _est(),
      trend: TrendDirection.stable,
      primaryDriver: null,
      recommendation: _rec,
    );

    await tester.pumpWidget(
      wrap(
        CityDetailSheet(estimate: _est()),
        overrides: [
          userCityProvider.overrideWith((ref) async => null),
          areaInsightProvider('Lahore').overrideWith((ref) async => view),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Not available'), findsOneWidget);
  });

  testWidgets('no estimate for the tapped city → extras hidden entirely', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        CityDetailSheet(estimate: _est()),
        overrides: [
          userCityProvider.overrideWith((ref) async => null),
          areaInsightProvider('Lahore').overrideWith((ref) async => null),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('PRIMARY CONTRIBUTOR'), findsNothing);
    // The base sheet (unaffected) still renders.
    expect(find.text('Lahore'), findsOneWidget);
  });
}
